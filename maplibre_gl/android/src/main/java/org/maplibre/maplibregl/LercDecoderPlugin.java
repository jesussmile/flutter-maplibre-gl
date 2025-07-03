package org.maplibre.maplibregl;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.HashMap;
import java.util.Map;

/**
 * Native LERC decoder plugin integrated into MapLibre GL Flutter
 */
public class LercDecoderPlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private LercNativeLoader lercNativeLoader;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "maplibre_gl/lerc_decoder");
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
        android.util.Log.d("LercDecoderPlugin", "Method called: " + call.method);
        
        if (lercNativeLoader == null) {
            android.util.Log.e("LercDecoderPlugin", "LERC native library not initialized");
            result.error("LERC_NOT_INITIALIZED", "LERC native library failed to initialize", null);
            return;
        }

        switch (call.method) {
            case "getLercInfo":
                android.util.Log.d("LercDecoderPlugin", "Getting LERC info...");
                byte[] infoBuffer = call.argument("buffer");
                if (infoBuffer == null) {
                    result.error("INVALID_ARGUMENT", "Buffer cannot be null", null);
                    return;
                }
                
                LercInfo info = lercNativeLoader.getLercInfo(infoBuffer);
                if (info == null) {
                    android.util.Log.e("LercDecoderPlugin", "Failed to get LERC info from native loader");
                    result.error("DECODE_ERROR", "Failed to get LERC info", null);
                    return;
                }
                
                android.util.Log.d("LercDecoderPlugin", "LERC info obtained: " + info.width + "x" + info.height);
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
                android.util.Log.d("LercDecoderPlugin", "Decoding LERC data...");
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
                    android.util.Log.e("LercDecoderPlugin", "Failed to decode LERC data from native loader");
                    result.error("DECODE_ERROR", "Failed to decode LERC data", null);
                    return;
                }
                
                android.util.Log.d("LercDecoderPlugin", "LERC data decoded successfully: " + decodedData.length + " points");
                result.success(decodedData);
                break;
                
            default:
                result.notImplemented();
                break;
        }
    }
} 