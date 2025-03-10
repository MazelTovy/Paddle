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

#include "paddle/fluid/operators/collective/recv_v2_op.h"

#if defined(PADDLE_WITH_ASCEND_CL)
#include "paddle/fluid/platform/collective_helper.h"
#include "paddle/fluid/platform/device/npu/hccl_helper.h"
#endif
#include "paddle/fluid/distributed/collective/ProcessGroup.h"
#include "paddle/phi/api/include/tensor.h"

namespace paddle {
namespace operators {

template <typename T>
class CRecvOpASCENDKernel : public framework::OpKernel<T> {
 public:
  void Compute(const framework::ExecutionContext& ctx) const override {
#if defined(PADDLE_WITH_ASCEND_CL)
    auto out = ctx.Output<framework::LoDTensor>("Out");
    out->mutable_data<T>(out->dims(), ctx.GetPlace());
    void* ptr = reinterpret_cast<void*>(const_cast<T*>(out->data<T>()));
    int numel = out->numel();
    HcclDataType dtype =
        platform::ToHCCLDataType(framework::TransToProtoVarType(out->dtype()));

    int ring_id = ctx.Attr<int>("ring_id");
    auto map = distributed::ProcessGroupMapFromGid::getInstance();
    if (map->has(ring_id)) {
      // Use ProcessGroup
      distributed::ProcessGroup* pg = map->get(ring_id);
      std::vector<phi::DenseTensor> out_tensor;
      out_tensor.emplace_back(*out);
      auto task = pg->Recv(out_tensor, 0);
      return;
    }
    auto place = ctx.GetPlace();
    auto comm =
        paddle::platform::HCCLCommContext::Instance().Get(ring_id, place);

    aclrtStream stream = nullptr;
    auto dev_ctx = platform::DeviceContextPool::Instance().Get(place);
    if (ctx.Attr<bool>("use_calc_stream")) {
      stream = static_cast<platform::NPUDeviceContext*>(dev_ctx)->stream();
    } else {
      stream = comm->stream();
    }

    int nranks = comm->nranks();
    int peer = ctx.Attr<int>("peer");

    PADDLE_ENFORCE_EQ(nranks, 2,
                      platform::errors::InvalidArgument(
                          "The nranks must be 2, but (%d)", nranks));

    int root = peer;

    VLOG(3) << "begin hccl recv, parameter is: "
            << "ring_id:" << ring_id << ", nranks:" << nranks
            << ", peer:" << peer << ", numel:" << numel << ", ptr:" << ptr
            << ", dtype:" << dtype << ", root:" << root
            << ", comm: " << comm->comm() << ", stream: " << stream;

    PADDLE_ENFORCE_NPU_SUCCESS(platform::dynload::HcclBroadcast(
        ptr, numel, dtype, (uint32_t)root, comm->comm(), stream));

#else
    PADDLE_THROW(platform::errors::PreconditionNotMet(
        "PaddlePaddle should compile with NPU."));
#endif
  }
};

}  // namespace operators
}  // namespace paddle

namespace ops = paddle::operators;
namespace plat = paddle::platform;

REGISTER_OP_NPU_KERNEL(recv_v2, ops::CRecvOpASCENDKernel<int>,
                       ops::CRecvOpASCENDKernel<int8_t>,
                       ops::CRecvOpASCENDKernel<float>,
                       ops::CRecvOpASCENDKernel<plat::float16>);
