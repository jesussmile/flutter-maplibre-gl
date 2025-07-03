#include "Lerc.h"
#include <cstring>

extern "C" {

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
    double* noDataValue) {
    if (!pLercBlob || !nCols || !nRows || !nBands || !nValidPixels || !dataType || !minValue || !maxValue || !noDataValue)
        return 1;
    LercNS::Lerc::LercInfo info;
    LercNS::ErrCode err = LercNS::Lerc::GetLercInfo(pLercBlob, (unsigned int)blobSize, info);
    if (err != LercNS::ErrCode::Ok)
        return 2;
    *nCols = info.nCols;
    *nRows = info.nRows;
    *nBands = info.nBands;
    *nValidPixels = info.numValidPixel;
    *dataType = (int)info.dt;
    *minValue = info.zMin;
    *maxValue = info.zMax;
    *noDataValue = 0; // LERC2 supports per-band noData, but for simplicity, set to 0 here
    return 0;
}

// Returns 0 on success
int Lerc_decode(
    const unsigned char* pLercBlob,
    size_t blobSize,
    const unsigned char* pMaskBytes,
    int nCols,
    int nRows,
    int nBands,
    int dataType,
    void* pData) {
    if (!pLercBlob || !pData)
        return 1;
    int nMasks = 0;
    unsigned char* pValidBytes = nullptr;
    if (pMaskBytes) {
        nMasks = 1;
        pValidBytes = (unsigned char*)pMaskBytes;
    }
    LercNS::Lerc::DataType dt = (LercNS::Lerc::DataType)dataType;
    LercNS::ErrCode err = LercNS::Lerc::Decode(
        pLercBlob, (unsigned int)blobSize, nMasks, pValidBytes,
        1, nCols, nRows, nBands, dt, pData, nullptr, nullptr);
    return (err == LercNS::ErrCode::Ok) ? 0 : 2;
}

} // extern "C" 