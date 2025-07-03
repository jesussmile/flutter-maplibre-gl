cmake_minimum_required(VERSION 3.22.1)
project(maplibre_lerc)

# Set C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Add the LERC source files
file(GLOB LERC_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/Lerc1Decode/*.cpp"
)

# Add our wrapper files
set(WRAPPER_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc_wrapper.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/Lerc_c_api_impl.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/lerc_jni_bridge.cpp"
)

# Create the shared library
add_library(maplibre_lerc SHARED
    ${LERC_SOURCES}
    ${WRAPPER_SOURCES}
)

# Set include directories
target_include_directories(maplibre_lerc PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib
    ${CMAKE_CURRENT_SOURCE_DIR}/lerc-master/src/LercLib/include
)

# Link required libraries
target_link_libraries(maplibre_lerc
    android
    log
)

# Set compiler flags for optimization
target_compile_options(maplibre_lerc PRIVATE
    -O3
    -fvisibility=hidden
    -DANDROID
)

# Set linker flags
set_target_properties(maplibre_lerc PROPERTIES
    LINK_FLAGS "-Wl,--gc-sections -Wl,--strip-all"
) 