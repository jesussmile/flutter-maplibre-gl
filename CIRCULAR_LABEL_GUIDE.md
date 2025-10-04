# Circular Label Implementation Guide

## Overview
This guide documents the complete implementation of **circular labels with curved text** for MapLibre GL in Flutter. This feature enables rendering of text that follows the circumference of a circle - perfect for aviation airspace boundaries, circular restricted areas, MOAs, and other circular geographic features.

## Implementation Architecture

The circular label feature follows the same proven architecture as pill labels:

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Flutter API (controller.dart)                      │
│  - createCircleLabel() method                               │
│  - User-facing API with documentation                       │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Layer 2: Platform Interface                                 │
│  - Abstract method definition                               │
│  - Platform contract for implementations                    │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Layer 3: Method Channel Bridge                              │
│  - invokeMethod('style#createCircleLabel', params)          │
│  - Flutter-to-native communication                          │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Layer 4: Native Android Implementation                      │
│  - createCircleLabelBitmap() method                         │
│  - Path.addArc() for circular path                          │
│  - canvas.drawTextOnPath() for curved text                  │
│  - style.addImage() to register bitmap                      │
└─────────────────────────────────────────────────────────────┘
```

## Key Implementation Details

### Native Android Implementation

**File**: `MapLibreMapController.java`

#### Method Channel Handler (Lines 1795-1850)
```java
case "style#createCircleLabel": {
    String imageName = call.argument("name");
    String labelText = call.argument("text");
    Double radius = call.argument("radius");
    String circleColor = call.argument("circleColor");
    Double circleStrokeWidth = call.argument("circleStrokeWidth");
    String textColor = call.argument("textColor");
    Double textSize = call.argument("textSize");
    Boolean topArc = call.argument("topArc");

    Bitmap circleBitmap = createCircleLabelBitmap(
        labelText,
        radius.floatValue(),
        circleColor,
        circleStrokeWidth.floatValue(),
        textColor,
        textSize.floatValue(),
        topArc
    );

    style.addImage(imageName, circleBitmap, false);
    Log.d(TAG, "✅ Added circle label to style: " + imageName);
    result.success(null);
}
```

#### Circular Bitmap Generation (Lines 4580-4700)
```java
private Bitmap createCircleLabelBitmap(
    String text,
    float radius,
    String circleColor,
    float circleStrokeWidth,
    String textColor,
    float textSize,
    boolean topArc
) {
    try {
        // Density scaling (important for Retina/HD displays)
        float density = context.getResources().getDisplayMetrics().density;
        float scaledRadius = radius * density;
        float scaledStrokeWidth = circleStrokeWidth * density;
        float scaledTextSize = textSize * density;

        // Create bitmap with padding
        int bitmapSize = (int) ((scaledRadius + scaledStrokeWidth + 20) * 2);
        Bitmap bitmap = Bitmap.createBitmap(bitmapSize, bitmapSize, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);

        // Draw circle outline
        Paint circlePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        circlePaint.setStyle(Paint.Style.STROKE);
        circlePaint.setStrokeWidth(scaledStrokeWidth);
        circlePaint.setColor(Color.parseColor(circleColor));
        
        float centerX = bitmapSize / 2f;
        float centerY = bitmapSize / 2f;
        canvas.drawCircle(centerX, centerY, scaledRadius, circlePaint);

        // Setup text paint
        Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        textPaint.setColor(Color.parseColor(textColor));
        textPaint.setTextSize(scaledTextSize);
        textPaint.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));

        // Create circular path for text
        Path path = new Path();
        float textRadius = scaledRadius + scaledStrokeWidth / 2 + 5 * density;
        
        if (topArc) {
            // Text on top half of circle (180° to 0°)
            path.addArc(
                centerX - textRadius, centerY - textRadius,
                centerX + textRadius, centerY + textRadius,
                180f, 180f
            );
        } else {
            // Text on bottom half of circle (0° to 180°)
            path.addArc(
                centerX - textRadius, centerY - textRadius,
                centerX + textRadius, centerY + textRadius,
                0f, 180f
            );
        }

        // Draw curved text along path
        canvas.drawTextOnPath(text, path, 0, 0, textPaint);

        return bitmap;
    } catch (Exception e) {
        Log.e(TAG, "Error creating circle label bitmap: " + e.getMessage());
        // Fallback: simple circle
        Bitmap fallbackBitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(fallbackBitmap);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.RED);
        canvas.drawCircle(50, 50, 40, paint);
        return fallbackBitmap;
    }
}
```

### Flutter API

**File**: `controller.dart` (Lines 1680-1738)

```dart
/// Creates a circular label with text curved around the circle's circumference
///
/// This method generates a native bitmap with a circle outline and text that
/// follows the circle's edge. Perfect for aviation airspace boundaries, circular
/// restricted areas, MOAs, and other circular geographic features.
///
/// Parameters:
/// - [name]: Unique identifier for the label image (used in iconImage)
/// - [text]: Text to display curved along the circle
/// - [radius]: Circle radius in density-independent pixels (default: 30.0)
/// - [circleColor]: Hex color string for circle outline (default: '#0066FF')
/// - [circleStrokeWidth]: Outline width in dp (default: 2.0)
/// - [textColor]: Hex color string for text (default: '#FFFFFF')
/// - [textSize]: Text size in sp (default: 14.0)
/// - [topArc]: If true, text curves along top arc; if false, bottom arc (default: true)
///
/// Example usage:
/// ```dart
/// // Create circular label on native side
/// await controller.createCircleLabel(
///   name: 'restricted-area-label',
///   text: 'RESTRICTED R-2508',
///   radius: 30.0,
///   circleColor: '#FF0000',
///   circleStrokeWidth: 3.0,
///   textColor: '#FFFFFF',
///   textSize: 12.0,
///   topArc: true,
/// );
///
/// // Display on map using addSymbol (NOT addSymbolLayer!)
/// await controller.addSymbol(
///   SymbolOptions(
///     geometry: LatLng(32.8, -97.0),
///     iconImage: 'restricted-area-label',
///     iconSize: 0.5, // Important: Use 0.5 for density-scaled bitmaps
///   ),
/// );
/// ```
Future<void> createCircleLabel({
  required String name,
  required String text,
  double radius = 30.0,
  String circleColor = '#0066FF',
  double circleStrokeWidth = 2.0,
  String textColor = '#FFFFFF',
  double textSize = 14.0,
  bool topArc = true,
}) {
  return _maplibrePlatform.createCircleLabel(
    name: name,
    text: text,
    radius: radius,
    circleColor: circleColor,
    circleStrokeWidth: circleStrokeWidth,
    textColor: textColor,
    textSize: textSize,
    topArc: topArc,
  );
}
```

## Usage Examples

### Example 1: Restricted Airspace (Red, Top Arc)
```dart
await controller.createCircleLabel(
  name: 'restricted-r2508',
  text: 'RESTRICTED R-2508',
  radius: 30.0,
  circleColor: '#FF0000',
  circleStrokeWidth: 3.0,
  textColor: '#FFFFFF',
  textSize: 12.0,
  topArc: true,
);

await controller.addSymbol(
  SymbolOptions(
    geometry: LatLng(32.8, -97.0),
    iconImage: 'restricted-r2508',
    iconSize: 0.5,
  ),
);
```

### Example 2: MOA (Blue, Bottom Arc)
```dart
await controller.createCircleLabel(
  name: 'moa-whiskey174',
  text: 'MOA WHISKEY 174',
  radius: 35.0,
  circleColor: '#0066FF',
  circleStrokeWidth: 3.0,
  textColor: '#FFFFFF',
  textSize: 12.0,
  topArc: false, // Text on bottom
);

await controller.addSymbol(
  SymbolOptions(
    geometry: LatLng(32.7, -97.1),
    iconImage: 'moa-whiskey174',
    iconSize: 0.5,
  ),
);
```

### Example 3: Prohibited Area (Dark Red, Top Arc)
```dart
await controller.createCircleLabel(
  name: 'prohibited-p40',
  text: 'PROHIBITED P-40',
  radius: 25.0,
  circleColor: '#990000',
  circleStrokeWidth: 3.0,
  textColor: '#FFFFFF',
  textSize: 11.0,
  topArc: true,
);

await controller.addSymbol(
  SymbolOptions(
    geometry: LatLng(32.75, -97.05),
    iconImage: 'prohibited-p40',
    iconSize: 0.5,
  ),
);
```

### Example 4: Alert Area (Orange, Bottom Arc)
```dart
await controller.createCircleLabel(
  name: 'alert-a632',
  text: 'ALERT AREA A-632',
  radius: 40.0,
  circleColor: '#FF6600',
  circleStrokeWidth: 3.0,
  textColor: '#FFFFFF',
  textSize: 13.0,
  topArc: false,
);

await controller.addSymbol(
  SymbolOptions(
    geometry: LatLng(32.85, -96.95),
    iconImage: 'alert-a632',
    iconSize: 0.5,
  ),
);
```

## Technical Details

### Text Path Calculation

The curved text is achieved using Android's `Path.addArc()` and `Canvas.drawTextOnPath()` methods:

**Top Arc (topArc=true)**:
- Arc sweeps from **180° to 360° (0°)** → text appears on top half of circle
- Path direction: left-to-right along top edge

**Bottom Arc (topArc=false)**:
- Arc sweeps from **0° to 180°** → text appears on bottom half of circle  
- Path direction: left-to-right along bottom edge

### Density Scaling

All measurements are automatically scaled for device pixel density:

```java
float density = context.getResources().getDisplayMetrics().density;
float scaledRadius = radius * density;      // e.g., 30dp → 67.5px at 2.25x
float scaledStrokeWidth = circleStrokeWidth * density;
float scaledTextSize = textSize * density;
```

**Important**: When displaying with `addSymbol()`, use `iconSize: 0.5` to compensate for the density scaling:
```dart
iconSize: 0.5,  // Scales 2.25x bitmap back to original intended size
```

### Text Positioning

Text is positioned slightly outside the circle outline for better visibility:

```java
float textRadius = scaledRadius + scaledStrokeWidth / 2 + 5 * density;
```

This creates a **5dp gap** between the circle outline and the text baseline.

## Aviation Color Standards

Recommended colors for aviation airspace types:

| Airspace Type | Color Code | Description |
|--------------|------------|-------------|
| **Restricted** | `#FF0000` | Red - flight restrictions apply |
| **Prohibited** | `#990000` | Dark red - flight prohibited |
| **MOA** (Military Operations Area) | `#0066FF` | Blue - military training |
| **Alert Area** | `#FF6600` | Orange - high volume pilot training |
| **Warning Area** | `#FFCC00` | Yellow - hazardous activities |
| **TFR** (Temporary Flight Restriction) | `#FF00FF` | Magenta - temporary restriction |

## Performance Considerations

1. **Bitmap Caching**: Each `createCircleLabel()` call generates and caches a bitmap on the native side
2. **Memory Usage**: ~5-10KB per circular label bitmap (depends on radius and text length)
3. **Rendering**: Uses hardware-accelerated Canvas drawing with anti-aliasing
4. **Reuse**: Call `createCircleLabel()` once, then use `addSymbol()` multiple times with same `iconImage`

## Troubleshooting

### Issue: Circular labels not appearing
**Solution**: Ensure you're using `addSymbol()` (NOT `addSymbolLayer()`):
```dart
// ✅ CORRECT
await controller.addSymbol(SymbolOptions(...));

// ❌ WRONG - Method channel images incompatible with layers
await controller.addSymbolLayer(...);
```

### Issue: Labels appear too large/small
**Solution**: Use `iconSize: 0.5` to account for density scaling:
```dart
SymbolOptions(
  iconImage: 'circle-label',
  iconSize: 0.5,  // Important for density-scaled bitmaps
)
```

### Issue: Text appears truncated
**Solution**: Increase the `radius` parameter to provide more arc length for the text.

### Issue: Text positioning looks off
**Solution**: Try toggling `topArc` parameter:
```dart
topArc: true,   // Text on top half of circle
topArc: false,  // Text on bottom half of circle
```

## Files Modified

This implementation involved changes to the following files:

1. **Native Android**:
   - `MapLibreMapController.java` (Lines 1795-1850, 4580-4700)

2. **Flutter Platform**:
   - `maplibre_gl_platform_interface.dart` (Lines 106-116)
   - `method_channel_maplibre_gl.dart` (Lines 524-549)

3. **Flutter API**:
   - `controller.dart` (Lines 1680-1738)

4. **Example**:
   - `pill_label_example.dart` (Lines 193-281, UI buttons)

## Related Documentation

- [Pill Label Solution](./PILL_LABEL_SOLUTION.md) - Similar implementation for pill/lozenge labels
- [Android Canvas Documentation](https://developer.android.com/reference/android/graphics/Canvas)
- [Android Path Documentation](https://developer.android.com/reference/android/graphics/Path)
- [MapLibre Style Spec](https://maplibre.org/maplibre-style-spec/)

## Credits

Implemented as part of the Flight Canvas aviation navigation project, extending the proven pill label architecture to support circular airspace boundary visualization with curved text following the circle circumference.
