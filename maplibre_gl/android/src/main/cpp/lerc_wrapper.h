#ifndef LERC_WRAPPER_H
#define LERC_WRAPPER_H

#include <stddef.h>
#include <stdint.h>
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

bool lerc_wrapper_initialize();

LercInfo* lerc_wrapper_get_info(const uint8_t* buffer, size_t size);

double* lerc_wrapper_decode(const uint8_t* buffer, size_t size, LercInfo* info);

void lerc_wrapper_free_info(LercInfo* info);

void lerc_wrapper_free_data(double* data);

#ifdef __cplusplus
}
#endif

#endif // LERC_WRAPPER_H 