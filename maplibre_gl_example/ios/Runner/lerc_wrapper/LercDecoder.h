#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Objective-C wrapper for the LERC native decoder.
 */
@interface LercDecoder : NSObject

/**
 * Information about a decoded LERC file.
 */
@interface LercInfo : NSObject

@property (nonatomic, readonly) NSUInteger width;
@property (nonatomic, readonly) NSUInteger height;
@property (nonatomic, readonly) NSUInteger numBands;
@property (nonatomic, readonly) NSUInteger numValidPixels;
@property (nonatomic, readonly) double minValue;
@property (nonatomic, readonly) double maxValue;
@property (nonatomic, readonly) double noDataValue;

@end

/**
 * Singleton instance of the LERC decoder.
 */
+ (instancetype)sharedInstance;

/**
 * Get information about a LERC blob.
 * @param data The LERC compressed data
 * @return A LercInfo object with metadata, or nil if an error occurred
 */
- (nullable LercInfo *)getInfoFromData:(NSData *)data;

/**
 * Decode LERC compressed data.
 * @param data The LERC compressed data
 * @param info The LercInfo object with metadata (can be obtained from getInfoFromData:)
 * @return An array of decoded elevation values, or nil if an error occurred
 */
- (nullable NSArray<NSNumber *> *)decodeData:(NSData *)data withInfo:(LercInfo *)info;

@end

NS_ASSUME_NONNULL_END
