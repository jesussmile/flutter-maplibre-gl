package org.maplibre.example.terrain;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.HashMap;
import java.util.Map;

/**
 * FlutterPlugin that bridges Flutter and native LERC decoder.
 */
public class LercDecoderPlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private LercNativeLoader lercNativeLoader;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "org.maplibre.example/lerc_decoder");
        channel.setMethodCallHandler(this);
        
        try {
            lercNativeLoader = LercNativeLoader.getInstance();
        } catch (RuntimeException e) {
            System.err.println("Failed to initialize LERC native library: " + e.getMessage());
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if (lercNativeLoader == null) {
            result.error("LERC_NOT_INITIALIZED", "LERC native library failed to initialize", null);
            return;
        }

        switch (call.method) {
            case "getLercInfo":
                byte[] infoBuffer = call.argument("buffer");
                if (infoBuffer == null) {
                    result.error("INVALID_ARGUMENT", "Buffer cannot be null", null);
                    return;
                }
                
                LercInfo info = lercNativeLoader.getLercInfo(infoBuffer);
                if (info == null) {
                    result.error("DECODE_ERROR", "Failed to get LERC info", null);
                    return;
                }
                
                Map<String, Object> infoMap = new HashMap<>();
                infoMap.put("width", info.width);
                infoMap.put("height", info.height);
                infoMap.put("numBands", info.numBands);
                infoMap.put("numValidPixels", info.numValidPixels);
                infoMap.put("minValue", info.minValue);
                infoMap.put("maxValue", info.maxValue);
                infoMap.put("noDataValue", info.noDataValue);
                
                result.success(infoMap);
                break;
                
            case "decodeLerc":
                byte[] decodeBuffer = call.argument("buffer");
                Map<String, Object> infoArg = call.argument("info");
                
                if (decodeBuffer == null || infoArg == null) {
                    result.error("INVALID_ARGUMENT", "Buffer and info cannot be null", null);
                    return;
                }
                
                // Create LercInfo from the passed map
                LercInfo lercInfo = new LercInfo(
                    (int) infoArg.get("width"),
                    (int) infoArg.get("height"),
                    (int) infoArg.get("numBands"),
                    (int) infoArg.get("numValidPixels"),
                    (double) infoArg.get("minValue"),
                    (double) infoArg.get("maxValue"),
                    (double) infoArg.get("noDataValue")
                );
                
                double[] decodedData = lercNativeLoader.decodeLerc(decodeBuffer, lercInfo);
                if (decodedData == null) {
                    result.error("DECODE_ERROR", "Failed to decode LERC data", null);
                    return;
                }
                
                result.success(decodedData);
                break;
                
            default:
                result.notImplemented();
                break;
        }
    }
}
