# MapLibre Styling Guide for Aviation Procedures

This document provides comprehensive styling guidelines for implementing aviation procedure visualization using MapLibre GL JS, with examples for both web and mobile (Flutter) implementations.

## Table of Contents

1. [Color Scheme](#color-scheme)
2. [Line Styles](#line-styles)
3. [Waypoint Markers](#waypoint-markers)
4. [Waypoint Labels](#waypoint-labels)
5. [UI Components](#ui-components)
6. [Layer Properties](#layer-properties)
7. [Implementation Examples](#implementation-examples)

## Color Scheme

### Primary Colors

```css
/* Aviation Blue - Primary accent color */
--aviation-blue: #00d4ff;

/* Aviation Orange - Missed approach and hierarchical indicators */
--aviation-orange: #ff6b35;

/* Background Colors */
--dark-bg: #1a1a1a;
--panel-bg: rgba(0, 0, 0, 0.95);
--card-bg: rgba(255, 255, 255, 0.05);

/* Text Colors */
--text-primary: white;
--text-secondary: #ccc;
--text-muted: #888;

/* Border Colors */
--border-primary: #333;
--border-active: #00d4ff;
```

### Procedure-Specific Colors

| Procedure Type | Normal Path | Missed Approach | Usage |
|---------------|-------------|-----------------|--------|
| **SID** | `#00d4ff` (Blue) | N/A | Departure procedures |
| **STAR** | `#00d4ff` (Blue) | N/A | Arrival procedures |
| **Approach** | `#00d4ff` (Blue) | `#ff6b35` (Orange) | Landing procedures |
| **Hierarchical** | `#ff6b35` (Orange) | N/A | Complex multi-part procedures |

## Line Styles

### Line Properties Reference

```javascript
// Standard Procedure Line
{
    'line-color': '#00d4ff',
    'line-width': 4,
    'line-opacity': 0.8,
    'line-dasharray': [1, 0] // Solid line
}

// Missed Approach Line
{
    'line-color': '#ff6b35',
    'line-width': 4,
    'line-opacity': 0.8,
    'line-dasharray': [2, 3] // Dashed line (2px dash, 3px gap)
}

// Hierarchical Procedure Line
{
    'line-color': '#ff6b35',
    'line-width': 4,
    'line-opacity': 0.8,
    'line-dasharray': [1, 0] // Solid line
}
```

### Web Implementation

```javascript
// Normal approach segment
map.addLayer({
    id: lineLayerId,
    type: 'line',
    source: sourceId,
    paint: {
        'line-color': '#00d4ff',
        'line-width': 4,
        'line-opacity': 0.8,
        'line-dasharray': [1, 0]
    }
});

// Missed approach segment
map.addLayer({
    id: missedLayerId,
    type: 'line',
    source: `${sourceId}-missed`,
    paint: {
        'line-color': '#ff6b35',
        'line-width': 4,
        'line-opacity': 0.8,
        'line-dasharray': [2, 3]
    }
});
```

### Flutter Implementation

```dart
// Normal procedure line
await controller.addLine(
  LineOptions(
    geometry: coordinates,
    lineColor: "#00D4FF",
    lineWidth: 4.0,
    lineOpacity: 0.8,
    lineDasharray: [], // Solid line
  ),
);

// Missed approach line
await controller.addLine(
  LineOptions(
    geometry: missedCoordinates,
    lineColor: "#FF6B35",
    lineWidth: 4.0,
    lineOpacity: 0.8,
    lineDasharray: [2.0, 3.0], // Dashed line
  ),
);
```

## Waypoint Markers

### Circle Properties

```javascript
// Standard waypoint circles
{
    'circle-color': '#00d4ff', // Or individual colors via ['get', 'color']
    'circle-radius': 5, // Normal: 5, Enhanced: 8
    'circle-stroke-width': 2, // Normal: 2, Enhanced: 3
    'circle-stroke-color': 'white',
    'circle-opacity': 0.9
}
```

### Visibility Control

```javascript
// Toggle waypoint visibility
{
    'layout': {
        'visibility': showWaypoints ? 'visible' : 'none'
    }
}
```

### Web Implementation

```javascript
map.addLayer({
    'id': pointsLayerId,
    'type': 'circle',
    'source': waypointSourceId,
    'paint': {
        'circle-color': ['get', 'color'], // Individual colors per waypoint
        'circle-radius': showEnhanced ? 8 : 5,
        'circle-stroke-width': showEnhanced ? 3 : 2,
        'circle-stroke-color': 'white',
        'circle-opacity': 0.9
    },
    'layout': {
        'visibility': showWaypoints ? 'visible' : 'none'
    }
});
```

### Flutter Implementation

```dart
await controller.addCircle(
  CircleOptions(
    geometry: waypointCoord,
    circleColor: "#00D4FF",
    circleRadius: enhanced ? 8.0 : 5.0,
    circleStrokeWidth: enhanced ? 3.0 : 2.0,
    circleStrokeColor: "#FFFFFF",
    circleOpacity: 0.9,
  ),
);
```

## Waypoint Labels

### CSS Styling (Web)

```css
.waypoint-label {
    position: absolute;
    color: white;
    padding: 2px 6px;
    border-radius: 3px;
    font-size: 11px;
    font-weight: bold;
    pointer-events: none;
    z-index: 1000;
    border: 1px solid rgba(255, 255, 255, 0.5);
    white-space: nowrap;
    transform: translate(-50%, -200%);
    text-shadow: 1px 1px 2px rgba(0, 0, 0, 0.8);
    background-color: #00d4ff; /* Dynamic based on procedure type */
}

.waypoint-label.hidden {
    display: none;
}
```

### Flutter Styling

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: backgroundColor, // #00D4FF or #FF6B35
    borderRadius: BorderRadius.circular(3),
    border: Border.all(
      color: Colors.white.withOpacity(0.5),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.8),
        offset: const Offset(1, 1),
        blurRadius: 2,
      ),
    ],
  ),
  child: Text(
    waypointName,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    ),
  ),
);
```

## UI Components

### Procedure Cards

```css
.procedure-card {
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid #333;
    border-radius: 8px;
    margin: 10px 0;
    transition: all 0.3s ease;
    cursor: pointer;
}

.procedure-card.hierarchical {
    border-left: 4px solid #ff6b35;
}

.procedure-card:hover {
    background: rgba(255, 255, 255, 0.1);
    border-color: #00d4ff;
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0, 212, 255, 0.2);
}

.procedure-card.selected {
    background: rgba(0, 212, 255, 0.2);
    border-color: #00d4ff;
    box-shadow: 0 0 15px rgba(0, 212, 255, 0.4);
}
```

### Badges and Indicators

```css
.hierarchical-badge {
    background: #ff6b35;
    color: white;
    font-size: 10px;
    padding: 2px 6px;
    border-radius: 3px;
    font-weight: bold;
    margin-left: 8px;
}

.version-badge {
    position: absolute;
    top: 10px;
    right: 10px;
    background: #ff6b35;
    color: white;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 10px;
    font-weight: bold;
}
```

### Toggle Switches

```css
.toggle-switch {
    position: relative;
    width: 40px;
    height: 20px;
    background-color: #333;
    border-radius: 10px;
    cursor: pointer;
    transition: background-color 0.3s;
}

.toggle-switch.active {
    background-color: #00d4ff;
}

.toggle-switch::before {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 16px;
    height: 16px;
    background-color: white;
    border-radius: 50%;
    transition: transform 0.3s;
}

.toggle-switch.active::before {
    transform: translateX(20px);
}
```

## Layer Properties

### Layer Structure

```javascript
// Layer naming convention
const sourceId = `procedure-${timestamp}-${random}`;
const lineLayerId = `${sourceId}-line`;
const missedLayerId = `${sourceId}-missed`;
const pointsLayerId = `${sourceId}-points`;
const waypointSourceId = `${sourceId}-waypoints`;
```

### Source Configuration

```javascript
// GeoJSON source
map.addSource(sourceId, {
    type: 'geojson',
    data: feature
});

// Waypoint source with individual properties
map.addSource(waypointSourceId, {
    'type': 'geojson',
    'data': {
        'type': 'FeatureCollection',
        'features': waypointFeatures // Each with individual 'color' property
    }
});
```

### Layer Ordering

1. **Background layers** (map style)
2. **Procedure lines** (lowest z-index)
3. **Waypoint circles** (middle z-index)
4. **HTML labels** (highest z-index: 1000)

## Implementation Examples

### Complete Procedure Layer (Web)

```javascript
function addProcedureToMap(feature, color = '#00d4ff') {
    const sourceId = `procedure-${Date.now()}-${Math.random()}`;
    const lineLayerId = `${sourceId}-line`;
    const pointsLayerId = `${sourceId}-points`;
    
    // Add source
    map.addSource(sourceId, {
        type: 'geojson',
        data: feature
    });
    
    // Add line layer
    map.addLayer({
        id: lineLayerId,
        type: 'line',
        source: sourceId,
        paint: {
            'line-color': color,
            'line-width': 4,
            'line-opacity': 0.8,
            'line-dasharray': [1, 0]
        }
    });
    
    // Add waypoint circles
    const waypointFeatures = createWaypointFeatures(feature);
    const waypointSourceId = `${sourceId}-waypoints`;
    
    map.addSource(waypointSourceId, {
        type: 'geojson',
        data: {
            type: 'FeatureCollection',
            features: waypointFeatures
        }
    });
    
    map.addLayer({
        id: pointsLayerId,
        type: 'circle',
        source: waypointSourceId,
        paint: {
            'circle-color': ['get', 'color'],
            'circle-radius': 5,
            'circle-stroke-width': 2,
            'circle-stroke-color': 'white',
            'circle-opacity': 0.9
        }
    });
    
    // Add HTML labels
    createWaypointLabels(feature, color);
}
```

### Flutter Implementation

```dart
class ProcedureLayer {
  final MapLibreMapController controller;
  final Color normalColor;
  final Color missedColor;
  
  ProcedureLayer({
    required this.controller,
    this.normalColor = const Color(0xFF00D4FF),
    this.missedColor = const Color(0xFFFF6B35),
  });
  
  Future<void> addProcedure(Procedure procedure) async {
    // Add main route line
    await controller.addLine(
      LineOptions(
        geometry: procedure.coordinates,
        lineColor: "#00D4FF",
        lineWidth: 4.0,
        lineOpacity: 0.8,
      ),
    );
    
    // Add missed approach if present
    if (procedure.missedApproach.isNotEmpty) {
      await controller.addLine(
        LineOptions(
          geometry: procedure.missedApproach,
          lineColor: "#FF6B35",
          lineWidth: 4.0,
          lineOpacity: 0.8,
          lineDasharray: [2.0, 3.0],
        ),
      );
    }
    
    // Add waypoint circles
    for (int i = 0; i < procedure.coordinates.length; i++) {
      await controller.addCircle(
        CircleOptions(
          geometry: procedure.coordinates[i],
          circleColor: procedure.isMissedWaypoint(i) ? "#FF6B35" : "#00D4FF",
          circleRadius: 5.0,
          circleStrokeWidth: 2.0,
          circleStrokeColor: "#FFFFFF",
          circleOpacity: 0.9,
        ),
      );
    }
  }
}
```

## Best Practices

### Performance

1. **Layer Limits**: Keep total layers under 50 for optimal performance
2. **Source Reuse**: Reuse sources when possible, only update data
3. **Conditional Rendering**: Use visibility controls instead of adding/removing layers
4. **Cleanup**: Always remove unused layers and sources

### Visual Hierarchy

1. **Line Width**: Use 4px for main procedures, 2px for secondary elements
2. **Opacity**: Use 0.8 for active procedures, 0.5 for inactive
3. **Z-Index**: Labels (1000) > Waypoints (auto) > Lines (auto)

### Accessibility

1. **Color Contrast**: Ensure sufficient contrast against map backgrounds
2. **Text Size**: Minimum 11px for labels
3. **Alternative Indicators**: Use patterns/shapes in addition to colors

### Aviation Standards

1. **Color Coding**: Blue for normal paths, Orange for missed approaches
2. **Line Styles**: Solid for normal, dashed for missed approaches
3. **Waypoint Order**: Maintain procedural sequence in visual presentation

---

*This documentation provides comprehensive styling guidelines for aviation procedure visualization. For implementation questions or updates, refer to the source code in `/Users/pannam/Desktop/ARINC_CREATOR/hierarchical_procedure_viewer_v2.html`.*
