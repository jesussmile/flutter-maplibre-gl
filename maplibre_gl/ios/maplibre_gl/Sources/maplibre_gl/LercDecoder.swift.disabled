import Flutter
import Foundation

/**
 * Information about a decoded LERC file.
 */
@objc public class LercInfo: NSObject {
    @objc public let width: UInt32
    @objc public let height: UInt32
    @objc public let numBands: UInt32
    @objc public let numValidPixels: UInt32
    @objc public let minValue: Double
    @objc public let maxValue: Double
    @objc public let noDataValue: Double

    init(width: UInt32, height: UInt32, numBands: UInt32, numValidPixels: UInt32,
         minValue: Double, maxValue: Double, noDataValue: Double) {
        self.width = width
        self.height = height
        self.numBands = numBands
        self.numValidPixels = numValidPixels
        self.minValue = minValue
        self.maxValue = maxValue
        self.noDataValue = noDataValue
    }
}

/**
 * Swift wrapper for the native LERC decoder.
 */
@objc public class LercDecoder: NSObject {
    private static var sharedInstance: LercDecoder?
    private var isInitialized = false

    @objc public static func shared() -> LercDecoder {
        if sharedInstance == nil {
            sharedInstance = LercDecoder()
        }
        return sharedInstance!
    }

    private override init() {
        super.init()
        initializeNativeLibrary()
    }

    private func initializeNativeLibrary() {
        if !isInitialized {
            if lerc_wrapper_initialize() {
                isInitialized = true
                print("LERC decoder initialized successfully")
            } else {
                print("Failed to initialize LERC decoder")
            }
        }
    }

    /**
     * Get information about a LERC blob.
     * @param data The LERC compressed data
     * @return A LercInfo object with metadata, or nil if an error occurred
     */
    @objc public func getInfo(from data: Data) -> LercInfo? {
        guard isInitialized else {
            print("LERC decoder not initialized")
            return nil
        }

        return data.withUnsafeBytes { bytes in
            guard let buffer = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            let infoPtr = lerc_wrapper_get_info(buffer, data.count)
            guard infoPtr != nil else {
                return nil
            }

            let info = LercInfo(
                width: infoPtr!.pointee.width,
                height: infoPtr!.pointee.height,
                numBands: infoPtr!.pointee.numBands,
                numValidPixels: infoPtr!.pointee.numValidPixels,
                minValue: infoPtr!.pointee.minValue,
                maxValue: infoPtr!.pointee.maxValue,
                noDataValue: infoPtr!.pointee.noDataValue
            )

            lerc_wrapper_free_info(infoPtr)
            return info
        }
    }

    /**
     * Decode LERC compressed data.
     * @param data The LERC compressed data
     * @param info The LercInfo object with metadata
     * @return An array of decoded elevation values, or nil if an error occurred
     */
    @objc public func decode(data: Data, info: LercInfo) -> [Double]? {
        guard isInitialized else {
            print("LERC decoder not initialized")
            return nil
        }

        return data.withUnsafeBytes { bytes in
            guard let buffer = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            // Create a native LercInfo struct
            var nativeInfo = LercInfo_t(
                width: info.width,
                height: info.height,
                numBands: info.numBands,
                numValidPixels: info.numValidPixels,
                minValue: info.minValue,
                maxValue: info.maxValue,
                noDataValue: info.noDataValue
            )

            let dataPtr = lerc_wrapper_decode(buffer, data.count, &nativeInfo)
            guard dataPtr != nil else {
                return nil
            }

            let pixelCount = Int(info.width * info.height)
            let decodedData = Array(UnsafeBufferPointer(start: dataPtr, count: pixelCount))

            lerc_wrapper_free_data(dataPtr)
            return decodedData
        }
    }
}

/**
 * Flutter plugin for LERC decoding on iOS.
 */
@objc public class LercDecoderPlugin: NSObject, FlutterPlugin {
    private let decoder = LercDecoder.shared()

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "maplibre_gl/lerc_decoder",
            binaryMessenger: registrar.messenger()
        )
        let instance = LercDecoderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getLercInfo":
            handleGetLercInfo(call, result: result)
        case "decodeLerc":
            handleDecodeLerc(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleGetLercInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let bufferData = args["buffer"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Buffer cannot be null", details: nil))
            return
        }

        guard let info = decoder.getInfo(from: bufferData.data) else {
            result(FlutterError(code: "DECODE_ERROR", message: "Failed to get LERC info", details: nil))
            return
        }

        let infoMap: [String: Any] = [
            "width": info.width,
            "height": info.height,
            "numBands": info.numBands,
            "numValidPixels": info.numValidPixels,
            "minValue": info.minValue,
            "maxValue": info.maxValue,
            "noDataValue": info.noDataValue
        ]

        result(infoMap)
    }

    private func handleDecodeLerc(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let bufferData = args["buffer"] as? FlutterStandardTypedData,
              let infoArg = args["info"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Buffer and info cannot be null", details: nil))
            return
        }

        // Create LercInfo from the passed map
        guard let width = infoArg["width"] as? UInt32,
              let height = infoArg["height"] as? UInt32,
              let numBands = infoArg["numBands"] as? UInt32,
              let numValidPixels = infoArg["numValidPixels"] as? UInt32,
              let minValue = infoArg["minValue"] as? Double,
              let maxValue = infoArg["maxValue"] as? Double,
              let noDataValue = infoArg["noDataValue"] as? Double else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid info structure", details: nil))
            return
        }

        let info = LercInfo(
            width: width,
            height: height,
            numBands: numBands,
            numValidPixels: numValidPixels,
            minValue: minValue,
            maxValue: maxValue,
            noDataValue: noDataValue
        )

        guard let decodedData = decoder.decode(data: bufferData.data, info: info) else {
            result(FlutterError(code: "DECODE_ERROR", message: "Failed to decode LERC data", details: nil))
            return
        }

        result(decodedData)
    }
} 