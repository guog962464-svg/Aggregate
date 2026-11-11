cmake_minimum_required(VERSION 3.22.1)
project(aggregate_node_probe)

add_library(node SHARED IMPORTED)
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(node_library_dir "${CMAKE_CURRENT_LIST_DIR}/../jniLibs")
else()
    set(node_library_dir "${CMAKE_CURRENT_LIST_DIR}/../../allAbis/jniLibs")
endif()
set_target_properties(node PROPERTIES IMPORTED_LOCATION
    "${node_library_dir}/${ANDROID_ABI}/libnode.so")

add_library(aggregate_node_probe SHARED node_probe.cpp)
target_compile_features(aggregate_node_probe PRIVATE cxx_std_20)
target_include_directories(aggregate_node_probe PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../vendor/include/node")
target_link_libraries(aggregate_node_probe node log)
target_link_options(aggregate_node_probe PRIVATE "-Wl,-z,max-page-size=16384")
