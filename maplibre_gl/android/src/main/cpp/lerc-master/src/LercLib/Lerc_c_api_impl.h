#ifndef LERC_C_API_IMPL_H
#define LERC_C_API_IMPL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns 0 on success
int Lerc_getInfo(
    const unsigned char* pLercBlob,
    size_t blobSize,
    int* nCols,
    int* nRows,
    int* nBands,
    int* nValidPixels,
    int* dataType,
    double* minValue,
    double* maxValue,
    double* noDataValue);

// Returns 0 on success
int Lerc_decode(
    const unsigned char* pLercBlob,
    size_t blobSize,
    const unsigned char* pMaskBytes,
    int nCols,
    int nRows,
    int nBands,
    int dataType,
    void* pData);

#ifdef __cplusplus
}
#endif

#endif // LERC_C_API_IMPL_H 