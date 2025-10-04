# Pill Label Debugging Guide

## Problem Summary
Native pill labels are being created successfully (confirmed by debug logs showing bitmap dimensions like 334x64 px), but they are NOT visible on the map despite:
- ✅ No compilation errors
- ✅ No runtime exceptions
- ✅ Bitmaps created with correct sizes
- ✅ GeoJSON source added
- ✅ SymbolLayer added
- ❌ **Labels completely invisible**

## Debugging History

### Attempt 1: Expression Syntax Investigation
**Hypothesis**: The expression syntax `['get', 'imageName']` was incorrect.

**Test**: Changed to hardcoded `iconImage: 'pill-label-0'`

**Result**: ❌ Still not visible. This ruled out expression syntax as the issue.

### Attempt 2: Icon Size Investigation  
**Hypothesis**: Icons too small at iconSize: 0.5

**Test**: Changed to `iconSize: 1.0`

**Result**: ❌ Still not visible.

### Attempt 3: Icon Size Further Testing
**Hypothesis**: Icons still too small at 1.0

**Test**: Changed to `iconSize: 2.0` (should be VERY large - ~300px on screen)

**Result**: ❌ Still not visible (current test in progress)

### Attempt 4: Direct Symbol Test
**Hypothesis**: SymbolLayer has an issue, but direct Symbol addition might work

**Test**: Added individual Symbol using `addSymbol()` with same image at map center

**Code**:
```dart
await _mapController!.addSymbol(
  SymbolOptions(
    geometry: LatLng(32.85, -97.1), // Map center
    iconImage: 'pill-label-0',
    iconSize: 2.0,
  ),
);
```

**Result**: 🔄 In progress - awaiting rebuild

## Current Code State

### pill_label_example.dart Changes:
1. **iconImage**: Hardcoded to `'pill-label-0'` (was `['get', 'imageName']`)
2. **iconSize**: Increased to `2.0` (was `0.5` → `1.0` → `2.0`)
3. **Debug logging**: Enhanced with feature details and layer info
4. **Test symbol**: Added individual Symbol at map center as control test

### MapLibreMapController.java Changes:
1. **Debug logging**: Added log when image is added to style:
   ```java
   Log.d("MapLibreMapController", "✅ Added image to style: " + imageName + " (" + width + "x" + height + " px)");
   ```

## Key Observations

### Working Examples Comparison

**ADSB Traffic (WORKS)**:
```dart
// Load image from asset
await controller!.addImage('traffic-icon', trafficList);

// Add layer
await controller!.addSymbolLayer(
  sourceId,
  layerId,
  SymbolLayerProperties(
    iconImage: 'traffic-icon',  // Hardcoded
    iconSize: 0.1,
  ),
);
```

**Native State Labels (WORKS)**:
```dart
// Create bitmap via Flutter Canvas
final imageBytes = await _createWidgetImage(state);
await _mapController!.addImage('state-${state.abbr}', imageBytes);

// Add INDIVIDUAL symbols (NOT layer)
await _mapController!.addSymbol(
  SymbolOptions(
    iconImage: 'state-${state.abbr}',
    iconSize: 1.0,
  ),
);
```

**Pill Labels (FAILS)**:
```dart
// Create bitmap via native Canvas
await _mapController!.createPillLabel(name: imageName, ...);

// Add layer
await _mapController!.addSymbolLayer(
  sourceId,
  layerId,
  SymbolLayerProperties(
    iconImage: 'pill-label-0',  // Hardcoded for test
    iconSize: 2.0,
  ),
);
```

### Critical Differences

| Aspect | ADSB Traffic | Native State Labels | Pill Labels |
|--------|-------------|-------------------|-------------|
| Image source | Asset file | Flutter Canvas | Native Canvas |
| Add method | `addImage()` | `addImage()` | `createPillLabel()` → `style.addImage()` |
| Display method | `addSymbolLayer()` | `addSymbol()` | `addSymbolLayer()` |
| **Status** | ✅ WORKS | ✅ WORKS | ❌ FAILS |

## Hypotheses to Test

### Hypothesis A: Native addImage Not Working
**Likelihood**: 🔴 Medium

The native `style.addImage()` call might be failing silently or not actually registering the image.

**Test**:
1. Check if the new debug log appears: `"✅ Added image to style:"`
2. Try using Flutter's `addImage()` instead of native `createPillLabel()`

**How to test**:
```dart
// Generate bitmap in Dart instead of native
final bitmap = await generateBitmapInDart(text: 'TEST');
await _mapController!.addImage('test-pill', bitmap);
```

### Hypothesis B: Timing Issue
**Likelihood**: 🟡 Low

Images might not be fully registered when layer is created.

**Test**: Add delay between image creation and layer addition
```dart
await Future.delayed(Duration(milliseconds: 500));
```

### Hypothesis C: Layer Below Base Layers
**Likelihood**: 🟡 Medium

SymbolLayer might be added below map base layers (buildings, roads, etc.)

**Test**: Add layer with `belowLayerId` parameter or check layer order

### Hypothesis D: Style Reload Issue  
**Likelihood**: 🟡 Low

Map style might be reloading after images are added, clearing custom images.

**Test**: Check style version before/after operations

### Hypothesis E: Bitmap Format Issue
**Likelihood**: 🟢 High

Native Canvas-generated bitmaps might have wrong format (ARGB vs RGBA) or pre-multiplied alpha issues.

**Test**: 
1. Compare bitmap config with working examples
2. Try different bitmap formats in native code

### Hypothesis F: Density Scaling Issue
**Likelihood**: 🔴 High  

MapLibre might be treating density-scaled bitmaps incorrectly, making them invisible or positioned off-screen.

**Test**:
1. Create bitmap at 1x density (no scaling)
2. Check if iconSize calculation is backwards

## Next Steps

### Immediate Actions (Current Build)
1. ✅ Hot reload with iconSize: 2.0
2. ✅ Check if test Symbol appears at map center
3. ✅ Review debug logs for image registration

### If Test Symbol WORKS:
→ Issue is with **SymbolLayer**, not image creation
- Try different SymbolLayerProperties configurations
- Check if layer is visible (`setLayerVisibility`)
- Inspect layer z-order

### If Test Symbol FAILS:
→ Issue is with **image registration**, not layer
- Verify `style.addImage()` actually executes
- Try Flutter's `addImage()` instead of native
- Check bitmap format compatibility

### If BOTH Fail:
→ Fundamental issue with how images are created
- Generate bitmap using Flutter Canvas instead
- Copy exact pattern from native_state_labels.dart
- Investigate MapLibre image requirements

## Code Locations

### Flutter Code
- **Example file**: `flutter-maplibre-gl/maplibre_gl_example/lib/pill_label_example.dart`
- **Controller extension**: `flutter-maplibre-gl/maplibre_gl/lib/src/controller.dart` (createPillLabel method)

### Native Android Code
- **Method channel handler**: `MapLibreMapController.java` lines 1773-1800 (case "style#createPillLabel")
- **Bitmap generation**: `MapLibreMapController.java` lines 4442-4566 (createPillLabelBitmap)

### Working Examples to Reference
- **ADSB Traffic**: `flutter-maplibre-gl/maplibre_gl_example/lib/adsb_traffic_page.dart`
- **Native State Labels**: `flutter-maplibre-gl/maplibre_gl_example/lib/native_state_labes.dart`

## Expected Debug Output

When clicking "Show Labels", you should see:
```
I/flutter: 🏷️ Adding native pill labels...
D/MapLibreMapController: Created pill label 'DALLAS B: 11000-0' (334x64 px)
D/MapLibreMapController: ✅ Added image to style: pill-label-0 (334x64 px)
D/MapLibreMapController: Created pill label 'FORT WORTH C: 5000-1200' (448x64 px)
D/MapLibreMapController: ✅ Added image to style: pill-label-1 (448x64 px)
[... more images ...]
I/flutter: 📍 Added GeoJSON source with 5 features
I/flutter: 📍 Sample feature: {"type":"Feature",...}
I/flutter: 🗺️ Added SymbolLayer with iconImage=pill-label-0, iconSize=2.0
I/flutter: ✅ TEST: Added individual Symbol with pill-label-0 at center
I/flutter: ✅ Added 5 native pill labels
```

If you see this output but no labels, it confirms the rendering/visibility issue.

## Success Criteria

✅ **Labels visible on map** with:
- Pill/lozenge shape with rounded corners
- Text centered in background
- Multiple colors (blue, green, orange, purple, red)
- Located in Dallas/Fort Worth area

Current status: ❌ All criteria failing - labels completely invisible

## Documentation Generated
- **Current file**: PILL_LABEL_DEBUGGING_GUIDE.md
- **Previous file**: NATIVE_PILL_LABEL_FIXES.md (type casting and pixel ratio fixes)
