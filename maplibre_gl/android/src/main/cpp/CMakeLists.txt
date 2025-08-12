cmake_minimum_required(VERSION 3.18.1)

project("triangle_renderer")

# Configure build settings
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Create the triangle renderer native library
add_library(
    triangle_renderer
    SHARED
    triangle_renderer.cpp
    triangle_layer_jni.cpp
)

# Find and link required libraries
find_library(
    log-lib
    log
)

find_library(
    gles-lib
    GLESv2
)

find_library(
    egl-lib
    EGL
)

find_library(
    android-lib
    android
)

# Link libraries to the target
target_link_libraries(
    triangle_renderer
    ${log-lib}
    ${gles-lib}
    ${egl-lib}
    ${android-lib}
)

# Set compile definitions
target_compile_definitions(
    triangle_renderer PRIVATE
    ANDROID=1
)

# Set compile options for optimization
target_compile_options(
    triangle_renderer PRIVATE
    -fvisibility=hidden
    -ffunction-sections
    -fdata-sections
    -O2
)
