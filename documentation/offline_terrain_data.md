# Offline Terrain Data Support

This document provides detailed information on the offline terrain data support implementation in the FlightCanvas Terrain plugin, which allows users to access terrain elevation data without an active internet connection.

## Overview

The FlightCanvas Terrain plugin supports offline terrain visualization by downloading, storing, and efficiently retrieving LERC-compressed elevation data on the device's local storage. This implementation enables pilots and other users to access critical terrain information in areas with limited or no connectivity.

## Implementation Architecture

Offline terrain data functionality is built on top of the plugin's caching system and extends it with specific capabilities for managing downloaded terrain data.

### Key Components

1. **Terrain Data Manager**: Coordinates downloading, storage, and access to offline terrain data
2. **Region Download Manager**: Handles the download of multiple terrain tiles for a defined region
3. **Offline Storage Manager**: Organizes and stores terrain data on the device
4. **Offline-First TileProvider**: Prioritizes local terrain data over network requests

## Offline Data Storage Structure

Offline terrain data is organized using a structured directory hierarchy:

```
/app_documents/
├── terrain_data/
│   ├── offline/
│   │   ├── region_metadata.json  # Contains metadata about downloaded regions
│   │   ├── region_1/
│   │   │   ├── metadata.json     # Region-specific metadata
│   │   │   ├── z_12/            # Zoom level 12 directory
│   │   │   │   ├── x_1234_y_5678.lerc  # Terrain tile at coordinates x=1234, y=5678
│   │   │   │   └── ...
│   │   │   ├── z_13/            # Zoom level 13 directory
│   │   │   └── ...
│   │   ├── region_2/
│   │   └── ...
│   └── cache/
│       └── ...                   # Standard cache directory for non-offline data
└── ...
```

## Region Download Process

The process for downloading terrain data for offline use involves several steps:

### 1. Region Selection

Users can select a geographic region for offline download through:

- Drawing a region on a map
- Entering coordinates manually
- Selecting predefined regions

The region is defined by:
```dart
class TerrainRegion {
  final String id;
  final String name;
  final LatLngBounds bounds;
  final List<int> zoomLevels;
  final int estimatedTileCount;
  final int estimatedDataSize;
  
  // Additional metadata
  DateTime? dateDownloaded;
  double downloadProgress = 0.0;
  DownloadStatus status = DownloadStatus.notStarted;
}
```

### 2. Download Planning

Before download begins, the system:

1. Calculates tiles needed for the selected region
2. Estimates storage requirements
3. Verifies device has sufficient storage
4. Creates a download queue prioritizing lower zoom levels first

```dart
Future<TerrainRegion> planRegionDownload(LatLngBounds bounds, List<int> zoomLevels) async {
  final String regionId = _generateRegionId();
  final String regionName = "Region $regionId";
  
  // Calculate tile coordinates for all requested zoom levels
  int totalTiles = 0;
  final Map<int, List<TileCoordinates>> tilesByZoom = {};
  
  for (int zoom in zoomLevels) {
    final tiles = _calculateTilesForBounds(bounds, zoom);
    tilesByZoom[zoom] = tiles;
    totalTiles += tiles.length;
  }
  
  // Estimate data size (average LERC tile size * number of tiles)
  const avgTileSizeKb = 15; // Average LERC tile size in KB
  final estimatedSizeKb = totalTiles * avgTileSizeKb;
  
  return TerrainRegion(
    id: regionId,
    name: regionName,
    bounds: bounds,
    zoomLevels: zoomLevels,
    estimatedTileCount: totalTiles,
    estimatedDataSize: estimatedSizeKb,
  );
}
```

### 3. Download Execution

The download process:

1. Creates the necessary directory structure
2. Downloads tiles in batches to manage memory usage
3. Updates progress with notifications to the UI
4. Handles connection interruptions with resume capability

```dart
Future<bool> downloadRegion(TerrainRegion region) async {
  // Prepare directories
  final regionDir = Directory('${await _getOfflineDirPath()}/${region.id}');
  await regionDir.create(recursive: true);
  
  // Save region metadata
  await _saveRegionMetadata(region);
  
  // Start download process for each zoom level
  int totalDownloaded = 0;
  final int totalTiles = region.estimatedTileCount;
  
  try {
    for (int zoom in region.zoomLevels) {
      final zoomDir = Directory('${regionDir.path}/z_$zoom');
      await zoomDir.create();
      
      final tiles = _calculateTilesForBounds(region.bounds, zoom);
      
      // Download tiles in batches
      const batchSize = 10;
      for (int i = 0; i < tiles.length; i += batchSize) {
        final batch = tiles.skip(i).take(batchSize);
        await Future.wait(
          batch.map((tile) => _downloadAndSaveTile(tile, zoomDir.path))
        );
        
        totalDownloaded += batch.length;
        region.downloadProgress = totalDownloaded / totalTiles;
        
        // Notify listeners about progress
        _progressController.add(region);
      }
    }
    
    region.status = DownloadStatus.completed;
    region.dateDownloaded = DateTime.now();
    await _saveRegionMetadata(region);
    return true;
  } catch (e) {
    region.status = DownloadStatus.failed;
    await _saveRegionMetadata(region);
    return false;
  }
}
```

### 4. Tile Download and Storage

Individual tiles are downloaded and stored efficiently:

```dart
Future<void> _downloadAndSaveTile(TileCoordinates tile, String dirPath) async {
  try {
    final tileUrl = _buildLercTileUrl(tile);
    final response = await _httpClient.get(Uri.parse(tileUrl));
    
    if (response.statusCode == 200) {
      final tileData = response.bodyBytes;
      final tileFile = File('$dirPath/x_${tile.x}_y_${tile.y}.lerc');
      await tileFile.writeAsBytes(tileData);
    } else {
      throw Exception('Failed to download tile: ${response.statusCode}');
    }
  } catch (e) {
    rethrow; // Bubble up for retry/error handling
  }
}
```

## Offline-First Data Access

A key aspect of the offline implementation is the "offline-first" approach to data access:

### TileProvider Implementation

The `OfflineLercTileProvider` prioritizes locally stored data before making network requests:

```dart
class OfflineLercTileProvider extends LercTileProvider {
  final TerrainOfflineManager offlineManager;
  
  OfflineLercTileProvider({
    required this.offlineManager,
    required super.referenceAltitude,
    // Other parameters
  });
  
  @override
  Future<DecodedLercData?> getLercData(TileCoordinates coordinates) async {
    // 1. Check if the tile exists offline
    final offlineTileData = await offlineManager.getOfflineTileData(coordinates);
    if (offlineTileData != null) {
      // Decode and return the offline tile
      return await LercDecoder.decode(offlineTileData);
    }
    
    // 2. Fall back to online source if not available offline
    return await super.getLercData(coordinates);
  }
}
```

### Offline Manager Integration

The `TerrainOfflineManager` handles checking for and retrieving offline data:

```dart
class TerrainOfflineManager {
  // Check if a specific tile exists offline
  Future<bool> isTileAvailableOffline(TileCoordinates coordinates) async {
    final File tileFile = await _getTileFile(coordinates);
    return await tileFile.exists();
  }
  
  // Get offline tile data if available
  Future<Uint8List?> getOfflineTileData(TileCoordinates coordinates) async {
    final File tileFile = await _getTileFile(coordinates);
    if (await tileFile.exists()) {
      return await tileFile.readAsBytes();
    }
    return null;
  }
  
  // Find the file for a specific tile (checking all downloaded regions)
  Future<File> _getTileFile(TileCoordinates coordinates) async {
    final offlineDir = await _getOfflineDirPath();
    final regions = await _listRegions();
    
    // Check each region for the tile
    for (final region in regions) {
      if (region.zoomLevels.contains(coordinates.z)) {
        final tilePath = '$offlineDir/${region.id}/z_${coordinates.z}/x_${coordinates.x}_y_${coordinates.y}.lerc';
        final file = File(tilePath);
        if (await file.exists()) {
          return file;
        }
      }
    }
    
    // Return a non-existent file path if tile not found
    return File('$offlineDir/not_found_${coordinates.z}_${coordinates.x}_${coordinates.y}.lerc');
  }
}
```

## User Interface for Offline Data Management

The plugin provides several user interface components for managing offline terrain data:

1. **Region Selection UI**: Map-based interface for selecting regions
2. **Download Manager UI**: Shows download progress and manages pending downloads
3. **Region Manager UI**: Lists downloaded regions with options to view or delete
4. **Storage Usage View**: Shows disk space usage by offline data

## Background Downloads and Resume Support

The implementation supports:

1. **Background Downloads**: Continue downloading when app is in background
2. **Download Resumption**: Resume interrupted downloads
3. **Prioritization**: Specify regions that should be downloaded first

```dart
// Resume all pending downloads
Future<void> resumeAllPendingDownloads() async {
  final regions = await _listRegions();
  for (final region in regions) {
    if (region.status == DownloadStatus.inProgress || 
        region.status == DownloadStatus.failed) {
      // Queue for download continuation
      _downloadQueue.add(region);
    }
  }
  _processDownloadQueue();
}

// Process download queue one at a time
Future<void> _processDownloadQueue() async {
  if (_isDownloading || _downloadQueue.isEmpty) return;
  
  _isDownloading = true;
  final region = _downloadQueue.removeFirst();
  
  final success = await downloadRegion(region);
  
  _isDownloading = false;
  _processDownloadQueue(); // Process next in queue
}
```

## Optimizations for Offline Data

Several optimizations are implemented to make offline data more efficient:

1. **Multiple Resolution Support**: Store data at various zoom levels for detail/coverage balance
2. **Partial Region Support**: Allow downloading only portions of larger regions
3. **Efficient Storage**: Use LERC's native compression to minimize storage requirements
4. **Lazy Decoding**: Only decode tiles when needed for rendering

## Data Consistency and Updates

The plugin maintains data consistency through:

1. **Version Tracking**: Metadata includes data source version information
2. **Selective Updates**: Allow updating specific regions without full re-download
3. **Validation**: Verify data integrity after download

## Conclusion

The offline terrain data support in FlightCanvas Terrain provides robust capabilities for accessing terrain elevation data in disconnected environments. By combining efficient storage formats with a comprehensive download management system and offline-first data access approach, the plugin ensures users can rely on terrain visualization regardless of network connectivity.

This implementation is particularly valuable for aviation applications where network coverage may be limited during flight, ensuring that critical terrain information remains accessible when it's needed most.
