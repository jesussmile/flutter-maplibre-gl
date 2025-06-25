# C++ LERC Wrapper Implementation

This document details the implementation of the C++ wrapper for the LERC (Limited Error Raster Compression) library in the FlightCanvas Terrain plugin.

## Purpose of the Wrapper

The C++ wrapper serves as a bridge between the native LERC library and the Dart FFI (Foreign Function Interface). Its primary purposes are:

1. **Providing a C-compatible API**: The LERC library is written in C++ with complex APIs, while Dart FFI requires C-compatible functions.
2. **Simplifying the Interface**: Reduce the complexity of the LERC API to only what is needed by the Flutter application.
3. **Handling Memory Management**: Ensure proper allocation and deallocation of resources.
4. **Error Handling**: Catch C++ exceptions and translate them to a simpler error reporting mechanism.
5. **Type Conversion**: Handle conversion between LERC's data types and the formats needed by the Flutter application.

## Wrapper Header File

The wrapper interface is defined in `src/lerc_wrapper.h`:

```cpp
#ifndef LERC_WRAPPER_H
#define LERC_WRAPPER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t width;
    uint32_t height;
    uint32_t numBands;
    uint32_t numValidPixels;
    double minValue;
    double maxValue;
    double noDataValue;
} LercInfo;

bool lerc_wrapper_initialize(void);
LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size);
double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info);
void lerc_wrapper_free_info(LercInfo* info);
void lerc_wrapper_free_data(double* data);

#ifdef __cplusplus
}
#endif

#endif // LERC_WRAPPER_H
```

### Key Components:

1. **C Compatibility**:
   - Uses `extern "C"` to prevent C++ name mangling
   - Uses C-compatible types (`uint32_t`, `size_t`, etc.)

2. **LercInfo Struct**:
   - Stores metadata about the LERC data
   - Includes dimensions (width, height) and value range (minValue, maxValue)
   - Provides information about bands and valid pixels

3. **API Functions**:
   - `lerc_wrapper_initialize()`: Initialize the library
   - `lerc_wrapper_get_info()`: Extract metadata from LERC data
   - `lerc_wrapper_decode()`: Decompress LERC data to a double array
   - Memory management functions for cleanup

## Wrapper Implementation

The implementation is in `src/lerc_wrapper.cpp`:

```cpp
#include "lerc_wrapper.h"
#include "Lerc_c_api.h"
#include <cstdio>

bool lerc_wrapper_initialize() {
    return true;
}

LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size) {
    try {
        unsigned int infoArray[10];
        double dataRangeArray[3];
        
        lerc_status status = lerc_getBlobInfo(
            buffer,
            static_cast<unsigned int>(size),
            infoArray,
            dataRangeArray,
            10,
            3
        );
        
        if (status != 0) return nullptr;

        auto* info = new LercInfo{
            infoArray[3],  // width
            infoArray[4],  // height
            infoArray[5],  // numBands
            infoArray[6],  // numValidPixels
            dataRangeArray[0],  // minValue
            dataRangeArray[1],  // maxValue
            -9999.0  // noDataValue (default)
        };
        
        return info;
    } catch (...) {
        return nullptr;
    }
}
```

### Core Functions Explained

#### 1. Initialization

```cpp
bool lerc_wrapper_initialize() {
    return true;
}
```

This function is a placeholder for initialization code. In this implementation, it simply returns true as the LERC library does not require explicit initialization.

#### 2. Getting LERC Metadata

```cpp
LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size) {
    try {
        unsigned int infoArray[10];
        double dataRangeArray[3];
        
        lerc_status status = lerc_getBlobInfo(
            buffer,
            static_cast<unsigned int>(size),
            infoArray,
            dataRangeArray,
            10,
            3
        );
        
        if (status != 0) return nullptr;

        auto* info = new LercInfo{
            infoArray[3],  // width
            infoArray[4],  // height
            infoArray[5],  // numBands
            infoArray[6],  // numValidPixels
            dataRangeArray[0],  // minValue
            dataRangeArray[1],  // maxValue
            -9999.0  // noDataValue (default)
        };
        
        return info;
    } catch (...) {
        return nullptr;
    }
}
```

This function:
- Takes a pointer to the LERC data buffer and its size
- Uses `lerc_getBlobInfo` from the LERC C API to extract metadata
- Maps the information from LERC's arrays to the `LercInfo` structure
- Returns a dynamically allocated `LercInfo` structure (caller must free)
- Catches any C++ exceptions and returns null on error

#### 3. Decoding LERC Data

```cpp
double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info) {
    try {
        if (!info) return nullptr;

        size_t numPixels = info->width * info->height;
        auto* floatData = new float[numPixels];
        auto* doubleData = new double[numPixels];

        // Try decoding as float first
        lerc_status status = lerc_decode(
            buffer,
            static_cast<unsigned int>(size),
            0,         // bitmap mask (none)
            nullptr,   // bitmap mask (none)
            1,         // number of bands to process
            info->width,
            info->height,
            1,         // number of bands in input
            6,         // data type = float
            floatData
        );

        if (status != 0) {
            // If float fails, try decoding as double
            status = lerc_decode(
                buffer,
                static_cast<unsigned int>(size),
                0,
                nullptr,
                1,
                info->width,
                info->height,
                1,
                7,         // data type = double
                doubleData
            );

            if (status != 0) {
                delete[] floatData;
                delete[] doubleData;
                return nullptr;
            }

            delete[] floatData;
            return doubleData;
        }

        // Convert float to double if decoded as float
        for (size_t i = 0; i < numPixels; i++) {
            doubleData[i] = static_cast<double>(floatData[i]);
        }

        delete[] floatData;
        return doubleData;
    } catch (...) {
        return nullptr;
    }
}
```

This function:
- Takes the LERC data buffer, its size, and the previously retrieved metadata
- Allocates memory for both float and double arrays
- Attempts to decode the LERC data as float first (more common for terrain data)
- If float decoding fails, tries to decode as double
- Converts float data to double if necessary for consistency
- Returns a dynamically allocated array of doubles (caller must free)
- Catches any C++ exceptions and returns null on error

#### 4. Memory Management

```cpp
void lerc_wrapper_free_info(LercInfo* info) {
    delete info;
}

void lerc_wrapper_free_data(double* data) {
    delete[] data;
}
```

These functions:
- Provide explicit memory management for the dynamically allocated structures
- Enable the Dart code to release native memory via FFI
- Prevent memory leaks when dealing with large terrain datasets
- Follow C++ best practices for resource management

## iOS-Specific Implementation

For iOS, an additional Objective-C++ wrapper (`ios/Classes/LercWrapper.mm`) is used to bridge between the C++ wrapper and iOS platform requirements:

```objectivec++
// C interface implementation
extern "C" {
    bool lerc_wrapper_initialize(void) {
        return [LercWrapper initialize];
    }

    LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size) {
        NSData *data = [NSData dataWithBytes:buffer length:size];
        NSData *infoData = [LercWrapper getInfoFromData:data];
        if (!infoData) {
            return nullptr;
        }
        LercInfo *info = new LercInfo;
        memcpy(info, [infoData bytes], sizeof(LercInfo));
        return info;
    }

    // ... other functions ...
}

@implementation LercWrapper
+ (BOOL)initialize {
    // iOS-specific initialization
    return YES;
}

// ... Objective-C++ implementation of wrapper functions ...
@end
```

This iOS-specific implementation:
- Provides the same C-compatible API as the core wrapper
- Uses Objective-C++ to bridge between C++ and Objective-C
- Handles data conversion between C/C++ types and Objective-C objects (NSData)
- Ensures proper memory management in the Objective-C environment

## Error Handling Approach

The wrapper uses these strategies for error handling:

1. **Exception Handling**:
   - All public functions are wrapped in try-catch blocks
   - Any C++ exceptions are caught and translated to simpler error indicators (nullptr returns)

2. **Status Codes**:
   - LERC API's status codes are checked after each operation
   - Non-zero status codes are treated as errors

3. **Null Returns**:
   - Functions return nullptr or other falsy values on error
   - The Dart code checks for these conditions and handles errors appropriately

## Type Conversion Details

The wrapper handles several type conversions:

1. **Data Type Conversions**:
   - LERC supports multiple data types (int, float, double)
   - The wrapper tries float first, then double, standardizing to double for all returns
   - Converting to double ensures consistent handling in Dart

2. **Memory Layout Conversions**:
   - LERC's internal memory format is converted to a flat array of doubles
   - This simplifies access from Dart FFI

3. **Size Types**:
   - C++ size_t converted to uint32_t for LERC API
   - Ensures compatibility with LERC's expected types

## Memory Allocation Strategy

The wrapper follows these allocation principles:

1. **Dynamic Allocation**:
   - Uses C++ `new` operator for structures and arrays
   - Returns raw pointers to Dart for access via FFI

2. **Explicit Deallocation**:
   - Provides dedicated free functions for each allocation type
   - Does not rely on RAII for cleanup across the FFI boundary

3. **Resource Safety**:
   - Cleans up temporary allocations in the event of errors
   - Ensures no memory leaks if operations fail

## Limitations and Future Improvements

1. **Encoding Support**:
   - The current wrapper only supports decoding, not encoding
   - Future versions could add LERC encoding capabilities

2. **Multiple Bands**:
   - While the `numBands` field is present in `LercInfo`, the wrapper currently processes only the first band
   - Could be extended to handle multi-band data (e.g., multispectral imagery)

3. **Error Information**:
   - Limited error information is currently passed back to Dart
   - Could be improved with more detailed error reporting

4. **Optimization**:
   - Further optimizations could reduce memory usage and improve performance
   - Direct access to LERC blocks could avoid intermediate buffers

## Conclusion

The C++ wrapper effectively bridges the gap between the native LERC library and the Dart FFI interface. It simplifies complex C++ APIs into a straightforward C-compatible interface while maintaining the performance benefits of the native implementation. The careful handling of memory management and error conditions ensures robust operation when processing large terrain datasets.