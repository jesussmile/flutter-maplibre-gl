cmake_minimum_required(VERSION 3.10)
project(lerc_integration)

# Set the path to the LERC wrapper directory
set(LERC_WRAPPER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../src/lerc_wrapper)
set(LERC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../lerc-master)

# Include the LERC wrapper CMakeLists.txt
add_subdirectory(${LERC_WRAPPER_DIR} ${CMAKE_CURRENT_BINARY_DIR}/lerc_wrapper)

# Create a wrapper for Java/Kotlin to access the native library
add_library(lerc_terrain SHARED
    lerc_jni_bridge.cpp
)

# Link with the lerc_wrapper library
target_link_libraries(lerc_terrain
    lerc_wrapper
    android
    log
)

# Set C++ standard
set_target_properties(lerc_terrain PROPERTIES
    CXX_STANDARD 14
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
)
