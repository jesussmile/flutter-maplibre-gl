#include "lerc_wrapper.h"
#include "include/Lerc_c_api.h"
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
            infoArray[3],
            infoArray[4],
            infoArray[5],
            infoArray[6],
            dataRangeArray[0],
            dataRangeArray[1],
            -9999.0
        };
        
        return info;
    } catch (...) {
        return nullptr;
    }
}

double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info) {
    try {
        if (!info) return nullptr;

        size_t numPixels = info->width * info->height;
        auto* floatData = new float[numPixels];
        auto* doubleData = new double[numPixels];

        lerc_status status = lerc_decode(
            buffer,
            static_cast<unsigned int>(size),
            0,
            nullptr,
            1,
            info->width,
            info->height,
            1,
            6,
            floatData
        );

        if (status != 0) {
            status = lerc_decode(
                buffer,
                static_cast<unsigned int>(size),
                0,
                nullptr,
                1,
                info->width,
                info->height,
                1,
                7,
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

        for (size_t i = 0; i < numPixels; i++) {
            doubleData[i] = static_cast<double>(floatData[i]);
        }

        delete[] floatData;
        return doubleData;
    } catch (...) {
        return nullptr;
    }
}

void lerc_wrapper_free_info(LercInfo* info) {
    delete info;
}

void lerc_wrapper_free_data(double* data) {
    delete[] data;
} 