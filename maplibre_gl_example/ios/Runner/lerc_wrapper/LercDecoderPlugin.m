#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>
#import "LercDecoder.h"

@interface LercDecoderPlugin : NSObject<FlutterPlugin>
@end

@implementation LercDecoderPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"org.maplibre.example/lerc_decoder"
                                     binaryMessenger:[registrar messenger]];
    LercDecoderPlugin* instance = [[LercDecoderPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"getLercInfo" isEqualToString:call.method]) {
        FlutterStandardTypedData *buffer = call.arguments[@"buffer"];
        if (buffer == nil) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                       message:@"Buffer cannot be null"
                                       details:nil]);
            return;
        }
        
        LercInfo *info = [[LercDecoder sharedInstance] getInfoFromData:buffer.data];
        if (info == nil) {
            result([FlutterError errorWithCode:@"DECODE_ERROR"
                                       message:@"Failed to get LERC info"
                                       details:nil]);
            return;
        }
        
        NSDictionary *infoMap = @{
            @"width": @(info.width),
            @"height": @(info.height),
            @"numBands": @(info.numBands),
            @"numValidPixels": @(info.numValidPixels),
            @"minValue": @(info.minValue),
            @"maxValue": @(info.maxValue),
            @"noDataValue": @(info.noDataValue)
        };
        
        result(infoMap);
    }
    else if ([@"decodeLerc" isEqualToString:call.method]) {
        FlutterStandardTypedData *buffer = call.arguments[@"buffer"];
        NSDictionary *infoArg = call.arguments[@"info"];
        
        if (buffer == nil || infoArg == nil) {
            result([FlutterError errorWithCode:@"INVALID_ARGUMENT"
                                       message:@"Buffer and info cannot be null"
                                       details:nil]);
            return;
        }
        
        // Create LercInfo from the passed map
        LercInfo *info = [[LercInfo alloc] init];
        [info setValue:infoArg[@"width"] forKey:@"width"];
        [info setValue:infoArg[@"height"] forKey:@"height"];
        [info setValue:infoArg[@"numBands"] forKey:@"numBands"];
        [info setValue:infoArg[@"numValidPixels"] forKey:@"numValidPixels"];
        [info setValue:infoArg[@"minValue"] forKey:@"minValue"];
        [info setValue:infoArg[@"maxValue"] forKey:@"maxValue"];
        [info setValue:infoArg[@"noDataValue"] forKey:@"noDataValue"];
        
        NSArray<NSNumber *> *decodedData = [[LercDecoder sharedInstance] decodeData:buffer.data withInfo:info];
        if (decodedData == nil) {
            result([FlutterError errorWithCode:@"DECODE_ERROR"
                                       message:@"Failed to decode LERC data"
                                       details:nil]);
            return;
        }
        
        result(decodedData);
    }
    else {
        result(FlutterMethodNotImplemented);
    }
}

@end
