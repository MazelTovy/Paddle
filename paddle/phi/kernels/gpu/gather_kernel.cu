// Copyright (c) 2022 PaddlePaddle Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "paddle/phi/common/bfloat16.h"
#include "paddle/phi/common/float16.h"
#include "paddle/phi/core/kernel_registry.h"
#include "paddle/phi/kernels/funcs/gather.cu.h"
#include "paddle/phi/kernels/gather_kernel.h"

namespace phi {

template <typename T, typename Context>
void GatherKernel(const Context& dev_ctx,
                  const DenseTensor& x,
                  const DenseTensor& index,
                  const Scalar& axis,
                  DenseTensor* out) {
  const auto& index_type = index.dtype();
  auto axis_v = axis.to<int>();
  if (axis_v != 0) {
    if (index_type == phi::DataType::INT32) {
      phi::funcs::GatherV2CUDAFunction<T, int32_t>(
          &x, &index, axis_v, out, dev_ctx);
    } else if (index_type == phi::DataType::INT64) {
      phi::funcs::GatherV2CUDAFunction<T, int64_t>(
          &x, &index, axis_v, out, dev_ctx);
    } else if (index_type == phi::DataType::INT16) {
      phi::funcs::GatherV2CUDAFunction<T, int16_t>(
          &x, &index, axis_v, out, dev_ctx);
    }
    return;
  }

  dev_ctx.template Alloc<T>(out);

  if (x.numel() == 0) return;
  if (index_type == phi::DataType::INT32) {
    phi::funcs::GPUGather<T, int>(dev_ctx, x, index, out);
  } else if (index_type == phi::DataType::INT64) {
    phi::funcs::GPUGather<T, int64_t>(dev_ctx, x, index, out);
  } else if (index_type == phi::DataType::INT16) {
    phi::funcs::GPUGather<T, int16_t>(dev_ctx, x, index, out);
  }
}

}  // namespace phi

PD_REGISTER_KERNEL(gather,
                   GPU,
                   ALL_LAYOUT,
                   phi::GatherKernel,
                   float,
                   double,
                   int64_t,
                   int,
                   int16_t,
                   phi::dtype::float16,
                   phi::dtype::bfloat16) {}
