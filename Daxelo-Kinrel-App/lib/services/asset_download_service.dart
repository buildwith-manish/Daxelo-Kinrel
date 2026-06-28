// lib/services/asset_download_service.dart
//
// DAXELO KINREL — Asset Download Service
//
// Downloads kinship JSON data files from GitHub Releases.
// The primary file is indian_kinship.json.gz (~3 MB compressed).
// Global kinship JSONs are downloaded on demand by language.
//
// The app bundles a tiny kinship_core.json (~388 KB) in the APK for
// instant offline access. The full JSON is downloaded in the background
// on first launch to unlock all 5363 relationships.

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Progress update emitted during download.
class DownloadProgress {
  final String currentFile;
  final double progress; // 0.0 to 1.0
  final String message;
  final int bytesDownloaded;
  final int? totalBytes;

  const DownloadProgress({
    required this.currentFile,
    required this.progress,
    required this.message,
    required this.bytesDownloaded,
    this.totalBytes,
  });
}

/// Handles downloading and caching kinship JSON data files.
class AssetDownloadService {
  static const String releaseBaseUrl =
      'https://github.com/buildwith-manish/Daxelo-Kinrel/releases/download/v1.0.0-assets';

  /// Primary Indian kinship JSON (v5.0.0, 5363 entries)
  static const String indianJsonUrl = '$releaseBaseUrl/indian_kinship.json.gz';

  /// Global kinship JSONs — downloaded on demand by language
  static const Map<String, String> globalJsonUrls = {
    'arabic': '$releaseBaseUrl/arabic_kinship_production.json.gz',
    'korean': '$releaseBaseUrl/korean_kinship_production.json.gz',
    'japanese': '$releaseBaseUrl/japanese_kinship_production.json.gz',
    'russian': '$releaseBaseUrl/russian_kinship_production_v2.json.gz',
    'vietnamese': '$releaseBaseUrl/vietnamese_kinship_production_v2.json.gz',
    'chinese': '$releaseBaseUrl/chinese_kinship_production.json.gz',
  };

  static const String indianJsonFileName = 'indian_kinship.json';
  static const String indianJsonGzFileName = 'indian_kinship.json.gz';
  static const String _versionMarker = 'asset_version_1_0_0.txt';
  static const String _currentVersion = '1.0.0';

  final Dio _dio;

  AssetDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  /// Check if the Indian kinship JSON is already downloaded.
  Future<bool> isIndianJsonReady() async {
    try {
      final path = await getIndianJsonPath();
      final file = File(path);
      if (!file.existsSync()) return false;
      final size = await file.length();
      return size > 1024 * 1024; // > 1 MB
    } catch (_) {
      return false;
    }
  }

  /// Download indian_kinship.json.gz, decompress, and save locally.
  /// Returns a stream of download progress (0.0 to 1.0).
  Stream<DownloadProgress> downloadIndianJson() async* {
    final dir = await _getAssetDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      throw AssetDownloadException(
        'No internet connection. Please connect to download kinship data.',
      );
    }

    final gzPath = '${dir.path}/$indianJsonGzFileName';
    final outPath = '${dir.path}/$indianJsonFileName';

    // Delete existing file if present
    final outFile = File(outPath);
    if (outFile.existsSync()) {
      await outFile.delete();
    }

    yield DownloadProgress(
      currentFile: 'indian',
      progress: 0.0,
      message: 'Downloading kinship data...',
      bytesDownloaded: 0,
      totalBytes: 0,
    );

    // Download
    await _dio.download(
      indianJsonUrl,
      gzPath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          _progressController.add(DownloadProgress(
            currentFile: 'indian',
            progress: received / total,
            message: 'Downloading kinship data...',
            bytesDownloaded: received,
            totalBytes: total,
          ));
        }
      },
    );

    // Decompress
    _progressController.add(const DownloadProgress(
      currentFile: 'indian',
      progress: 1.0,
      message: 'Extracting kinship data...',
      bytesDownloaded: 0,
      totalBytes: 0,
    ));

    await _decompressGzip(gzPath, outPath);

    // Delete .gz file
    final gzFile = File(gzPath);
    if (gzFile.existsSync()) {
      await gzFile.delete();
    }

    // Write version marker
    final versionFile = File('${dir.path}/$_versionMarker');
    await versionFile.writeAsString(_currentVersion);
  }

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  /// Get local path of downloaded indian_kinship.json.
  Future<String> getIndianJsonPath() async {
    final dir = await _getAssetDir();
    return '${dir.path}/$indianJsonFileName';
  }

  /// Download a specific global language JSON on demand.
  Future<void> downloadGlobalJson(String language) async {
    final url = globalJsonUrls[language];
    if (url == null) {
      throw AssetDownloadException('Unknown language: $language');
    }

    final dir = await _getAssetDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final gzPath = '${dir.path}/${language}_kinship.json.gz';
    final outPath = '${dir.path}/${language}_kinship.json';

    await _dio.download(url, gzPath);
    await _decompressGzip(gzPath, outPath);

    final gzFile = File(gzPath);
    if (gzFile.existsSync()) {
      await gzFile.delete();
    }
  }

  /// Check if a specific global JSON is downloaded.
  Future<bool> isGlobalJsonReady(String language) async {
    try {
      final dir = await _getAssetDir();
      final file = File('${dir.path}/${language}_kinship.json');
      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Get path to a downloaded global JSON.
  Future<String> getGlobalJsonPath(String language) async {
    final dir = await _getAssetDir();
    return '${dir.path}/${language}_kinship.json';
  }

  /// Delete all downloaded assets.
  Future<void> resetAssets() async {
    final dir = await _getAssetDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _decompressGzip(String gzPath, String outPath) async {
    final inputBytes = await File(gzPath).readAsBytes();
    final decompressedBytes = gzip.decode(inputBytes);
    await File(outPath).writeAsBytes(decompressedBytes);
  }

  Future<Directory> _getAssetDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final assetDir = Directory('${appDir.path}/kinrel_assets');
    if (!assetDir.existsSync()) {
      await assetDir.create(recursive: true);
    }
    return assetDir;
  }
}

class AssetDownloadException implements Exception {
  final String message;
  AssetDownloadException(this.message);

  @override
  String toString() => 'AssetDownloadException: $message';
}
