# Copyright (c) 2016 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

if(WITH_TESTING)
  include(tests/test.cmake) # some generic cmake function for inference
endif()

cc_library(
  paddle_inference_io
  SRCS io.cc
  DEPS paddle_framework ${GLOB_OP_LIB} ${GLOB_OPERATOR_DEPS})

# analysis and tensorrt must be added before creating static library,
# otherwise, there would be undefined reference to them in static library.
add_subdirectory(analysis)
add_subdirectory(utils)
if(TENSORRT_FOUND)
  add_subdirectory(tensorrt)
endif()

if(WITH_LITE)
  add_subdirectory(lite)
endif()

# fluid_modules exclude API-interface of inference/api and inference/capi_exp
get_property(fluid_modules GLOBAL PROPERTY FLUID_MODULES)
get_property(phi_modules GLOBAL PROPERTY PHI_MODULES)
get_property(phi_kernels GLOBAL PROPERTY PHI_KERNELS)
set(utils_modules stringpiece pretty_log string_helper benchmark)

add_subdirectory(api)

# Create static inference library if needed
# All static libs in inference/api
set(STATIC_INFERENCE_API
    paddle_inference_api
    analysis_predictor
    zero_copy_tensor
    reset_tensor_array
    analysis_config
    paddle_pass_builder
    phi
    ${mkldnn_quantizer_cfg})

#windows GPU static library over the limit, so not create_static_lib, and cc_library is dummy
if(WIN32 AND WITH_GPU)
  cc_library(paddle_inference DEPS ${fluid_modules} phi ${STATIC_INFERENCE_API}
                                   ${utils_modules})
else()
  create_static_lib(paddle_inference ${fluid_modules} ${phi_modules}
                    ${phi_kernels} ${STATIC_INFERENCE_API} ${utils_modules})
endif()

if(NOT APPLE)
  # TODO(liuyiqu: Temporarily disable the link flag because it is not support on Mac.
  set(LINK_FLAGS
      "-Wl,--retain-symbols-file ${CMAKE_CURRENT_SOURCE_DIR}/paddle_inference.sym"
  )
  set_target_properties(paddle_inference PROPERTIES LINK_FLAGS "${LINK_FLAGS}")
endif()

# C inference API
add_subdirectory(capi_exp)

if(WITH_TESTING AND WITH_INFERENCE_API_TEST)
  add_subdirectory(tests/api)
endif()

set(SHARED_INFERENCE_SRCS
    io.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/../framework/data_feed.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/../framework/data_feed_factory.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/../framework/dataset_factory.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/api/api.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/api/api_impl.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/api/analysis_predictor.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/api/paddle_infer_contrib.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/api/details/zero_copy_tensor.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/utils/io_utils.cc
    ${PADDLE_CUSTOM_OP_SRCS})

# shared inference library deps
set(SHARED_INFERENCE_DEPS ${fluid_modules} phi analysis_predictor
                          ${utils_modules})

if(WITH_CRYPTO)
  set(SHARED_INFERENCE_DEPS ${SHARED_INFERENCE_DEPS} paddle_crypto)
endif(WITH_CRYPTO)

if(WITH_PSCORE)
  set(SHARED_INFERENCE_DEPS ${SHARED_INFERENCE_DEPS} fleet ps_service
                            tensor_table)
endif()

if(WITH_ONNXRUNTIME)
  set(SHARED_INFERENCE_SRCS
      ${SHARED_INFERENCE_SRCS}
      ${CMAKE_CURRENT_SOURCE_DIR}/api/onnxruntime_predictor.cc)
endif(WITH_ONNXRUNTIME)

# Create shared inference library
cc_library(
  paddle_inference_shared SHARED
  SRCS ${SHARED_INFERENCE_SRCS}
  DEPS ${SHARED_INFERENCE_DEPS})

get_property(os_dependency_modules GLOBAL PROPERTY OS_DEPENDENCY_MODULES)
target_link_libraries(paddle_inference_shared ${os_dependency_modules})
if(WIN32)
  target_link_libraries(paddle_inference_shared gflags)
endif()

set_target_properties(paddle_inference_shared PROPERTIES OUTPUT_NAME
                                                         paddle_inference)
if(NOT APPLE AND NOT WIN32)
  # TODO(liuyiqun): Temporarily disable the link flag because it is not support on Mac.
  if(WITH_CUSTOM_DEVICE)
    set(LINK_FLAGS
        "-Wl,--version-script ${CMAKE_CURRENT_SOURCE_DIR}/paddle_inference_custom_device.map"
    )
  else()
    set(LINK_FLAGS
        "-Wl,--version-script ${CMAKE_CURRENT_SOURCE_DIR}/paddle_inference.map")
  endif()
  set_target_properties(paddle_inference_shared PROPERTIES LINK_FLAGS
                                                           "${LINK_FLAGS}")
  # check symbol hidden
  file(
    WRITE ${CMAKE_CURRENT_BINARY_DIR}/check_symbol.cmake
    "execute_process(COMMAND sh -c \"${CMAKE_CURRENT_SOURCE_DIR}/check_symbol.sh"
    " ${CMAKE_CURRENT_BINARY_DIR}/libpaddle_inference.so\" RESULT_VARIABLE symbol_res)\n"
    "if(NOT \"\${symbol_res}\" STREQUAL \"0\")\n"
    "  message(FATAL_ERROR \"Check symbol failed.\")\n"
    "endif()\n")
  add_custom_command(
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/.check_symbol"
    COMMAND ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_BINARY_DIR}/check_symbol.cmake"
    DEPENDS paddle_inference_shared)
  add_custom_target(check_symbol ALL
                    DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/.check_symbol")
endif()
