# Circular Label Edge Style Control: Rounded vs Straight

## Overview
This feature adds the ability to control whether circular airspace labels have **rounded pill edges** (like traditional pill buttons) or **straight edges** (like rectangular bars) following the circle contour.

## Visual Comparison

### Rounded Edges (`roundedEdges: true`)
```
    ╭──────────────╮
   ●●●●●●●●●●●●●●●●●●
  ●                  ●
 ●                    ●
●                      ●
```
**Use Case**: Softer, friendlier appearance
- MOAs (Military Operations Areas)
- Alert Areas
- Warning Areas

### Straight Edges (`roundedEdges: false`)
```
    ┌──────────────┐
   ●●●●●●●●●●●●●●●●●●
  ●                  ●
 ●                    ●
●                      ●
```
**Use Case**: Sharper, more authoritative appearance
- Restricted Areas
- Prohibited Areas
- Critical airspace boundaries

## Implementation Details

### Native Android (Paint.Cap)
The feature uses Android's `Paint.Cap` property:

```java
// Rounded edges (pill shape)
pillBackgroundPaint.setStrokeCap(Paint.Cap.ROUND);

// Straight edges (rectangular bar)
pillBackgroundPaint.setStrokeCap(Paint.Cap.BUTT);
```

**Paint.Cap Options**:
- `Paint.Cap.ROUND` - Adds semicircular caps at path endpoints
- `Paint.Cap.BUTT` - Ends path with flat, perpendicular edge
- `Paint.Cap.SQUARE` - Similar to BUTT but extends beyond endpoint (not used)

### Parameter Flow

```
Flutter API (roundedEdges: bool)
    ↓
Method Channel ('roundedEdges': true/false)
    ↓
MapLibreMapController.java
    ↓
createCircleLabelBitmap(roundedEdges)
    ↓
pillBackgroundPaint.setStrokeCap(roundedEdges ? Paint.Cap.ROUND : Paint.Cap.BUTT)
```

## Usage Examples

### Example 1: Restricted Area (Straight Edges)
```dart
await controller.createCircleLabel(
  name: 'restricted-r2508',
  text: 'RESTRICTED R-2508',
  radius: 40.0,
  circleColor: '#FF0000',
  topArc: true,
  roundedEdges: false,  // ← Straight edges for authoritative look
);
```

**Visual Result**:
```
    ┌─ RESTRICTED R-2508 ─┐  ← Straight, sharp edges
   ●●●●●●●●●●●●●●●●●●●●●●●●●
  ●                          ●
```

### Example 2: MOA (Rounded Edges)
```dart
await controller.createCircleLabel(
  name: 'moa-whiskey174',
  text: 'MOA WHISKEY 174',
  radius: 45.0,
  circleColor: '#0066FF',
  topArc: false,
  roundedEdges: true,  // ← Rounded edges for softer look
);
```

**Visual Result**:
```
  ●                          ●
   ●●●●●●●●●●●●●●●●●●●●●●●●●
    ╰─ MOA WHISKEY 174 ─╯  ← Rounded, pill-shaped edges
```

### Example 3: Prohibited Area (Straight Edges)
```dart
await controller.createCircleLabel(
  name: 'prohibited-p40',
  text: 'PROHIBITED P-40',
  radius: 35.0,
  circleColor: '#990000',
  topArc: true,
  roundedEdges: false,  // ← Straight edges emphasize restriction
);
```

### Example 4: Alert Area (Rounded Edges)
```dart
await controller.createCircleLabel(
  name: 'alert-a632',
  text: 'ALERT AREA A-632',
  radius: 50.0,
  circleColor: '#FF6600',
  topArc: false,
  roundedEdges: true,  // ← Rounded edges for informational tone
);
```

## Aviation Use Case Guidelines

### When to Use Straight Edges (`roundedEdges: false`)
✅ **Regulatory/Restrictive Airspace**:
- Restricted Areas (R-areas)
- Prohibited Areas (P-areas)
- Special Use Airspace (SUA) with strict entry requirements
- TFRs (Temporary Flight Restrictions)
- Security Identification Display Areas (SIDA)

**Rationale**: Sharp, straight edges convey authority and strict boundaries.

### When to Use Rounded Edges (`roundedEdges: true`)
✅ **Informational/Advisory Airspace**:
- Military Operations Areas (MOAs)
- Alert Areas (A-areas)
- Warning Areas (W-areas)
- Controlled Firing Areas (CFAs)
- Wildlife refuges and national parks

**Rationale**: Soft, rounded edges convey advisory information without harsh restriction.

## API Reference

### Flutter API
```dart
Future<void> createCircleLabel({
  required String name,
  required String text,
  double radius = 40.0,
  String circleColor = '#0066FF',
  double circleStrokeWidth = 2.0,
  String textColor = '#FFFFFF',
  double textSize = 16.0,
  bool topArc = true,
  bool roundedEdges = true,  // ← NEW PARAMETER (default: true)
})
```

### Parameters
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `roundedEdges` | `bool` | `true` | If `true`, pill edges are rounded (Paint.Cap.ROUND). If `false`, edges are straight (Paint.Cap.BUTT). |

### Default Behavior
- **Default**: `roundedEdges: true` (rounded, pill-shaped)
- **Backward Compatible**: Existing code without this parameter will continue to work with rounded edges

## Technical Implementation

### Files Modified

1. **MapLibreMapController.java**
   - Added `roundedEdges` parameter to method channel handler
   - Updated `createCircleLabelBitmap()` signature
   - Conditional `setStrokeCap()` based on parameter

2. **controller.dart**
   - Added `roundedEdges` parameter to `createCircleLabel()`
   - Updated documentation with edge style examples

3. **maplibre_gl_platform_interface.dart**
   - Added `roundedEdges` to platform interface method signature

4. **method_channel_maplibre_gl.dart**
   - Added `roundedEdges` to method channel invocation parameters

5. **pill_label_example.dart**
   - Updated example data with `roundedEdges` configuration
   - Demonstrates both styles: restricted/prohibited (straight) vs MOA/alert (rounded)

### Code Snippet: Native Implementation
```java
// Draw pill-shaped background (thick arc with configurable cap style)
Paint pillBackgroundPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
pillBackgroundPaint.setColor(android.graphics.Color.parseColor(circleColor));
pillBackgroundPaint.setStyle(Paint.Style.STROKE);
pillBackgroundPaint.setStrokeWidth(pillStrokeWidth);

// Use ROUND for pill-shaped ends, BUTT for straight edges
pillBackgroundPaint.setStrokeCap(roundedEdges ? Paint.Cap.ROUND : Paint.Cap.BUTT);

canvas.drawPath(pillPath, pillBackgroundPaint);
```

## Testing the Feature

### Test Case 1: Restricted Areas (Straight)
```dart
// Create labels with straight edges
final restrictedAreas = ['RESTRICTED R-2508', 'PROHIBITED P-40'];
for (var label in restrictedAreas) {
  await controller.createCircleLabel(
    name: label.toLowerCase().replaceAll(' ', '-'),
    text: label,
    circleColor: '#FF0000',
    roundedEdges: false,  // Test straight edges
  );
}
```

### Test Case 2: Advisory Areas (Rounded)
```dart
// Create labels with rounded edges
final advisoryAreas = ['MOA WHISKEY 174', 'ALERT AREA A-632'];
for (var label in advisoryAreas) {
  await controller.createCircleLabel(
    name: label.toLowerCase().replaceAll(' ', '-'),
    text: label,
    circleColor: '#0066FF',
    roundedEdges: true,  // Test rounded edges
  );
}
```

### Visual Verification
1. Run the app and tap "Add Circles" button
2. Observe the 4 circular labels:
   - **RESTRICTED R-2508**: Straight edges (top arc, red)
   - **MOA WHISKEY 174**: Rounded edges (bottom arc, blue)
   - **PROHIBITED P-40**: Straight edges (top arc, dark red)
   - **ALERT AREA A-632**: Rounded edges (bottom arc, orange)

## Performance Impact

**Memory**: ✅ No impact - same bitmap size regardless of cap style
**Rendering**: ✅ Negligible - `setStrokeCap()` is a simple property assignment
**Compatibility**: ✅ Fully backward compatible - defaults to rounded edges

## Design Rationale

### Why Two Edge Styles?
1. **Visual Hierarchy**: Different airspace types need different visual emphasis
2. **Regulatory Distinction**: Strict restrictions vs advisory information
3. **User Perception**: Sharp edges = strict, rounded edges = informational
4. **Aviation Standards**: Follows conventional airspace boundary visualization

### Why `roundedEdges: true` as Default?
- Softer, more approachable appearance
- Matches traditional "pill button" design patterns
- Backward compatible with previous implementations
- Most common use case (informational labels)

## Summary

| Feature | Rounded Edges | Straight Edges |
|---------|---------------|----------------|
| **Parameter** | `roundedEdges: true` | `roundedEdges: false` |
| **Android** | `Paint.Cap.ROUND` | `Paint.Cap.BUTT` |
| **Appearance** | Soft, pill-shaped | Sharp, rectangular |
| **Use Case** | Advisory airspace | Restrictive airspace |
| **Examples** | MOA, Alert Areas | Restricted, Prohibited |

## Example Output

Run the example app to see:
- ✅ 2 labels with **straight edges** (restricted, prohibited)
- ✅ 2 labels with **rounded edges** (MOA, alert area)
- ✅ Both top and bottom arc positioning
- ✅ Different colors and radii for visual variety

---

**Feature Status**: ✅ Complete and tested
**Compatibility**: ✅ Backward compatible (default: `roundedEdges: true`)
**Documentation**: ✅ Comprehensive guide with examples
