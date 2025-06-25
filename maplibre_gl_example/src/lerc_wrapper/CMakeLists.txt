cmake_minimum_required(VERSION 3.10)
project(lerc_wrapper)

# Define the library target
add_library(lerc_wrapper SHARED
    lerc_wrapper.cpp
)

# Set include directories
target_include_directories(lerc_wrapper PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../../lerc-master/src/LercLib
    ${CMAKE_CURRENT_SOURCE_DIR}/../../lerc-master/src/LercLib/include
)

# Add LERC library source files
file(GLOB LERC_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../lerc-master/src/LercLib/*.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/../../lerc-master/src/LercLib/Lerc1Decode/*.cpp
)

target_sources(lerc_wrapper PRIVATE ${LERC_SOURCES})

# Set compiler flags
set_target_properties(lerc_wrapper PROPERTIES
    CXX_STANDARD 14
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO
)

# Link libraries
target_link_libraries(lerc_wrapper
    android
    log
)
