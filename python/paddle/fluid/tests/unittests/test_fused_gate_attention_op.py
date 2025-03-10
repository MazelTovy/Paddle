# Copyright (c) 2022 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import numpy as np

import paddle
import paddle.nn as nn
from paddle import tensor
import unittest
from op_test import OpTest, convert_float_to_uint16, convert_uint16_to_float
from test_sparse_attention_op import get_cuda_version
from paddle import _C_ops
from paddle.fluid.framework import default_main_program, _enable_legacy_dygraph
from paddle.fluid import core

_enable_legacy_dygraph()


@unittest.skipIf(not core.is_compiled_with_cuda(),
                 "Paddle is not compiled with CUDA")
class TestFusedGateAttentionOp(OpTest):

    def setUp(self):
        self.__class__.op_type = "fused_gate_attention"
        # use autograd to check grad in this unittest.
        self.__class__.no_need_check_grad = True
        self.config()
        self.merge_qkv = self.q_dim == self.kv_dim
        self.generate_input_data()

    def config(self):
        self.dtype = "float32"
        self.has_gating = True
        self.batch_size = 1
        self.msa_len = 3
        self.res_len = 5
        self.q_dim = 6
        self.num_heads = 2
        self.key_dim = 4
        self.m_size = self.res_len
        self.kv_dim = self.q_dim
        self.out_dim = self.q_dim
        self.bias_attr = True

    def generate_input_data(self):

        def _random(shape):
            if self.dtype == "bfloat16":
                data = np.random.random(shape).astype("float32")
                return convert_float_to_uint16(data)
            else:
                return np.random.random(shape).astype(self.dtype)

        np.random.seed(123)
        self.query = _random(
            (self.batch_size, self.msa_len, self.res_len, self.q_dim))
        self.q_weight = _random((self.q_dim, self.num_heads, self.key_dim))
        self.k_weight = _random((self.kv_dim, self.num_heads, self.key_dim))
        self.v_weight = _random((self.kv_dim, self.num_heads, self.key_dim))
        if self.merge_qkv:
            self.key = None
            # (3, self.num_heads, self.key_dim, self.q_dim)
            q_weight_t = np.transpose(self.q_weight, axes=[1, 2, 0])
            k_weight_t = np.transpose(self.k_weight, axes=[1, 2, 0])
            v_weight_t = np.transpose(self.v_weight, axes=[1, 2, 0])
            self.qkv_weight = np.stack([q_weight_t, k_weight_t, v_weight_t])
        else:
            self.key = _random(
                (self.batch_size, self.msa_len, self.m_size, self.kv_dim))
            self.qkv_weight = None

        self.attn_mask = _random(
            (self.batch_size, self.msa_len, 1, 1, self.m_size))

        if self.bias_attr:
            self.nonbatched_bias = _random(
                (self.batch_size, 1, self.num_heads, self.res_len, self.m_size))

        if self.has_gating:
            self.gating_w = _random((self.q_dim, self.num_heads, self.key_dim))
            self.gating_b = _random((self.num_heads, self.key_dim))

        self.output_w = _random((self.num_heads, self.key_dim, self.out_dim))
        self.output_b = _random((self.out_dim))

        self.dout = _random(
            (self.batch_size, self.msa_len, self.res_len, self.q_dim))

    def get_reference_out(self):
        paddle.disable_static(place=paddle.CUDAPlace(0))

        query = paddle.to_tensor(self.query, stop_gradient=False)
        key = query if self.merge_qkv else paddle.to_tensor(self.key,
                                                            stop_gradient=False)
        q_weight = paddle.to_tensor(self.q_weight, stop_gradient=False)
        k_weight = paddle.to_tensor(self.k_weight, stop_gradient=False)
        v_weight = paddle.to_tensor(self.v_weight, stop_gradient=False)
        src_mask = paddle.to_tensor(self.attn_mask, stop_gradient=True)

        c = self.key_dim**(-0.5)
        # [batch_size, msa_len, num_heads, res_len, key_dim]
        q = paddle.einsum('nbqa,ahc->nbqhc', query, q_weight) * c
        # [batch_size, msa_len, num_heads, m_size, key_dim]
        k = paddle.einsum('nbka,ahc->nbkhc', key, k_weight)
        # [batch_size, msa_len, num_heads, m_size, key_dim]
        v = paddle.einsum('nbka,ahc->nbkhc', key, v_weight)

        # [batch_size, msa_len, num_heads, res_len, m_size]
        logits = paddle.einsum('nbqhc,nbkhc->nbhqk', q, k)  # qk_out
        logits = logits + src_mask
        if self.bias_attr:
            nonbatched_bias = paddle.to_tensor(self.nonbatched_bias,
                                               stop_gradient=False)
            logits = logits + nonbatched_bias

        weights = nn.functional.softmax(logits)  # softmax_out
        weighted_avg = paddle.einsum('nbhqk,nbkhc->nbqhc', weights, v)

        if self.has_gating:
            gating_w = paddle.to_tensor(self.gating_w, stop_gradient=False)
            gating_b = paddle.to_tensor(self.gating_b, stop_gradient=False)
            gate_values = paddle.einsum('nbqc,chv->nbqhv', query,
                                        gating_w) + gating_b
            gate_values = nn.functional.sigmoid(gate_values)
            weighted_avg = weighted_avg * gate_values

        output_b = paddle.to_tensor(self.output_b, stop_gradient=False)
        output_w = paddle.to_tensor(self.output_w, stop_gradient=False)

        out = paddle.einsum('nbqhc,hco->nbqo', weighted_avg,
                            output_w) + output_b
        paddle.autograd.backward([out], [paddle.to_tensor(self.dout)],
                                 retain_graph=True)
        if self.merge_qkv:
            return out, query.grad, None
        else:
            return out, query.grad, key.grad

    def get_fused_gate_attention_out(self):
        paddle.disable_static(place=paddle.CUDAPlace(0))

        query = paddle.to_tensor(self.query, stop_gradient=False)
        if self.merge_qkv:
            key = None
            q_weight = None
            k_weight = None
            v_weight = None
            qkv_weight = paddle.to_tensor(self.qkv_weight, stop_gradient=False)
        else:
            key = paddle.to_tensor(self.key, stop_gradient=False)
            q_weight = paddle.to_tensor(self.q_weight, stop_gradient=False)
            k_weight = paddle.to_tensor(self.k_weight, stop_gradient=False)
            v_weight = paddle.to_tensor(self.v_weight, stop_gradient=False)
            qkv_weight = None

        src_mask = paddle.to_tensor(self.attn_mask, stop_gradient=True)

        if self.bias_attr:
            nonbatched_bias = paddle.to_tensor(self.nonbatched_bias,
                                               stop_gradient=False)
        else:
            nonbatched_bias = None
        if self.has_gating:
            gating_w = paddle.to_tensor(self.gating_w, stop_gradient=False)
            gating_b = paddle.to_tensor(self.gating_b, stop_gradient=False)
        else:
            gating_w = None
            gating_b = None

        output_w = paddle.to_tensor(self.output_w, stop_gradient=False)
        output_b = paddle.to_tensor(self.output_b, stop_gradient=False)

        _, _, _, _, _, _, _, out = _C_ops.fused_gate_attention(
            query, key, q_weight, k_weight, v_weight, qkv_weight,
            nonbatched_bias, src_mask, gating_w, gating_b, output_w, output_b,
            'has_gating', self.has_gating, 'merge_qkv', self.merge_qkv)

        paddle.autograd.backward([out], [paddle.to_tensor(self.dout)],
                                 retain_graph=True)
        if key is not None:
            return out, query.grad, key.grad
        else:
            return out, query.grad, None

    def check_output_and_grad(self, atol, rtol):

        def _convert(value):
            if self.dtype == "bfloat16":
                return convert_uint16_to_float(value)
            return value

        output_names = ["out", "query_grad", "key_grad"]
        outputs_ref = self.get_reference_out()
        outputs_fused = self.get_fused_gate_attention_out()
        for i in range(len(outputs_fused)):
            ref_res = outputs_ref[i]
            fused_res = outputs_fused[i]
            if ref_res is not None and fused_res is not None:
                print("Checking {}".format(output_names[i]))
                np.testing.assert_allclose(_convert(ref_res),
                                           _convert(fused_res.numpy()),
                                           atol=atol,
                                           rtol=rtol)

    def test_output_and_grad(self):
        self.check_output_and_grad(atol=1e-5, rtol=1e-5)


class TestMergeQKVLargeBatchSizeCase(TestFusedGateAttentionOp):

    def config(self):
        super().config()
        self.batch_size = 2


class TestSeparatedQKVCase(TestFusedGateAttentionOp):

    def config(self):
        self.dtype = "float32"
        self.has_gating = False
        self.batch_size = 1
        self.msa_len = 3
        self.res_len = 5
        self.q_dim = 6
        self.num_heads = 2
        self.key_dim = 4
        self.m_size = 4
        self.kv_dim = 2
        self.out_dim = self.q_dim
        self.bias_attr = False


class TestMergeQKVNoBiasGatingCase(TestFusedGateAttentionOp):

    def config(self):
        super().config()
        self.has_gating = False
        self.bias_attr = False


class TestMergeQKVFp16Case(TestFusedGateAttentionOp):

    def config(self):
        super().config()
        self.dtype = "float16"

    def test_output_and_grad(self):
        place = core.CUDAPlace(0)
        if core.is_float16_supported(place):
            self.check_output_and_grad(atol=1e-1, rtol=1e-5)


class TestMergeQKVLargeBatchSizeFp16Case(TestMergeQKVFp16Case):

    def config(self):
        super().config()
        self.batch_size = 2


@unittest.skipIf(
    not core.is_compiled_with_cuda() or get_cuda_version() < 11000,
    "core is not compiled with CUDA and cuda version need larger than or equal to 11.3"
)
class TestMergeQKVBF16Case(TestFusedGateAttentionOp):

    def config(self):
        super().config()
        self.dtype = "bfloat16"

    def test_output_and_grad(self):
        self.check_output_and_grad(atol=1e-1, rtol=1e-3)


class TestMergeQKVLargeBatchSizeBF16Case(TestMergeQKVBF16Case):

    def config(self):
        super().config()
        self.batch_size = 2


if __name__ == "__main__":
    unittest.main()
