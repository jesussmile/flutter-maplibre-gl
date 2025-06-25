# Enhanced UI for Visualization Controls

This document describes the implementation of enhanced user interface controls for terrain visualization in the FlightCanvas Terrain project.

## Overview

The FlightCanvas Terrain project includes a comprehensive suite of UI controls that allow users to customize and interact with terrain visualization. These controls provide a rich and intuitive interface for adjusting parameters such as:

1. Reference altitude
2. Warning levels
3. Terrain color schemes
4. Rendering modes
5. Hillshading options
6. View settings

## Implementation Details

### UI Control Panel Structure

The main UI controls are organized in a floating panel with collapsible sections:

```dart
class TerrainControlPanel extends StatefulWidget {
  final ValueNotifier<double> referenceAltitude;
  final ValueNotifier<double> terrainResolution;
  final ValueNotifier<bool> useGradientMode;
  final ValueNotifier<bool> showHillshade;
  final ValueNotifier<bool> showTerrain;
  final Function(double) onAltitudeChange;
  final Function(double) onWarningAltitudeChange;
  
  const TerrainControlPanel({
    Key? key,
    required this.referenceAltitude,
    required this.terrainResolution,
    required this.useGradientMode,
    required this.showHillshade,
    required this.showTerrain,
    required this.onAltitudeChange,
    required this.onWarningAltitudeChange,
  }) : super(key: key);
  
  @override
  State<TerrainControlPanel> createState() => _TerrainControlPanelState();
}
```

### Collapsible Panel Implementation

The control panel uses a collapsible design to save screen space:

```dart
class _TerrainControlPanelState extends State<TerrainControlPanel> {
  // Track expanded sections
  bool _altitudeExpanded = true;
  bool _renderingExpanded = false;
  bool _advancedExpanded = false;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with collapse/expand all button
          _buildPanelHeader(),
          
          // Altitude controls section
          _buildExpandableSection(
            title: "Altitude Controls",
            expanded: _altitudeExpanded,
            onToggle: () => setState(() => _altitudeExpanded = !_altitudeExpanded),
            child: _buildAltitudeControls(),
          ),
          
          // Rendering controls section
          _buildExpandableSection(
            title: "Rendering Controls",
            expanded: _renderingExpanded,
            onToggle: () => setState(() => _renderingExpanded = !_renderingExpanded),
            child: _buildRenderingControls(),
          ),
          
          // Advanced settings section
          _buildExpandableSection(
            title: "Advanced Settings",
            expanded: _advancedExpanded,
            onToggle: () => setState(() => _advancedExpanded = !_advancedExpanded),
            child: _buildAdvancedSettings(),
          ),
        ],
      ),
    );
  }
}
```

### Expandable Section Implementation

Each section of controls can be expanded or collapsed:

```dart
Widget _buildExpandableSection({
  required String title,
  required bool expanded,
  required VoidCallback onToggle,
  required Widget child,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Section header with expand/collapse button
      InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                color: Colors.white,
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70,
                size: 16,
              ),
            ],
          ),
        ),
      ),
      
      // Expandable content with animation
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: expanded ? null : 0,
        child: expanded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: child,
              )
            : Container(),
      ),
    ],
  );
}
```

### Enhanced Altitude Controls

The altitude control section includes sliders and quick-adjust buttons:

```dart
Widget _buildAltitudeControls() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Reference altitude display with digital readout
      ValueListenableBuilder<double>(
        valueListenable: widget.referenceAltitude,
        builder: (context, altitude, child) {
          return Row(
            children: [
              Text(
                "Reference: ",
                style: TextStyle(color: Colors.white70),
              ),
              Text(
                "${NumberFormat.decimalPattern().format(altitude.round())} ft",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          );
        },
      ),
      
      const SizedBox(height: 8),
      
      // Altitude slider with improved styling
      ValueListenableBuilder<double>(
        valueListenable: widget.referenceAltitude,
        builder: (context, altitude, child) {
          return Column(
            children: [
              // Slider with tick marks
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: Colors.lightBlueAccent,
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                  trackHeight: 4,
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                  overlayColor: Colors.lightBlueAccent.withOpacity(0.2),
                ),
                child: Slider(
                  min: 0,
                  max: 30000,
                  divisions: 300, // 100ft increments
                  value: altitude,
                  label: "${altitude.round()} ft",
                  onChanged: (value) {
                    widget.onAltitudeChange(value);
                  },
                ),
              ),
              
              // Altitude range markers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("0", style: TextStyle(color: Colors.white70)),
                    Text("10K", style: TextStyle(color: Colors.white70)),
                    Text("20K", style: TextStyle(color: Colors.white70)),
                    Text("30K", style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      
      const SizedBox(height: 12),
      
      // Quick-adjust buttons
      _buildQuickAdjustButtons(),
      
      const SizedBox(height: 12),
      
      // Warning altitude control
      _buildWarningAltitudeControl(),
    ],
  );
}
```

### Enhanced Quick Adjust Buttons

Quick-adjust buttons with improved styling and haptic feedback:

```dart
Widget _buildQuickAdjustButtons() {
  return Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      _buildAltButton(-1000, "↓ 1K", Colors.orange[300]!),
      _buildAltButton(-500, "↓ 500", Colors.orange[200]!),
      _buildAltButton(-100, "↓ 100", Colors.orange[100]!),
      _buildAltButton(100, "↑ 100", Colors.lightBlue[100]!),
      _buildAltButton(500, "↑ 500", Colors.lightBlue[200]!),
      _buildAltButton(1000, "↑ 1K", Colors.lightBlue[300]!),
    ],
  );
}

Widget _buildAltButton(double change, String label, Color color) {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    onPressed: () {
      // Apply altitude change
      final newAltitude = widget.referenceAltitude.value + change;
      widget.onAltitudeChange(newAltitude.clamp(0, 30000));
      
      // Provide haptic feedback
      HapticFeedback.lightImpact();
    },
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
```

### Enhanced Rendering Controls

Improved UI for controlling terrain rendering options:

```dart
Widget _buildRenderingControls() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Terrain visibility toggle
      ValueListenableBuilder<bool>(
        valueListenable: widget.showTerrain,
        builder: (context, showTerrain, child) {
          return _buildToggleRow(
            label: "Show Terrain",
            value: showTerrain,
            onChanged: (value) {
              widget.showTerrain.value = value;
            },
            icon: Icons.terrain,
          );
        },
      ),
      
      const SizedBox(height: 12),
      
      // Rendering mode toggle with visual indicators
      ValueListenableBuilder<bool>(
        valueListenable: widget.useGradientMode,
        builder: (context, useGradient, child) {
          return Row(
            children: [
              const Text(
                "Rendering Mode:",
                style: TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              _buildModeToggleButton(
                label: "Simple",
                isSelected: !useGradient,
                onTap: () => widget.useGradientMode.value = false,
              ),
              const SizedBox(width: 8),
              _buildModeToggleButton(
                label: "Gradient",
                isSelected: useGradient,
                onTap: () => widget.useGradientMode.value = true,
              ),
            ],
          );
        },
      ),
      
      const SizedBox(height: 12),
      
      // Hillshade toggle with visual preview
      ValueListenableBuilder<bool>(
        valueListenable: widget.showHillshade,
        builder: (context, showHillshade, child) {
          return _buildToggleRowWithPreview(
            label: "Hillshade",
            value: showHillshade,
            onChanged: (value) {
              widget.showHillshade.value = value;
            },
            previewWidget: Container(
              width: 32,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey[800]!, Colors.grey[300]!],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        },
      ),
      
      const SizedBox(height: 12),
      
      // Terrain resolution slider
      ValueListenableBuilder<double>(
        valueListenable: widget.terrainResolution,
        builder: (context, resolution, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "Resolution:",
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "${resolution.round()} m",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    resolution.round() < 100 ? "High" : "Low",
                    style: TextStyle(
                      color: resolution.round() < 100 
                          ? Colors.green 
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: resolution.round() < 100 
                      ? Colors.green 
                      : Colors.orange,
                  inactiveTrackColor: Colors.grey[800],
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  min: 10,
                  max: 500,
                  divisions: 49,
                  value: resolution,
                  onChanged: (value) {
                    widget.terrainResolution.value = value;
                  },
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}
```

### Advanced Settings UI

Advanced visualization settings with detailed controls:

```dart
Widget _buildAdvancedSettings() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Color scheme selector
      _buildColorSchemeSelector(),
      
      const SizedBox(height: 16),
      
      // Vertical exaggeration control
      _buildVerticalExaggerationControl(),
      
      const SizedBox(height: 16),
      
      // Hillshade direction control
      _buildHillshadeDirectionControl(),
      
      const SizedBox(height: 16),
      
      // Warning level configuration button
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[800],
          foregroundColor: Colors.white,
        ),
        onPressed: () {
          _showWarningConfigurationDialog(context);
        },
        icon: const Icon(Icons.warning_amber_rounded),
        label: const Text("Configure Warning Levels"),
      ),
    ],
  );
}
```

### Color Scheme Selector

A visual selector for different terrain color schemes:

```dart
Widget _buildColorSchemeSelector() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Color Scheme:",
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildColorSchemeOption(
              name: "Natural",
              isSelected: _selectedColorScheme == "natural",
              onTap: () => _setColorScheme("natural"),
              colors: [
                Colors.blue[900]!,
                Colors.blue[600]!,
                Colors.blue[300]!,
                Colors.green[300]!,
                Colors.green[500]!,
                Colors.yellow[600]!,
                Colors.orange[800]!,
                Colors.brown[500]!,
                Colors.white,
              ],
            ),
            _buildColorSchemeOption(
              name: "Hypsometric",
              isSelected: _selectedColorScheme == "hypsometric",
              onTap: () => _setColorScheme("hypsometric"),
              colors: [
                Colors.indigo[900]!,
                Colors.blue[700]!,
                Colors.green[600]!,
                Colors.lime[500]!,
                Colors.yellow[500]!,
                Colors.orange[500]!,
                Colors.red[500]!,
                Colors.red[900]!,
                Colors.white70,
              ],
            ),
            _buildColorSchemeOption(
              name: "Terrain",
              isSelected: _selectedColorScheme == "terrain",
              onTap: () => _setColorScheme("terrain"),
              colors: [
                Colors.lightBlue[900]!,
                Colors.lightBlue[300]!,
                Colors.lightGreen[300]!,
                Colors.lightGreen[700]!,
                Colors.lime[700]!,
                Colors.amber[700]!,
                Colors.brown[700]!,
                Colors.brown[900]!,
                Colors.grey[200]!,
              ],
            ),
            _buildColorSchemeOption(
              name: "Monochrome",
              isSelected: _selectedColorScheme == "monochrome",
              onTap: () => _setColorScheme("monochrome"),
              colors: [
                Colors.black,
                Colors.grey[800]!,
                Colors.grey[600]!,
                Colors.grey[400]!,
                Colors.grey[300]!,
                Colors.grey[200]!,
                Colors.grey[100]!,
                Colors.white70,
                Colors.white,
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildColorSchemeOption({
  required String name,
  required bool isSelected,
  required VoidCallback onTap,
  required List<Color> colors,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 12),
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: colors),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}
```

### Vertical Exaggeration Control

A slider for adjusting terrain vertical exaggeration:

```dart
Widget _buildVerticalExaggerationControl() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            "Vertical Exaggeration:",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<double>(
            valueListenable: _verticalExaggeration,
            builder: (context, value, child) {
              return Text(
                "${value.toStringAsFixed(1)}×",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ],
      ),
      ValueListenableBuilder<double>(
        valueListenable: _verticalExaggeration,
        builder: (context, value, child) {
          return SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.purple[300],
              inactiveTrackColor: Colors.grey[800],
              thumbColor: Colors.white,
            ),
            child: Slider(
              min: 0.5,
              max: 3.0,
              divisions: 25,
              value: value,
              onChanged: (value) {
                _verticalExaggeration.value = value;
                _onVerticalExaggerationChanged(value);
              },
            ),
          );
        },
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Text("Less", style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text("Normal", style: TextStyle(color: Colors.white, fontSize: 12)),
          Text("More", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    ],
  );
}
```

### Hillshade Direction Control

A circular control for adjusting hillshading parameters:

```dart
Widget _buildHillshadeDirectionControl() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Light Direction:",
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Circular direction selector
          ValueListenableBuilder<double>(
            valueListenable: _lightDirection,
            builder: (context, direction, child) {
              return GestureDetector(
                onPanUpdate: (details) {
                  // Convert pan position to angle
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final center = Offset(box.size.width / 2, box.size.height / 2);
                  final position = details.localPosition;
                  final angle = math.atan2(
                    position.dy - center.dy,
                    position.dx - center.dx,
                  );
                  
                  // Update direction (0-360 degrees)
                  double degrees = (angle * 180 / math.pi) + 90;
                  if (degrees < 0) degrees += 360;
                  _lightDirection.value = degrees % 360;
                  _onLightDirectionChanged(degrees % 360);
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[900],
                    border: Border.all(color: Colors.grey[700]!, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Direction indicator
                      Positioned(
                        top: 50 - 40 * math.cos((direction - 90) * math.pi / 180),
                        left: 50 + 40 * math.sin((direction - 90) * math.pi / 180),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                      // Center marker
                      const Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          // Direction value display
          ValueListenableBuilder<double>(
            valueListenable: _lightDirection,
            builder: (context, direction, child) {
              String directionText = "";
              if (direction >= 337.5 || direction < 22.5) {
                directionText = "N";
              } else if (direction >= 22.5 && direction < 67.5) {
                directionText = "NE";
              } else if (direction >= 67.5 && direction < 112.5) {
                directionText = "E";
              } else if (direction >= 112.5 && direction < 157.5) {
                directionText = "SE";
              } else if (direction >= 157.5 && direction < 202.5) {
                directionText = "S";
              } else if (direction >= 202.5 && direction < 247.5) {
                directionText = "SW";
              } else if (direction >= 247.5 && direction < 292.5) {
                directionText = "W";
              } else {
                directionText = "NW";
              }
              
              return Column(
                children: [
                  Text(
                    "${direction.round()}°",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    directionText,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ],
  );
}
```

### Warning Configuration Dialog

A modal dialog for detailed warning level configuration:

```dart
void _showWarningConfigurationDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dialog title
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red),
                const SizedBox(width: 8),
                const Text(
                  "Warning Level Configuration",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Warning altitude slider
            _buildWarningLevelSlider(
              label: "Critical Warning",
              value: _warningAltitude.value,
              color: Colors.red,
              onChanged: (value) {
                setState(() {
                  _warningAltitude.value = value;
                  widget.onWarningAltitudeChange(value);
                });
              },
            ),
            
            const SizedBox(height: 16),
            
            // Secondary warning altitude slider
            _buildWarningLevelSlider(
              label: "Caution Warning",
              value: _cautionAltitude.value,
              color: Colors.orange,
              onChanged: (value) {
                setState(() {
                  _cautionAltitude.value = value;
                });
              },
            ),
            
            const SizedBox(height: 16),
            
            // Warning offset slider
            _buildWarningLevelSlider(
              label: "Critical Offset from Ref.",
              value: _criticalOffset.value,
              max: 5000,
              color: Colors.purple,
              onChanged: (value) {
                setState(() {
                  _criticalOffset.value = value;
                });
              },
            ),
            
            const SizedBox(height: 24),
            
            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  _applyWarningSettings();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  "Apply Warning Settings",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

### Display Presets

Presets for quickly switching between common visualization configurations:

```dart
Widget _buildDisplayPresets() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Display Presets:",
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildPresetButton(
              name: "Flight",
              icon: Icons.flight,
              onPressed: () => _applyPreset("flight"),
            ),
            _buildPresetButton(
              name: "Hiking",
              icon: Icons.hiking,
              onPressed: () => _applyPreset("hiking"),
            ),
            _buildPresetButton(
              name: "Nautical",
              icon: Icons.waves,
              onPressed: () => _applyPreset("nautical"),
            ),
            _buildPresetButton(
              name: "Night",
              icon: Icons.nightlight_round,
              onPressed: () => _applyPreset("night"),
            ),
            _buildPresetButton(
              name: "Technical",
              icon: Icons.info_outline,
              onPressed: () => _applyPreset("technical"),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildPresetButton({
  required String name,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueGrey[700],
        foregroundColor: Colors.white,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(name),
    ),
  );
}
```

## UI Interaction and State Management

The UI components communicate with the terrain visualization system through ValueNotifiers:

```dart
void _applyAltitudeChange(double value) {
  // Update reference altitude
  widget.referenceAltitude.value = value;
  
  // Pass the change to the parent handler
  widget.onAltitudeChange(value);
  
  // Provide haptic feedback
  HapticFeedback.selectionClick();
}

void _applyWarningSettings() {
  // Update warning altitude
  widget.onWarningAltitudeChange(_warningAltitude.value);
  
  // Additional warning settings would be applied here
  
  // Force terrain refresh
  _forceTerrainRefresh();
}

void _setColorScheme(String scheme) {
  setState(() {
    _selectedColorScheme = scheme;
  });
  
  // Apply color scheme to terrain rendering
  switch (scheme) {
    case "natural":
      TerrainColorManager.setColorScheme(TerrainColorScheme.natural);
      break;
    case "hypsometric":
      TerrainColorManager.setColorScheme(TerrainColorScheme.hypsometric);
      break;
    case "terrain":
      TerrainColorManager.setColorScheme(TerrainColorScheme.terrain);
      break;
    case "monochrome":
      TerrainColorManager.setColorScheme(TerrainColorScheme.monochrome);
      break;
  }
  
  // Force terrain refresh
  _forceTerrainRefresh();
}
```

## Usage Example

```dart
// Create terrain control panel
final controlPanel = TerrainControlPanel(
  referenceAltitude: _referenceAltitude,
  terrainResolution: _terrainResolution,
  useGradientMode: _useGradientMode,
  showHillshade: _showHillshade,
  showTerrain: _showTerrain,
  onAltitudeChange: (altitude) {
    _applyAltitudeChange(altitude);
  },
  onWarningAltitudeChange: (altitude) {
    _terrainSettings.warningAltitude = altitude;
    _forceTerrainRefresh();
  },
);

// Add control panel to the map screen
return Scaffold(
  body: Stack(
    children: [
      // Map with terrain layers
      _buildMap(),
      
      // Control panel positioned in the top-right corner
      Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        right: 10,
        child: controlPanel,
      ),
    ],
  ),
);
```
