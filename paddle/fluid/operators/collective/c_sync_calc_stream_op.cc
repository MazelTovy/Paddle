/* Copyright (c) 2019 PaddlePaddle Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */
#include "paddle/fluid/operators/collective/c_sync_calc_stream_op.h"

namespace paddle {
namespace operators {

class CSyncCalcStreamOpMaker : public framework::OpProtoAndCheckerMaker {
 public:
  void Make() {
    AddInput("X", "(Tensor) Dependency of the variable need to sync");
    AddOutput("Out", "(Tensor) Dependency of the variable need to sync");
    AddComment(R"DOC(
CSyncCalcStream Operator
Call calculation stream synchronization.
)DOC");
  }
};

}  // namespace operators
}  // namespace paddle

namespace ops = paddle::operators;

REGISTER_OP_WITHOUT_GRADIENT(c_sync_calc_stream, ops::CSyncCalcStreamOp,
                             ops::CSyncCalcStreamOpMaker);

REGISTER_OP_CUDA_KERNEL(c_sync_calc_stream, ops::CSyncCalcStreamKernel<float>);

REGISTER_OP_NPU_KERNEL(c_sync_calc_stream, ops::CSyncCalcStreamKernel<float>);

REGISTER_OP_MLU_KERNEL(c_sync_calc_stream, ops::CSyncCalcStreamKernel<float>);
