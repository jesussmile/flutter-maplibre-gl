# Custom Terrain Data Sources

This document describes the implementation of custom terrain data sources in the FlightCanvas Terrain project, allowing the application to fetch LERC-encoded terrain data from various sources.

## Overview

The FlightCanvas Terrain project supports loading terrain data from multiple source types:

1. **Network Sources**: Fetching terrain tiles from remote servers via HTTP
2. **Asset Sources**: Loading terrain data from application assets
3. **Local File Sources**: Using terrain data from local device storage
4. **Custom Sources**: Implementing custom data providers for specialized needs

This flexible approach allows the application to work with different data sources while maintaining a consistent interface for terrain rendering.

## Implementation Details

### Data Source Abstraction

The system uses an abstraction layer to handle different data sources:

```dart
abstract class LercDataSource {
  /// Get LERC data for a specific tile
  Future<Uint8List?> getTileData(int z, int x, int y);
  
  /// Check if data is available for a specific tile
  Future<bool> hasTileData(int z, int x, int y);
  
  /// Get source type identifier
  String get sourceType;
  
  /// Get source description
  String get description;
  
  /// Dispose resources associated with this source
  Future<void> dispose();
}
```

### Network Data Source

Implementation for fetching terrain data from web servers:

```dart
class NetworkLercDataSource implements LercDataSource {
  final String urlTemplate;
  final Map<String, String>? headers;
  final HttpClient _httpClient = HttpClient();
  final LRUCache<String, Uint8List> _cache = LRUCache<String, Uint8List>(capacity: 100);
  
  NetworkLercDataSource({
    required this.urlTemplate,
    this.headers,
  });
  
  @override
  String get sourceType => "network";
  
  @override
  String get description => "Remote LERC tiles from $urlTemplate";
  
  @override
  Future<Uint8List?> getTileData(int z, int x, int y) async {
    final String url = _formatUrl(z, x, y);
    final String cacheKey = "$z-$x-$y";
    
    // Check cache first
    final cachedData = _cache.get(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    
    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      
      // Add headers if provided
      if (headers != null) {
        headers!.forEach((key, value) {
          request.headers.add(key, value);
        });
      }
      
      final response = await request.close();
      
      if (response.statusCode == 200) {
        // Read response data
        final List<List<int>> chunks = [];
        await for (var chunk in response) {
          chunks.add(chunk);
        }
        
        // Combine chunks into a single list
        int totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
        final Uint8List data = Uint8List(totalLength);
        
        int offset = 0;
        for (var chunk in chunks) {
          data.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        
        // Cache the data
        _cache.put(cacheKey, data);
        
        return data;
      }
    } catch (e) {
      print("Error fetching tile ($z,$x,$y): $e");
    }
    
    return null;
  }
  
  @override
  Future<bool> hasTileData(int z, int x, int y) async {
    final String url = _formatUrl(z, x, y);
    final String cacheKey = "$z-$x-$y";
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      return true;
    }
    
    try {
      final request = await _httpClient.headUrl(Uri.parse(url));
      
      // Add headers if provided
      if (headers != null) {
        headers!.forEach((key, value) {
          request.headers.add(key, value);
        });
      }
      
      final response = await request.close();
      await response.drain(); // Discard the response body
      
      return response.statusCode == 200;
    } catch (e) {
      print("Error checking tile availability ($z,$x,$y): $e");
      return false;
    }
  }
  
  String _formatUrl(int z, int x, int y) {
    return urlTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }
  
  @override
  Future<void> dispose() async {
    _httpClient.close();
    _cache.clear();
  }
}
```

### Asset Data Source

Implementation for loading terrain data from application assets:

```dart
class AssetLercDataSource implements LercDataSource {
  final String assetPathTemplate;
  final AssetBundle assetBundle;
  final LRUCache<String, Uint8List> _cache = LRUCache<String, Uint8List>(capacity: 20);
  
  AssetLercDataSource({
    required this.assetPathTemplate,
    AssetBundle? bundle,
  }) : assetBundle = bundle ?? rootBundle;
  
  @override
  String get sourceType => "asset";
  
  @override
  String get description => "Asset LERC tiles from $assetPathTemplate";
  
  @override
  Future<Uint8List?> getTileData(int z, int x, int y) async {
    final String path = _formatPath(z, x, y);
    final String cacheKey = "$z-$x-$y";
    
    // Check cache first
    final cachedData = _cache.get(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    
    try {
      final ByteData data = await assetBundle.load(path);
      final Uint8List bytes = data.buffer.asUint8List();
      
      // Cache the data
      _cache.put(cacheKey, bytes);
      
      return bytes;
    } catch (e) {
      print("Error loading asset tile ($z,$x,$y) from $path: $e");
      return null;
    }
  }
  
  @override
  Future<bool> hasTileData(int z, int x, int y) async {
    final String cacheKey = "$z-$x-$y";
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      return true;
    }
    
    try {
      final String path = _formatPath(z, x, y);
      
      // Attempt to load the asset (this will throw if not found)
      await assetBundle.loadStructuredData<bool>(path, (String value) async {
        return true;
      });
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  String _formatPath(int z, int x, int y) {
    return assetPathTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }
  
  @override
  Future<void> dispose() async {
    _cache.clear();
  }
}
```

### Local File Data Source

Implementation for loading terrain data from device storage:

```dart
class FileLercDataSource implements LercDataSource {
  final String filePathTemplate;
  final LRUCache<String, Uint8List> _cache = LRUCache<String, Uint8List>(capacity: 50);
  
  FileLercDataSource({
    required this.filePathTemplate,
  });
  
  @override
  String get sourceType => "file";
  
  @override
  String get description => "Local LERC files from $filePathTemplate";
  
  @override
  Future<Uint8List?> getTileData(int z, int x, int y) async {
    final String path = _formatPath(z, x, y);
    final String cacheKey = "$z-$x-$y";
    
    // Check cache first
    final cachedData = _cache.get(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    
    try {
      final File file = File(path);
      if (await file.exists()) {
        final Uint8List bytes = await file.readAsBytes();
        
        // Cache the data
        _cache.put(cacheKey, bytes);
        
        return bytes;
      }
    } catch (e) {
      print("Error reading local tile ($z,$x,$y) from $path: $e");
    }
    
    return null;
  }
  
  @override
  Future<bool> hasTileData(int z, int x, int y) async {
    final String cacheKey = "$z-$x-$y";
    
    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      return true;
    }
    
    try {
      final String path = _formatPath(z, x, y);
      final File file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
  
  String _formatPath(int z, int x, int y) {
    return filePathTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
  }
  
  @override
  Future<void> dispose() async {
    _cache.clear();
  }
}
```

### Custom Data Source

Abstract class for implementing custom data sources:

```dart
abstract class CustomLercDataSource implements LercDataSource {
  @override
  String get sourceType => "custom";
  
  // Implementations must provide these methods
  @override
  Future<Uint8List?> getTileData(int z, int x, int y);
  
  @override
  Future<bool> hasTileData(int z, int x, int y);
}
```

### Combined Data Source

A data source that can combine multiple sources with fallback logic:

```dart
class CombinedLercDataSource implements LercDataSource {
  final List<LercDataSource> sources;
  final bool useFirstAvailable;
  
  CombinedLercDataSource({
    required this.sources,
    this.useFirstAvailable = true,
  });
  
  @override
  String get sourceType => "combined";
  
  @override
  String get description => "Combined source (${sources.length} sources)";
  
  @override
  Future<Uint8List?> getTileData(int z, int x, int y) async {
    if (useFirstAvailable) {
      // Return first available tile data
      for (final source in sources) {
        if (await source.hasTileData(z, x, y)) {
          return source.getTileData(z, x, y);
        }
      }
      return null;
    } else {
      // Try each source in order
      for (final source in sources) {
        final tileData = await source.getTileData(z, x, y);
        if (tileData != null) {
          return tileData;
        }
      }
      return null;
    }
  }
  
  @override
  Future<bool> hasTileData(int z, int x, int y) async {
    for (final source in sources) {
      if (await source.hasTileData(z, x, y)) {
        return true;
      }
    }
    return false;
  }
  
  @override
  Future<void> dispose() async {
    for (final source in sources) {
      await source.dispose();
    }
  }
}
```

### Data Source Manager

A central manager to create and handle data sources:

```dart
class LercDataSourceManager {
  // Singleton instance
  static final LercDataSourceManager _instance = LercDataSourceManager._internal();
  
  factory LercDataSourceManager() {
    return _instance;
  }
  
  LercDataSourceManager._internal();
  
  final Map<String, LercDataSource> _sources = {};
  
  // Create or get a network data source
  LercDataSource network(String urlTemplate, {Map<String, String>? headers, String? id}) {
    final sourceId = id ?? "network_${urlTemplate.hashCode}";
    
    if (!_sources.containsKey(sourceId)) {
      _sources[sourceId] = NetworkLercDataSource(
        urlTemplate: urlTemplate,
        headers: headers,
      );
    }
    
    return _sources[sourceId]!;
  }
  
  // Create or get an asset data source
  LercDataSource asset(String assetPathTemplate, {String? id}) {
    final sourceId = id ?? "asset_${assetPathTemplate.hashCode}";
    
    if (!_sources.containsKey(sourceId)) {
      _sources[sourceId] = AssetLercDataSource(
        assetPathTemplate: assetPathTemplate,
      );
    }
    
    return _sources[sourceId]!;
  }
  
  // Create or get a file data source
  LercDataSource file(String filePathTemplate, {String? id}) {
    final sourceId = id ?? "file_${filePathTemplate.hashCode}";
    
    if (!_sources.containsKey(sourceId)) {
      _sources[sourceId] = FileLercDataSource(
        filePathTemplate: filePathTemplate,
      );
    }
    
    return _sources[sourceId]!;
  }
  
  // Create a combined data source
  LercDataSource combined(List<LercDataSource> sources, {bool useFirstAvailable = true, String? id}) {
    final sourceId = id ?? "combined_${sources.hashCode}";
    
    if (!_sources.containsKey(sourceId)) {
      _sources[sourceId] = CombinedLercDataSource(
        sources: sources,
        useFirstAvailable: useFirstAvailable,
      );
    }
    
    return _sources[sourceId]!;
  }
  
  // Register a custom data source
  void registerCustomSource(String id, LercDataSource source) {
    _sources[id] = source;
  }
  
  // Get a registered data source
  LercDataSource? getSource(String id) {
    return _sources[id];
  }
  
  // Dispose all sources and clear the registry
  Future<void> disposeAll() async {
    for (final source in _sources.values) {
      await source.dispose();
    }
    _sources.clear();
  }
}
```

### Integration with LercTileProvider

The custom data sources integrate with the `LercTileProvider` for terrain rendering:

```dart
class LercTileProvider extends TileProvider {
  final LercDataSource dataSource;
  final double referenceAltitude;
  final double warningAltitude;
  final double minElevation;
  final double terrainResolution;
  final ValueChanged<double>? onElevationRead;
  
  LercTileProvider({
    required this.dataSource,
    required this.referenceAltitude,
    required this.warningAltitude,
    required this.minElevation,
    required this.terrainResolution,
    this.onElevationRead,
  }) {
    // Initialize provider with data source
    LercTileProvider._currentAltitude = referenceAltitude;
    
    // Start cleanup timer if not already running
    _cleanupTimer ??= Timer.periodic(
      Duration(milliseconds: TimerSettings().cleanupInterval),
      (_) {
        _cleanupUnusedElevations();
      },
    );
  }
  
  // Factory constructor for network source
  static LercTileProvider network(
    String urlTemplate, {
    required double referenceAltitude,
    required double warningAltitude,
    required double minElevation,
    required double terrainResolution,
    Map<String, String>? headers,
    ValueChanged<double>? onElevationRead,
  }) {
    final dataSource = LercDataSourceManager().network(urlTemplate, headers: headers);
    
    return LercTileProvider(
      dataSource: dataSource,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
      minElevation: minElevation,
      terrainResolution: terrainResolution,
      onElevationRead: onElevationRead,
    );
  }
  
  // Factory constructor for asset source
  static LercTileProvider asset(
    String assetPathTemplate, {
    required double referenceAltitude,
    required double warningAltitude,
    required double minElevation,
    required double terrainResolution,
    ValueChanged<double>? onElevationRead,
  }) {
    final dataSource = LercDataSourceManager().asset(assetPathTemplate);
    
    return LercTileProvider(
      dataSource: dataSource,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
      minElevation: minElevation,
      terrainResolution: terrainResolution,
      onElevationRead: onElevationRead,
    );
  }
  
  // Factory constructor for file source
  static LercTileProvider file(
    String filePathTemplate, {
    required double referenceAltitude,
    required double warningAltitude,
    required double minElevation,
    required double terrainResolution,
    ValueChanged<double>? onElevationRead,
  }) {
    final dataSource = LercDataSourceManager().file(filePathTemplate);
    
    return LercTileProvider(
      dataSource: dataSource,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
      minElevation: minElevation,
      terrainResolution: terrainResolution,
      onElevationRead: onElevationRead,
    );
  }
  
  // Implementation of TileProvider method
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _LercTileImage(
      dataSource: dataSource,
      coordinates: coordinates,
      referenceAltitude: referenceAltitude,
      warningAltitude: warningAltitude,
      minElevation: minElevation,
      altitudeBucketSize: _altitudeBucketSize,
      onElevationRead: onElevationRead,
      pixelCache: _renderedPixelCache,
    );
  }
}
```

### Data Fetching in _LercTileImage

The `_LercTileImage` class is updated to work with various data sources:

```dart
class _LercTileImage extends ImageProvider<_LercTileImage> {
  final LercDataSource dataSource;
  final TileCoordinates coordinates;
  final double referenceAltitude;
  final double warningAltitude;
  final double minElevation;
  final double altitudeBucketSize;
  final ValueChanged<double>? onElevationRead;
  final Map<String, Uint8List> pixelCache;
  
  // Constructor and other properties...
  
  // Get the LERC data for this tile
  Future<Uint8List?> _getLercData() async {
    final z = coordinates.z;
    final x = coordinates.x;
    final y = coordinates.y;
    
    try {
      return await dataSource.getTileData(z, x, y);
    } catch (e) {
      print("Error fetching LERC tile data ($z,$x,$y): $e");
      return null;
    }
  }
  
  // Process the LERC data to extract elevation values
  Future<Float64List?> _processLercData(Uint8List lercData) async {
    try {
      // Decode LERC data using the LERC decoder
      final decodedData = await LercIsolateDecoder.decode(lercData);
      
      // Extract elevation values for the tile
      if (decodedData != null) {
        // Create an array for the pixel elevations
        const tileSize = 256;
        final elevations = Float64List(tileSize * tileSize);
        
        // Extract elevations for this tile's geographic area
        final lat1 = _tile2lat(coordinates.y, coordinates.z);
        final lat2 = _tile2lat(coordinates.y + 1, coordinates.z);
        final lon1 = _tile2lon(coordinates.x, coordinates.z);
        final lon2 = _tile2lon(coordinates.x + 1, coordinates.z);
        
        // Sample elevations from the decoded data
        for (int py = 0; py < tileSize; py++) {
          final t = py / tileSize;
          final lat = lat1 * (1 - t) + lat2 * t;
          
          for (int px = 0; px < tileSize; px++) {
            final s = px / tileSize;
            final lon = lon1 * (1 - s) + lon2 * s;
            
            // Get elevation from the decoded data
            final elevation = decodedData.getElevationAtPoint(lat, lon);
            elevations[py * tileSize + px] = elevation;
          }
        }
        
        return elevations;
      }
    } catch (e) {
      print("Error processing LERC data: $e");
    }
    
    return null;
  }
  
  // Overridden methods to use the data source
  @override
  Future<_LercTileImage> obtainKey(ImageConfiguration configuration) {
    LercTileProvider._activeTileKeys.add(_trackingKey);
    return SynchronousFuture<_LercTileImage>(this);
  }
  
  @override
  ImageStreamCompleter loadImage(_LercTileImage key, ImageDecoderCallback decode) {
    // Check cache first...
    
    // Create new image
    final completer = OneFrameImageStreamCompleter(_createImage());
    _currentCompleter = completer;
    return completer;
  }
  
  Future<ImageInfo> _createImage() async {
    // Get LERC data for this tile
    final lercData = await _getLercData();
    if (lercData == null) {
      // Return empty/transparent image if no data
      return _createEmptyImage();
    }
    
    // Process the LERC data
    final elevations = await _processLercData(lercData);
    if (elevations == null) {
      // Return empty/transparent image if processing failed
      return _createEmptyImage();
    }
    
    // Render terrain image using the elevations
    final pixels = _renderTerrainImage(elevations);
    
    // Create image from pixels
    return _createImageFromPixels(pixels, 256, 256);
  }
}
```

## URL Template Format

The URL template format for network sources follows a standard convention:

```
https://example.com/terrain/{z}/{x}/{y}.lerc2
```

Where:
- `{z}` is the zoom level
- `{x}` is the horizontal tile coordinate
- `{y}` is the vertical tile coordinate

## Asset Path Template Format

For assets bundled with the application:

```
assets/terrain/{z}/{x}/{y}.lerc2
```

## File Path Template Format

For files stored on the device:

```
/data/user/0/com.example.app/files/terrain/{z}/{x}/{y}.lerc2
```

## Usage Examples

### Network Source Example

```dart
// Create a network tile provider
final networkProvider = LercTileProvider.network(
  'https://example.com/terrain/{z}/{x}/{y}.lerc2',
  referenceAltitude: 10000,
  warningAltitude: 15000,
  minElevation: -11000,
  terrainResolution: 100,
  headers: {
    'Authorization': 'Bearer $apiKey',
  },
);

// Use in a TileLayer
TileLayer(
  tileProvider: networkProvider,
  maxZoom: 19,
  minZoom: 1,
  urlTemplate: "unused",
),
```

### Asset Source Example

```dart
// Create an asset tile provider
final assetProvider = LercTileProvider.asset(
  'assets/terrain/{z}/{x}/{y}.lerc2',
  referenceAltitude: 10000,
  warningAltitude: 15000,
  minElevation: -11000,
  terrainResolution: 100,
);

// Use in a TileLayer
TileLayer(
  tileProvider: assetProvider,
  maxZoom: 19,
  minZoom: 1,
  urlTemplate: "unused",
),
```

### File Source Example

```dart
// Create a file tile provider
final fileProvider = LercTileProvider.file(
  '/data/user/0/com.example.app/files/terrain/{z}/{x}/{y}.lerc2',
  referenceAltitude: 10000,
  warningAltitude: 15000,
  minElevation: -11000,
  terrainResolution: 100,
);

// Use in a TileLayer
TileLayer(
  tileProvider: fileProvider,
  maxZoom: 19,
  minZoom: 1,
  urlTemplate: "unused",
),
```

### Combined Source Example

```dart
// Create data sources
final dataSourceManager = LercDataSourceManager();

final networkSource = dataSourceManager.network(
  'https://example.com/terrain/{z}/{x}/{y}.lerc2',
);

final fileSource = dataSourceManager.file(
  '/data/user/0/com.example.app/files/terrain/{z}/{x}/{y}.lerc2',
);

// Create combined source (file first, network as fallback)
final combinedSource = dataSourceManager.combined([fileSource, networkSource]);

// Create provider with combined source
final combinedProvider = LercTileProvider(
  dataSource: combinedSource,
  referenceAltitude: 10000,
  warningAltitude: 15000,
  minElevation: -11000,
  terrainResolution: 100,
);

// Use in a TileLayer
TileLayer(
  tileProvider: combinedProvider,
  maxZoom: 19,
  minZoom: 1,
  urlTemplate: "unused",
),
```
