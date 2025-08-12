// import 'package:flutter/material.dart';
// import 'package:maplibre_gl/maplibre_gl.dart';

// void main() {
//   runApp(ExperimentalFeaturesExample());
// }

// class ExperimentalFeaturesExample extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'MapLibre Experimental Features Example',
//       home: MapScreen(),
//     );
//   }
// }

// class MapScreen extends StatefulWidget {
//   @override
//   State<MapScreen> createState() => _MapScreenState();
// }

// class _MapScreenState extends State<MapScreen> {
//   MapLibreMapController? mapController;
//   bool trianglesEnabled = false;

//   static const _demoPosition = CameraPosition(
//     target: LatLng(37.7749, -122.4194), // San Francisco
//     zoom: 12.0,
//   );

//   void _onMapCreated(MapLibreMapController controller) {
//     mapController = controller;
//   }

//   void _onStyleLoaded() {
//     // Add some demo data source and try to add triangle layer
//     _addTriangleLayerDemo();
//   }

//   Future<void> _addTriangleLayerDemo() async {
//     try {
//       // First add a GeoJSON source with triangle data
//       await mapController!.addGeoJsonSource('triangles-source', {
//         'type': 'FeatureCollection',
//         'features': [
//           {
//             'type': 'Feature',
//             'geometry': {
//               'type': 'Point',
//               'coordinates': [-122.4194, 37.7749]
//             },
//             'properties': {
//               'size': 50,
//               'color': '#ff0000'
//             }
//           }
//         ]
//       });

//       // Try to add triangle layer - this will only work if experimental features are enabled
//       await mapController!.addTriangleLayer(
//         'triangles-source',
//         'triangles-layer',
//         TriangleLayerProperties(
//           triangleColor: '#ff0000',
//           triangleSize: 50,
//         ),
//       );

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Triangle layer added successfully!'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       }
//     } on ExperimentalFeatureException catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Triangle layers disabled: ${e.enableInstruction}'),
//             backgroundColor: Colors.orange,
//             duration: const Duration(seconds: 5),
//           ),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to add triangle layer: $e'),
//             backgroundColor: Colors.red,
//           ),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Experimental Features Demo'),
//         actions: [
//           Switch(
//             value: trianglesEnabled,
//             onChanged: (value) {
//               setState(() {
//                 trianglesEnabled = value;
//               });
//             },
//           ),
//           const Padding(
//             padding: EdgeInsets.only(right: 16.0),
//             child: Center(child: Text('Triangles')),
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(16.0),
//             color: Colors.blue.shade50,
//             child: Text(
//               trianglesEnabled
//                   ? 'Triangle layers are ENABLED - they will work when added'
//                   : 'Triangle layers are DISABLED - adding them will throw an exception',
//               style: TextStyle(
//                 fontWeight: FontWeight.bold,
//                 color: trianglesEnabled ? Colors.green : Colors.orange,
//               ),
//             ),
//           ),
//           Expanded(
//             child: MapLibreMap(
//               initialCameraPosition: _demoPosition,
//               // This is the key - enabling experimental features
//               experimentalFeatures: trianglesEnabled
//                   ? MapLibreExperimentalFeatures.triangles
//                   : MapLibreExperimentalFeatures.none,
//               onMapCreated: _onMapCreated,
//               onStyleLoadedCallback: _onStyleLoaded,
//             ),
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _addTriangleLayerDemo,
//         tooltip: 'Try adding triangle layer',
//         child: const Icon(Icons.change_history), // Triangle icon
//       ),
//     );
//   }
// }
