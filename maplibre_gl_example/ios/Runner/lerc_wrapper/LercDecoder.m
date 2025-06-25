#import "LercDecoder.h"
#include "lerc_wrapper.h"

@implementation LercDecoder

@implementation LercInfo

- (instancetype)initWithNativeLercInfo:(LercInfo *)nativeInfo {
    self = [super init];
    if (self) {
        _width = nativeInfo->width;
        _height = nativeInfo->height;
        _numBands = nativeInfo->numBands;
        _numValidPixels = nativeInfo->numValidPixels;
        _minValue = nativeInfo->minValue;
        _maxValue = nativeInfo->maxValue;
        _noDataValue = nativeInfo->noDataValue;
    }
    return self;
}

@end

+ (instancetype)sharedInstance {
    static LercDecoder *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        if (!lerc_wrapper_initialize()) {
            NSLog(@"Failed to initialize LERC native library");
        }
    });
    return instance;
}

- (nullable LercInfo *)getInfoFromData:(NSData *)data {
    if (data == nil || data.length == 0) {
        return nil;
    }
    
    LercInfo *nativeInfo = lerc_wrapper_get_info((const uint8_t*)data.bytes, data.length);
    if (nativeInfo == NULL) {
        return nil;
    }
    
    LercInfo *info = [[LercInfo alloc] initWithNativeLercInfo:nativeInfo];
    
    lerc_wrapper_free_info(nativeInfo);
    
    return info;
}

- (nullable NSArray<NSNumber *> *)decodeData:(NSData *)data withInfo:(LercInfo *)info {
    if (data == nil || data.length == 0 || info == nil) {
        return nil;
    }
    
    // Create a native LercInfo struct for the decoder
    struct LercInfo nativeInfo;
    nativeInfo.width = (uint32_t)info.width;
    nativeInfo.height = (uint32_t)info.height;
    nativeInfo.numBands = (uint32_t)info.numBands;
    nativeInfo.numValidPixels = (uint32_t)info.numValidPixels;
    nativeInfo.minValue = info.minValue;
    nativeInfo.maxValue = info.maxValue;
    nativeInfo.noDataValue = info.noDataValue;
    
    // Decode the LERC data
    double *data_ptr = lerc_wrapper_decode((const uint8_t*)data.bytes, data.length, &nativeInfo);
    if (data_ptr == NULL) {
        return nil;
    }
    
    // Create an NSArray from the decoded data
    NSUInteger pixelCount = info.width * info.height;
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:pixelCount];
    
    for (NSUInteger i = 0; i < pixelCount; i++) {
        [result addObject:@(data_ptr[i])];
    }
    
    // Free the native data
    lerc_wrapper_free_data(data_ptr);
    
    return [result copy];
}

@end
