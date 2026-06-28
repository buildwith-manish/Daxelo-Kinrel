// lib/services/asset_download_service.dart
//
// DAXELO KINREL — Asset Download Service
//
// Downloads and caches the two large kinship data files from GitHub Releases:
//   1. indian_kinship.json.gz  (~3 MB)  — translations + metadata
//   2. kinship_matrix.db.gz    (~941 MB) — SQLite kinship chain matrix
//
// Both files are decompressed to the app's application documents directory
// and cached across launches. On subsequent launches, no download occurs.

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';

/// Progress update emitted during download.
class DownloadProgress {
  final String currentFile; // 'json' or 'sqlite'
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

  @override
  String toString() =>
      'DownloadProgress($currentFile: ${(progress * 100).toStringAsFixed(1)}%, '
      '$bytesDownloaded/${totalBytes ?? '?'} bytes)';
}

/// Handles downloading and caching both kinship data files.
class AssetDownloadService {
  static const String releaseBaseUrl =
      'https://github.com/buildwith-manish/Daxelo-Kinrel/releases/download/v1.0.0-data';

  static const String sqliteUrl = '$releaseBaseUrl/kinship_matrix.db.gz';
  static const String jsonUrl = '$releaseBaseUrl/indian_kinship.json.gz';

  static const String sqliteFileName = 'kinship_matrix.db';
  static const String jsonFileName = 'indian_kinship.json';
  static const String sqliteGzFileName = 'kinship_matrix.db.gz';
  static const String jsonGzFileName = 'indian_kinship.json.gz';

  // Version marker file — bump this when releasing new data to force re-download.
  static const String _versionMarker = 'asset_version_1_0_0.txt';
  static const String _currentVersion = '1.0.0';

  final Dio _dio;

  AssetDownloadService({Dio? dio}) : _dio = dio ?? Dio();

  /// Check if both files already downloaded and valid.
  Future<bool> areAssetsReady() async {
    try {
      final dir = await _getAssetDir();
      final jsonFile = File('${dir.path}/$jsonFileName');
      final dbFile = File('${dir.path}/$sqliteFileName');
      final versionFile = File('${dir.path}/$_versionMarker');

      if (!jsonFile.existsSync() || !dbFile.existsSync()) {
        return false;
      }

      // Check version marker — if version changed, need re-download
      if (!versionFile.existsSync()) {
        return false;
      }
      final version = await versionFile.readAsString();
      if (version.trim() != _currentVersion) {
        return false;
      }

      // Basic size sanity check (JSON should be > 1MB, DB > 100MB)
      final jsonSize = await jsonFile.length();
      final dbSize = await dbFile.length();
      if (jsonSize < 1024 * 1024) return false; // < 1 MB
      if (dbSize < 50 * 1024 * 1024) return false; // < 50 MB

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Download both files with progress updates.
  /// Returns a stream of [DownloadProgress] that completes when both files are ready.
  Stream<DownloadProgress> downloadAssets() async* {
    final dir = await _getAssetDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Check internet connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw AssetDownloadException(
        'No internet connection. Please connect to the internet to download kinship data.',
      );
    }

    // Download JSON first (smaller, faster)
    yield* _downloadFile(
      url: jsonUrl,
      gzPath: '${dir.path}/$jsonGzFileName',
      outPath: '${dir.path}/$jsonFileName',
      fileLabel: 'json',
      message: 'Downloading relationship data...',
    );

    // Download SQLite DB second (larger)
    yield* _downloadFile(
      url: sqliteUrl,
      gzPath: '${dir.path}/$sqliteGzFileName',
      outPath: '${dir.path}/$sqliteFileName',
      fileLabel: 'sqlite',
      message: 'Downloading kinship matrix...',
    );

    // Write version marker
    final versionFile = File('${dir.path}/$_versionMarker');
    await versionFile.writeAsString(_currentVersion);
  }

  Stream<DownloadProgress> _downloadFile({
    required String url,
    required String gzPath,
    required String outPath,
    required String fileLabel,
    required String message,
  }) async* {
    final gzFile = File(gzPath);

    try {
      // Delete existing decompressed file if present
      final outFile = File(outPath);
      if (outFile.existsSync()) {
        await outFile.delete();
      }

      await _dio.download(
        url,
        gzPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            // Emit via the stream controller
            _progressController.add(DownloadProgress(
              currentFile: fileLabel,
              progress: progress,
              message: message,
              bytesDownloaded: received,
              totalBytes: total,
            ));
          }
        },
      );

      // Decompress the gzip file
      yield DownloadProgress(
        currentFile: fileLabel,
        progress: 1.0,
        message: 'Extracting $fileLabel...',
        bytesDownloaded: 0,
        totalBytes: 0,
      );

      await _decompressGzip(gzPath, outPath);

      // Delete the .gz file to save space
      if (gzFile.existsSync()) {
        await gzFile.delete();
      }
    } catch (e) {
      throw AssetDownloadException('Failed to download $fileLabel: $e');
    }
  }

  /// Decompress a .gz file to the output path using `gzip` system command.
  /// On mobile platforms, we use Dart's built-in gzip decompression via
  /// the `dart:io` GZipCodec.
  Future<void> _decompressGzip(String gzPath, String outPath) async {
    final inputBytes = await File(gzPath).readAsBytes();
    final decompressedBytes = gzip.decode(inputBytes);
    await File(outPath).writeAsBytes(decompressedBytes);
  }

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  /// Get path to downloaded SQLite file.
  Future<String> getSqlitePath() async {
    final dir = await _getAssetDir();
    return '${dir.path}/$sqliteFileName';
  }

  /// Get path to downloaded JSON file.
  Future<String> getJsonPath() async {
    final dir = await _getAssetDir();
    return '${dir.path}/$jsonFileName';
  }

  /// Verify file integrity by checking file sizes are non-trivial.
  Future<bool> verifyFiles() async {
    try {
      final jsonPath = await getJsonPath();
      final dbPath = await getSqlitePath();

      final jsonFile = File(jsonPath);
      final dbFile = File(dbPath);

      if (!jsonFile.existsSync() || !dbFile.existsSync()) {
        return false;
      }

      final jsonSize = await jsonFile.length();
      final dbSize = await dbFile.length();

      // JSON should be > 10 MB (uncompressed ~53 MB)
      // DB should be > 500 MB (uncompressed ~8 GB, but VACUUM'd would be ~300-400 MB)
      // We accept anything > 50 MB for the DB to be flexible
      return jsonSize > 10 * 1024 * 1024 && dbSize > 50 * 1024 * 1024;
    } catch (_) {
      return false;
    }
  }

  /// Delete all downloaded assets and version marker.
  Future<void> resetAssets() async {
    final dir = await _getAssetDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
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
