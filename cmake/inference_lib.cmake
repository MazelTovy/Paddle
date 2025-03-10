# Copyright (c) 2018 PaddlePaddle Authors. All Rights Reserved.
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

# make package for paddle fluid shared and static library
set(PADDLE_INSTALL_DIR
    "${CMAKE_BINARY_DIR}/paddle_install_dir"
    CACHE STRING "A path setting paddle shared and static libraries")

set(PADDLE_INFERENCE_INSTALL_DIR
    "${CMAKE_BINARY_DIR}/paddle_inference_install_dir"
    CACHE STRING "A path setting paddle inference shared and static libraries")

# At present, the size of static lib in Windows is very large,
# so we need to crop the library size.
if(WIN32)
  #todo: remove the option
  option(WITH_STATIC_LIB
         "Compile demo with static/shared library, default use dynamic." OFF)
  if(NOT PYTHON_EXECUTABLE)
    find_package(PythonInterp REQUIRED)
  endif()
endif()

set(COPY_SCRIPT_DIR ${PADDLE_SOURCE_DIR}/cmake)
function(copy TARGET)
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs SRCS DSTS)
  cmake_parse_arguments(copy_lib "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  list(LENGTH copy_lib_SRCS copy_lib_SRCS_len)
  list(LENGTH copy_lib_DSTS copy_lib_DSTS_len)
  if(NOT ${copy_lib_SRCS_len} EQUAL ${copy_lib_DSTS_len})
    message(
      FATAL_ERROR
        "${TARGET} source numbers are not equal to destination numbers")
  endif()
  math(EXPR len "${copy_lib_SRCS_len} - 1")
  foreach(index RANGE ${len})
    list(GET copy_lib_SRCS ${index} src)
    list(GET copy_lib_DSTS ${index} dst)
    if(WIN32) #windows
      file(TO_NATIVE_PATH ${src} native_src)
      file(TO_NATIVE_PATH ${dst} native_dst)
      add_custom_command(
        TARGET ${TARGET}
        POST_BUILD
        COMMAND ${PYTHON_EXECUTABLE} ${COPY_SCRIPT_DIR}/copyfile.py
                ${native_src} ${native_dst})
    else(WIN32) #not windows
      add_custom_command(
        TARGET ${TARGET}
        POST_BUILD
        COMMAND mkdir -p "${dst}"
        COMMAND cp -r "${src}" "${dst}"
        COMMENT "copying ${src} -> ${dst}")
    endif(WIN32) # not windows
  endforeach()
endfunction()

function(copy_part_of_thrid_party TARGET DST)
  if(${CBLAS_PROVIDER} STREQUAL MKLML)
    set(dst_dir "${DST}/third_party/install/mklml")
    if(WIN32)
      copy(
        ${TARGET}
        SRCS ${MKLML_LIB} ${MKLML_IOMP_LIB} ${MKLML_SHARED_LIB}
             ${MKLML_SHARED_IOMP_LIB} ${MKLML_INC_DIR}
        DSTS ${dst_dir}/lib ${dst_dir}/lib ${dst_dir}/lib ${dst_dir}/lib
             ${dst_dir})
    else()
      copy(
        ${TARGET}
        SRCS ${MKLML_LIB} ${MKLML_IOMP_LIB} ${MKLML_INC_DIR}
        DSTS ${dst_dir}/lib ${dst_dir}/lib ${dst_dir})
      if(WITH_STRIP)
        add_custom_command(
          TARGET ${TARGET}
          POST_BUILD
          COMMAND strip -s ${dst_dir}/lib/libiomp5.so
          COMMAND strip -s ${dst_dir}/lib/libmklml_intel.so
          COMMENT "striping libiomp5.so\nstriping libmklml_intel.so")
      endif()
    endif()
  elseif(${CBLAS_PROVIDER} STREQUAL EXTERN_OPENBLAS)
    set(dst_dir "${DST}/third_party/install/openblas")
    if(WIN32)
      copy(
        ${TARGET}
        SRCS ${CBLAS_INSTALL_DIR}/lib ${OPENBLAS_SHARED_LIB}
             ${CBLAS_INSTALL_DIR}/include
        DSTS ${dst_dir} ${dst_dir}/lib ${dst_dir})
    else()
      copy(
        ${TARGET}
        SRCS ${CBLAS_INSTALL_DIR}/lib ${CBLAS_INSTALL_DIR}/include
        DSTS ${dst_dir} ${dst_dir})
    endif()

    if(WITH_SPARSELT)
      set(dst_dir "${DST}/third_party/install/cusparselt")
      copy(
        ${TARGET}
        SRCS ${CUSPARSELT_INC_DIR} ${CUSPARSELT_LIB_DIR}
        DSTS ${dst_dir} ${dst_dir})
    endif()
  endif()

  if(WITH_MKLDNN)
    set(dst_dir "${DST}/third_party/install/mkldnn")
    if(WIN32)
      copy(
        ${TARGET}
        SRCS ${MKLDNN_INC_DIR} ${MKLDNN_SHARED_LIB} ${MKLDNN_LIB}
        DSTS ${dst_dir} ${dst_dir}/lib ${dst_dir}/lib)
    else()
      copy(
        ${TARGET}
        SRCS ${MKLDNN_INC_DIR} ${MKLDNN_SHARED_LIB}
        DSTS ${dst_dir} ${dst_dir}/lib)
      if(WITH_STRIP)
        add_custom_command(
          TARGET ${TARGET}
          POST_BUILD
          COMMAND strip -s ${dst_dir}/lib/libmkldnn.so.0
          COMMENT "striping libmkldnn.so.0")
      endif()
      add_custom_command(
        TARGET ${TARGET}
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E create_symlink libmkldnn.so.0
                ${dst_dir}/lib/libdnnl.so.1
        COMMAND ${CMAKE_COMMAND} -E create_symlink libmkldnn.so.0
                ${dst_dir}/lib/libdnnl.so.2
        COMMENT "Make a symbol link of libmkldnn.so.0")
    endif()
  endif()

  if(WITH_ONNXRUNTIME)
    set(dst_dir "${DST}/third_party/install/onnxruntime")
    copy(
      ${TARGET}
      SRCS ${ONNXRUNTIME_INC_DIR} ${ONNXRUNTIME_LIB_DIR}
      DSTS ${dst_dir} ${dst_dir})

    set(dst_dir "${DST}/third_party/install/paddle2onnx")
    copy(
      ${TARGET}
      SRCS ${PADDLE2ONNX_INC_DIR}/paddle2onnx ${PADDLE2ONNX_LIB_DIR}
      DSTS ${dst_dir}/include ${dst_dir})
  endif()

  set(dst_dir "${DST}/third_party/install/gflags")
  copy(
    ${TARGET}
    SRCS ${GFLAGS_INCLUDE_DIR} ${GFLAGS_LIBRARIES}
    DSTS ${dst_dir} ${dst_dir}/lib)

  set(dst_dir "${DST}/third_party/install/glog")
  copy(
    ${TARGET}
    SRCS ${GLOG_INCLUDE_DIR} ${GLOG_LIBRARIES}
    DSTS ${dst_dir} ${dst_dir}/lib)

  set(dst_dir "${DST}/third_party/install/utf8proc")
  copy(
    ${TARGET}
    SRCS ${UTF8PROC_INSTALL_DIR}/include ${UTF8PROC_LIBRARIES}
    DSTS ${dst_dir} ${dst_dir}/lib)

  if(WITH_CRYPTO)
    set(dst_dir "${DST}/third_party/install/cryptopp")
    copy(
      ${TARGET}
      SRCS ${CRYPTOPP_INCLUDE_DIR} ${CRYPTOPP_LIBRARIES}
      DSTS ${dst_dir} ${dst_dir}/lib)
  endif()

  set(dst_dir "${DST}/third_party/install/xxhash")
  copy(
    ${TARGET}
    SRCS ${XXHASH_INCLUDE_DIR} ${XXHASH_LIBRARIES}
    DSTS ${dst_dir} ${dst_dir}/lib)

  if(NOT PROTOBUF_FOUND OR WIN32)
    set(dst_dir "${DST}/third_party/install/protobuf")
    copy(
      ${TARGET}
      SRCS ${PROTOBUF_INCLUDE_DIR} ${PROTOBUF_LIBRARY}
      DSTS ${dst_dir} ${dst_dir}/lib)
  endif()

  if(LITE_BINARY_DIR)
    set(dst_dir "${DST}/third_party/install/lite")
    copy(
      ${TARGET}
      SRCS ${LITE_BINARY_DIR}/${LITE_OUTPUT_BIN_DIR}/*
      DSTS ${dst_dir})
  endif()
endfunction()

# inference library for only inference
set(inference_lib_deps third_party paddle_inference paddle_inference_c
                       paddle_inference_shared paddle_inference_c_shared)
add_custom_target(inference_lib_dist DEPENDS ${inference_lib_deps})

set(dst_dir "${PADDLE_INFERENCE_INSTALL_DIR}/third_party/threadpool")
copy(
  inference_lib_dist
  SRCS ${THREADPOOL_INCLUDE_DIR}/ThreadPool.h
  DSTS ${dst_dir})

# GPU must copy externalErrorMsg.pb
if(WITH_GPU)
  set(dst_dir "${PADDLE_INFERENCE_INSTALL_DIR}/third_party/externalError/data")
  copy(
    inference_lib_dist
    SRCS ${externalError_INCLUDE_DIR}
    DSTS ${dst_dir})
endif()

if(WITH_XPU)
  set(dst_dir "${PADDLE_INFERENCE_INSTALL_DIR}/third_party/install/xpu")
  copy(
    inference_lib_dist
    SRCS ${XPU_INC_DIR} ${XPU_LIB_DIR}
    DSTS ${dst_dir} ${dst_dir})
endif()

# CMakeCache Info
copy(
  inference_lib_dist
  SRCS ${CMAKE_CURRENT_BINARY_DIR}/CMakeCache.txt
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR})

copy_part_of_thrid_party(inference_lib_dist ${PADDLE_INFERENCE_INSTALL_DIR})

set(src_dir "${PADDLE_SOURCE_DIR}/paddle/fluid")

if(WIN32)
  if(WITH_STATIC_LIB)
    set(paddle_inference_lib
        $<TARGET_FILE_DIR:paddle_inference>/libpaddle_inference.lib
        $<TARGET_FILE_DIR:paddle_inference>/paddle_inference.*)
  else()
    set(paddle_inference_lib
        $<TARGET_FILE_DIR:paddle_inference_shared>/paddle_inference.dll
        $<TARGET_FILE_DIR:paddle_inference_shared>/paddle_inference.lib)
  endif()
  copy(
    inference_lib_dist
    SRCS ${src_dir}/inference/api/paddle_*.h ${paddle_inference_lib}
    DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include
         ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/lib
         ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/lib)
else(WIN32)
  set(paddle_inference_lib
      ${PADDLE_BINARY_DIR}/paddle/fluid/inference/libpaddle_inference.*)
  copy(
    inference_lib_dist
    SRCS ${src_dir}/inference/api/paddle_*.h ${paddle_inference_lib}
    DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include
         ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/lib)
endif(WIN32)

copy(
  inference_lib_dist
  SRCS ${CMAKE_BINARY_DIR}/paddle/fluid/framework/framework.pb.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/internal)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/fluid/framework/io/crypto/cipher.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/crypto/)
include_directories(${CMAKE_BINARY_DIR}/../paddle/fluid/framework/io)

# copy api headers for phi & custom op
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/phi/api/ext/*.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/phi/api/ext/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/phi/api/include/*.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/phi/api/include/
)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/phi/api/all.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/phi/api/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/phi/common/*.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/phi/common/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/phi/core/macros.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/phi/core/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/phi/core/visit_type.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/phi/core/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/utils/any.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/utils/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/utils/optional.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/utils/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/utils/none.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/utils/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/utils/flat_hash_map.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/utils/)
copy(
  inference_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/extension.h
  DSTS ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/include/experimental/)

# the header file of phi is copied to the experimental directory,
# the include path of phi needs to be changed to adapt to inference api path
add_custom_command(
  TARGET inference_lib_dist
  POST_BUILD
  COMMAND ${CMAKE_COMMAND} -P "${PADDLE_SOURCE_DIR}/cmake/phi_header.cmake"
  COMMENT "Change phi header include path to adapt to inference api path")

# CAPI inference library for only inference
set(PADDLE_INFERENCE_C_INSTALL_DIR
    "${CMAKE_BINARY_DIR}/paddle_inference_c_install_dir"
    CACHE STRING "A path setting CAPI paddle inference shared")
copy_part_of_thrid_party(inference_lib_dist ${PADDLE_INFERENCE_C_INSTALL_DIR})

set(src_dir "${PADDLE_SOURCE_DIR}/paddle/fluid")
if(WIN32)
  set(paddle_inference_c_lib
      $<TARGET_FILE_DIR:paddle_inference_c>/paddle_inference_c.*)
else(WIN32)
  set(paddle_inference_c_lib
      ${PADDLE_BINARY_DIR}/paddle/fluid/inference/capi_exp/libpaddle_inference_c.*
  )
endif(WIN32)

copy(
  inference_lib_dist
  SRCS ${src_dir}/inference/capi_exp/pd_*.h ${paddle_inference_c_lib}
  DSTS ${PADDLE_INFERENCE_C_INSTALL_DIR}/paddle/include
       ${PADDLE_INFERENCE_C_INSTALL_DIR}/paddle/lib)

if(WITH_STRIP AND NOT WIN32)
  add_custom_command(
    TARGET inference_lib_dist
    POST_BUILD
    COMMAND
      strip -s
      ${PADDLE_INFERENCE_C_INSTALL_DIR}/paddle/lib/libpaddle_inference_c.so
    COMMAND strip -s
            ${PADDLE_INFERENCE_INSTALL_DIR}/paddle/lib/libpaddle_inference.so
    COMMENT "striping libpaddle_inference_c.so\nstriping libpaddle_inference.so"
  )
endif()

# fluid library for both train and inference
set(fluid_lib_deps inference_lib_dist)
add_custom_target(fluid_lib_dist ALL DEPENDS ${fluid_lib_deps})

set(dst_dir "${PADDLE_INSTALL_DIR}/paddle/fluid")
set(module "inference")
if(WIN32)
  copy(
    fluid_lib_dist
    SRCS ${src_dir}/${module}/*.h ${src_dir}/${module}/api/paddle_*.h
         ${paddle_inference_lib}
    DSTS ${dst_dir}/${module} ${dst_dir}/${module} ${dst_dir}/${module}
         ${dst_dir}/${module})
else()
  copy(
    fluid_lib_dist
    SRCS ${src_dir}/${module}/*.h ${src_dir}/${module}/api/paddle_*.h
         ${paddle_inference_lib}
    DSTS ${dst_dir}/${module} ${dst_dir}/${module} ${dst_dir}/${module})
endif()

set(module "framework")
set(framework_lib_deps framework_proto data_feed_proto trainer_desc_proto)
add_dependencies(fluid_lib_dist ${framework_lib_deps})
copy(
  fluid_lib_dist
  SRCS ${src_dir}/${module}/*.h
       ${src_dir}/${module}/details/*.h
       ${PADDLE_BINARY_DIR}/paddle/fluid/framework/trainer_desc.pb.h
       ${PADDLE_BINARY_DIR}/paddle/fluid/framework/framework.pb.h
       ${PADDLE_BINARY_DIR}/paddle/fluid/framework/data_feed.pb.h
       ${src_dir}/${module}/ir/memory_optimize_pass/*.h
       ${src_dir}/${module}/ir/*.h
       ${src_dir}/${module}/fleet/*.h
  DSTS ${dst_dir}/${module}
       ${dst_dir}/${module}/details
       ${dst_dir}/${module}
       ${dst_dir}/${module}
       ${dst_dir}/${module}
       ${dst_dir}/${module}/ir/memory_optimize_pass
       ${dst_dir}/${module}/ir
       ${dst_dir}/${module}/fleet)

set(module "operators")
copy(
  fluid_lib_dist
  SRCS ${src_dir}/${module}/reader/blocking_queue.h
  DSTS ${dst_dir}/${module}/reader/)

set(module "memory")
copy(
  fluid_lib_dist
  SRCS ${src_dir}/${module}/*.h ${src_dir}/${module}/detail/*.h
       ${src_dir}/${module}/allocation/*.h
  DSTS ${dst_dir}/${module} ${dst_dir}/${module}/detail
       ${dst_dir}/${module}/allocation)

set(module "platform")
set(platform_lib_deps profiler_proto errors)
if(WITH_GPU)
  set(platform_lib_deps ${platform_lib_deps} external_error_proto)
endif(WITH_GPU)

add_dependencies(fluid_lib_dist ${platform_lib_deps})
copy(
  fluid_lib_dist
  SRCS ${src_dir}/${module}/*.h ${src_dir}/${module}/dynload/*.h
       ${src_dir}/${module}/details/*.h
       ${PADDLE_BINARY_DIR}/paddle/fluid/platform/*.pb.h
  DSTS ${dst_dir}/${module} ${dst_dir}/${module}/dynload
       ${dst_dir}/${module}/details ${dst_dir}/${module})

set(module "string")
copy(
  fluid_lib_dist
  SRCS ${PADDLE_SOURCE_DIR}/paddle/utils/${module}/*.h
       ${PADDLE_SOURCE_DIR}/paddle/utils/${module}/tinyformat/*.h
  DSTS ${dst_dir}/${module} ${dst_dir}/${module}/tinyformat)

set(module "imperative")
copy(
  fluid_lib_dist
  SRCS ${src_dir}/${module}/*.h ${src_dir}/${module}/jit/*.h
  DSTS ${dst_dir}/${module} ${dst_dir}/${module}/jit)

set(module "pybind")
copy(
  fluid_lib_dist
  SRCS ${CMAKE_CURRENT_BINARY_DIR}/paddle/fluid/${module}/pybind.h
  DSTS ${dst_dir}/${module})

set(dst_dir "${PADDLE_INSTALL_DIR}/third_party/eigen3")
copy(
  inference_lib_dist
  SRCS ${EIGEN_INCLUDE_DIR}/Eigen/Core ${EIGEN_INCLUDE_DIR}/Eigen/src
       ${EIGEN_INCLUDE_DIR}/unsupported/Eigen
  DSTS ${dst_dir}/Eigen ${dst_dir}/Eigen ${dst_dir}/unsupported)

set(dst_dir "${PADDLE_INSTALL_DIR}/third_party/boost")
copy(
  inference_lib_dist
  SRCS ${BOOST_INCLUDE_DIR}/boost
  DSTS ${dst_dir})

set(dst_dir "${PADDLE_INSTALL_DIR}/third_party/dlpack")
copy(
  inference_lib_dist
  SRCS ${DLPACK_INCLUDE_DIR}/dlpack
  DSTS ${dst_dir})

set(dst_dir "${PADDLE_INSTALL_DIR}/third_party/install/zlib")
copy(
  inference_lib_dist
  SRCS ${ZLIB_INCLUDE_DIR} ${ZLIB_LIBRARIES}
  DSTS ${dst_dir} ${dst_dir}/lib)

# CMakeCache Info
copy(
  fluid_lib_dist
  SRCS ${PADDLE_INFERENCE_INSTALL_DIR}/third_party
       ${CMAKE_CURRENT_BINARY_DIR}/CMakeCache.txt
  DSTS ${PADDLE_INSTALL_DIR} ${PADDLE_INSTALL_DIR})

# paddle fluid version
function(version version_file)
  execute_process(
    COMMAND ${GIT_EXECUTABLE} log --pretty=format:%H -1
    WORKING_DIRECTORY ${PADDLE_SOURCE_DIR}
    OUTPUT_VARIABLE PADDLE_GIT_COMMIT)
  file(
    WRITE ${version_file}
    "GIT COMMIT ID: ${PADDLE_GIT_COMMIT}\n"
    "WITH_MKL: ${WITH_MKL}\n"
    "WITH_MKLDNN: ${WITH_MKLDNN}\n"
    "WITH_GPU: ${WITH_GPU}\n"
    "WITH_ROCM: ${WITH_ROCM}\n"
    "WITH_ASCEND_CL: ${WITH_ASCEND_CL}\n"
    "WITH_ASCEND_CXX11: ${WITH_ASCEND_CXX11}\n"
    "WITH_IPU: ${WITH_IPU}\n")
  if(WITH_GPU)
    file(APPEND ${version_file}
         "CUDA version: ${CUDA_VERSION}\n"
         "CUDNN version: v${CUDNN_MAJOR_VERSION}.${CUDNN_MINOR_VERSION}\n")
  endif()
  if(WITH_ROCM)
    file(APPEND ${version_file}
         "HIP version: v${HIP_MAJOR_VERSION}.${HIP_MINOR_VERSION}\n"
         "MIOpen version: v${MIOPEN_MAJOR_VERSION}.${MIOPEN_MINOR_VERSION}\n")
  endif()
  if(WITH_ASCEND_CL)
    file(APPEND ${version_file}
         "Ascend Toolkit version: ${ASCEND_TOOLKIT_VERSION}\n"
         "Ascend Driver version: ${ASCEND_DRIVER_VERSION}\n")
  endif()
  if(WITH_IPU)
    file(APPEND ${version_file} "PopART version: ${POPART_VERSION}\n")
  endif()
  file(APPEND ${version_file}
       "CXX compiler version: ${CMAKE_CXX_COMPILER_VERSION}\n")
  if(TENSORRT_FOUND)
    file(
      APPEND ${version_file}
      "WITH_TENSORRT: ${TENSORRT_FOUND}\n"
      "TensorRT version: v${TENSORRT_MAJOR_VERSION}.${TENSORRT_MINOR_VERSION}.${TENSORRT_PATCH_VERSION}.${TENSORRT_BUILD_VERSION}\n"
    )
  endif()
  if(WITH_LITE)
    file(APPEND ${version_file} "WITH_LITE: ${WITH_LITE}\n"
                                "LITE_GIT_TAG: ${LITE_GIT_TAG}\n")
  endif()

endfunction()
version(${PADDLE_INSTALL_DIR}/version.txt)
version(${PADDLE_INFERENCE_INSTALL_DIR}/version.txt)
version(${PADDLE_INFERENCE_C_INSTALL_DIR}/version.txt)
