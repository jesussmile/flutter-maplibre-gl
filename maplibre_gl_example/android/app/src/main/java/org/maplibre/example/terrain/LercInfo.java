package org.maplibre.example.terrain;

/**
 * Java representation of the native LercInfo struct.
 * Contains metadata about a decoded LERC file.
 */
public class LercInfo {
    public final int width;
    public final int height;
    public final int numBands;
    public final int numValidPixels;
    public final double minValue;
    public final double maxValue;
    public final double noDataValue;

    public LercInfo(int width, int height, int numBands, int numValidPixels,
                    double minValue, double maxValue, double noDataValue) {
        this.width = width;
        this.height = height;
        this.numBands = numBands;
        this.numValidPixels = numValidPixels;
        this.minValue = minValue;
        this.maxValue = maxValue;
        this.noDataValue = noDataValue;
    }
}
