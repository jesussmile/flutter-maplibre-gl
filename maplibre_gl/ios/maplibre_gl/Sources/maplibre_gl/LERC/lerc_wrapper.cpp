#include "lerc_wrapper.h"
#include "Lerc.h"
#include "Lerc_c_api_impl.h"
#include <cstring>
#include <cstdlib>
#include <cstdio>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "lerc_wrapper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__)
#endif

static bool initialized = false;

bool lerc_wrapper_initialize() {
    initialized = true;
    return true;
}

LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size) {
    if (!initialized) lerc_wrapper_initialize();

    LercInfo* info = (LercInfo*)malloc(sizeof(LercInfo));
    if (!info) return nullptr;

    int width = 0, height = 0, numBands = 0, numValidPixels = 0, dataType = 0;
    double minValue = 0, maxValue = 0, noDataValue = 0;

    int ok = Lerc_getInfo(
        buffer, size,
        &width, &height, &numBands, &numValidPixels, &dataType,
        &minValue, &maxValue, &noDataValue);

    if (ok != 0) {
        free(info);
        return nullptr;
    }

    info->width = width;
    info->height = height;
    info->numBands = numBands;
    info->numValidPixels = numValidPixels;
    info->minValue = minValue;
    info->maxValue = maxValue;
    info->noDataValue = noDataValue;
    return info;
}

double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info) {
    if (!initialized || !info) return nullptr;
    size_t nPixels = info->width * info->height * info->numBands;
    float* floatData = (float*)malloc(nPixels * sizeof(float));
    double* doubleData = (double*)malloc(nPixels * sizeof(double));
    if (!floatData || !doubleData) {
        if (floatData) free(floatData);
        if (doubleData) free(doubleData);
        return nullptr;
    }

    int ok = Lerc_decode(
        buffer, size,
        0, // no mask
        info->width, info->height, info->numBands,
        6, // float
        floatData);

    if (ok == 0) {
        for (size_t i = 0; i < nPixels; i++) {
            doubleData[i] = (double)floatData[i];
        }
        free(floatData);
        return doubleData;
    }

    ok = Lerc_decode(
        buffer, size,
        0, // no mask
        info->width, info->height, info->numBands,
        7, // double
        doubleData);

    free(floatData);

    if (ok == 0) {
        return doubleData;
    } else {
        free(doubleData);
        LOGI("[lerc_wrapper] Lerc_decode failed with error code: %d", ok);
        return nullptr;
    }
}

void lerc_wrapper_free_info(LercInfo* info) {
    if (info) free(info);
}

void lerc_wrapper_free_data(double* data) {
    if (data) free(data);
}

extern "C" {

__attribute__((visibility("default")))
void lerc_wrapper_free_data(double* data) {
    if (data) free(data);
}

} // extern "C" 