/* Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */

#include "paddle/fluid/framework/op_registry.h"
#include "paddle/fluid/operators/randperm_op.h"

template <typename T>
using kernel =
    paddle::operators::RandpermKernel<paddle::platform::NPUDeviceContext, T>;

REGISTER_OP_NPU_KERNEL(randperm, kernel<int64_t>, kernel<int>, kernel<float>,
                       kernel<double>);
