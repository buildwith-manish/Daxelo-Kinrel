// lib/services/asset_download_service.dart
//
// Downloads indian_kinship.json.gz from GitHub Releases (~15MB compressed).
// No SQLite. The JSON provides chainRules for full resolution accuracy.

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DownloadProgress {
  final double progress;     // 0.0 to 1.0
  final String message;
  final int bytesDownloaded;
  final int? totalBytes;

  const DownloadProgress({
    required this.progress,
    required this.message,
    required this.bytesDownloaded,
    this.totalBytes,
  });
}

class AssetDownloadService {
  static const String _releaseBaseUrl =
      'https://github.com/buildwith-manish/Daxelo-Kinrel/releases/download/v1.0.0-assets';

  static const String _indianJsonUrl = '$_releaseBaseUrl/indian_kinship.json.gz';

  static const Map<String, String> _globalJsonUrls = {
    'arabic':      '$_releaseBaseUrl/arabic_kinship_production.json.gz',
    'korean':      '$_releaseBaseUrl/korean_kinship_production.json.gz',
    'japanese':    '$_releaseBaseUrl/japanese_kinship_production.json.gz',
    'russian':     '$_releaseBaseUrl/russian_kinship_production_v2.json.gz',
    'vietnamese':  '$_releaseBaseUrl/vietnamese_kinship_production_v2.json.gz',
    'chinese':     '$_releaseBaseUrl/chinese_kinship_production.json.gz',
  };

  static const String _jsonFileName    = 'indian_kinship.json';
  static const String _jsonGzFileName  = 'indian_kinship.json.gz';
  static const String _versionMarker   = 'asset_version_1_0_0.txt';
  static const String _currentVersion  = '1.0.0';

  final Dio _dio;
  AssetDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  /// True if full indian_kinship.json is downloaded and current.
  Future<bool> areAssetsReady() async {
    try {
      final dir = await _getAssetDir();
      final jsonFile = File('${dir.path}/$_jsonFileName');
      final versionFile = File('${dir.path}/$_versionMarker');

      if (!jsonFile.existsSync()) return false;
      if (!versionFile.existsSync()) return false;
      if ((await versionFile.readAsString()).trim() != _currentVersion) return false;

      // Sanity check: full JSON should be >10MB
      if (await jsonFile.length() < 10 * 1024 * 1024) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download indian_kinship.json.gz, decompress, and cache.
  /// Yields progress from 0.0 → 1.0.
  Stream<DownloadProgress> downloadAssets() async* {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw AssetDownloadException('No internet connection.');
    }

    final dir = await _getAssetDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final gzPath  = '${dir.path}/$_jsonGzFileName';
    final outPath = '${dir.path}/$_jsonFileName';

    // Remove existing decompressed file
    final outFile = File(outPath);
    if (outFile.existsSync()) await outFile.delete();

    // Download with progress
    await _dio.download(
      _indianJsonUrl,
      gzPath,
      onReceiveProgress: (received, total) {
        // Progress emitted via controller below
      },
    );

    // Can't easily yield from inside dio callback, so yield completion:
    yield const DownloadProgress(
      progress: 0.9,
      message: 'Extracting data...',
      bytesDownloaded: 0,
    );

    // Decompress
    final inputBytes = await File(gzPath).readAsBytes();
    final decompressed = gzip.decode(inputBytes);
    await File(outPath).writeAsBytes(decompressed);

    // Clean up .gz
    if (File(gzPath).existsSync()) await File(gzPath).delete();

    // Write version marker
    await File('${dir.path}/$_versionMarker').writeAsString(_currentVersion);

    yield const DownloadProgress(
      progress: 1.0,
      message: 'Ready',
      bytesDownloaded: 0,
    );
  }

  /// Download with explicit progress stream (preferred for UI).
  Stream<DownloadProgress> downloadAssetsWithProgress() async* {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw AssetDownloadException('No internet connection.');
    }

    final dir = await _getAssetDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final gzPath  = '${dir.path}/$_jsonGzFileName';
    final outPath = '${dir.path}/$_jsonFileName';

    final controller = StreamController<DownloadProgress>();

    // Download in background, emit progress
    _dio.download(
      _indianJsonUrl,
      gzPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          controller.add(DownloadProgress(
            progress: (received / total) * 0.85,
            message: 'Downloading relationship data...',
            bytesDownloaded: received,
            totalBytes: total,
          ));
        }
      },
    ).then((_) async {
      controller.add(const DownloadProgress(
        progress: 0.9, message: 'Extracting...', bytesDownloaded: 0,
      ));
      final inputBytes = await File(gzPath).readAsBytes();
      final decompressed = gzip.decode(inputBytes);
      await File(outPath).writeAsBytes(decompressed);
      if (File(gzPath).existsSync()) await File(gzPath).delete();
      await File('${dir.path}/$_versionMarker').writeAsString(_currentVersion);
      controller.add(const DownloadProgress(
        progress: 1.0, message: 'Ready', bytesDownloaded: 0,
      ));
      await controller.close();
    }).catchError((e) {
      controller.addError(AssetDownloadException('Download failed: $e'));
      controller.close();
    });

    yield* controller.stream;
  }

  /// Path to the downloaded full JSON.
  Future<String> getJsonPath() async {
    final dir = await _getAssetDir();
    return '${dir.path}/$_jsonFileName';
  }

  /// Download a specific global language JSON on demand.
  Future<void> downloadGlobalJson(String language) async {
    final url = _globalJsonUrls[language];
    if (url == null) throw AssetDownloadException('Unknown language: $language');

    final dir = await _getAssetDir();
    final gzPath  = '${dir.path}/${language}_kinship.json.gz';
    final outPath = '${dir.path}/${language}_kinship.json';

    await _dio.download(url, gzPath);
    final inputBytes = await File(gzPath).readAsBytes();
    await File(outPath).writeAsBytes(gzip.decode(inputBytes));
    if (File(gzPath).existsSync()) await File(gzPath).delete();
  }

  /// Check if a global language JSON is downloaded.
  Future<bool> isGlobalJsonReady(String language) async {
    final dir = await _getAssetDir();
    return File('${dir.path}/${language}_kinship.json').existsSync();
  }

  /// Get path to a downloaded global JSON.
  Future<String?> getGlobalJsonPath(String language) async {
    final dir = await _getAssetDir();
    final path = '${dir.path}/${language}_kinship.json';
    return File(path).existsSync() ? path : null;
  }

  /// Delete all downloaded assets (force re-download on next launch).
  Future<void> resetAssets() async {
    final dir = await _getAssetDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  // Legacy stub — SQLite no longer used
  Future<String> getSqlitePath() async => '';

  Future<Directory> _getAssetDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final assetDir = Directory('${appDir.path}/kinrel_assets');
    if (!assetDir.existsSync()) await assetDir.create(recursive: true);
    return assetDir;
  }
}

class AssetDownloadException implements Exception {
  final String message;
  AssetDownloadException(this.message);

  @override
  String toString() => 'AssetDownloadException: $message';
}
