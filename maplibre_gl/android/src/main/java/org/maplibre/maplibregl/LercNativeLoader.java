package org.maplibre.maplibregl;

/**
 * Provides Java interface to the native LERC decoder.
 */
public class LercNativeLoader {
    static {
        System.loadLibrary("maplibre_lerc");
    }

    /**
     * Initialize the LERC decoder.
     * @return true if initialization was successful
     */
    public native boolean initialize();

    /**
     * Get information about a LERC blob.
     * @param buffer The LERC compressed data
     * @return A LercInfo object with metadata, or null if an error occurred
     */
    public native LercInfo getLercInfo(byte[] buffer);

    /**
     * Decode LERC compressed data.
     * @param buffer The LERC compressed data
     * @param info The LercInfo object with metadata (can be obtained from getLercInfo)
     * @return An array of decoded elevation values, or null if an error occurred
     */
    public native double[] decodeLerc(byte[] buffer, LercInfo info);

    // Singleton instance
    private static LercNativeLoader instance;

    /**
     * Get the singleton instance.
     * @return The LercNativeLoader instance
     */
    public static synchronized LercNativeLoader getInstance() {
        if (instance == null) {
            instance = new LercNativeLoader();
            if (!instance.initialize()) {
                throw new RuntimeException("Failed to initialize LERC native library");
            }
        }
        return instance;
    }

    private LercNativeLoader() {
        // Private constructor to enforce singleton pattern
    }
} 