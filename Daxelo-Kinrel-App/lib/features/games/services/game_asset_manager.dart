// lib/features/games/services/game_asset_manager.dart
//
// Manages on-demand download of game assets (JSON word banks, images, audio)
// from Supabase Storage. NOT code/plugins — only static assets.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

enum GameDownloadStatus { notDownloaded, downloading, downloaded, failed }

class GameDownloadState {
  const GameDownloadState({this.status = GameDownloadStatus.notDownloaded, this.progress = 0.0});
  final GameDownloadStatus status;
  final double progress;
  GameDownloadState copyWith({GameDownloadStatus? status, double? progress}) =>
      GameDownloadState(status: status ?? this.status, progress: progress ?? this.progress);
}

class GameAssetManager {
  static const _prefsKey = 'game_download_status';

  static Future<String> _gameDir(String gameId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/games/$gameId');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static Future<GameDownloadStatus> getStatus(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString('$_prefsKey/$gameId');
    return GameDownloadStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => GameDownloadStatus.notDownloaded,
    );
  }

  static Future<void> setStatus(String gameId, GameDownloadStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsKey/$gameId', status.name);
  }

  static Future<bool> isDownloaded(String gameId) async {
    return await getStatus(gameId) == GameDownloadStatus.downloaded;
  }

  /// Download game assets from Supabase Storage.
  /// For Ghost Painter v1: downloads a prompt word bank JSON.
  static Future<void> download(String gameId, WidgetRef ref) async {
    await setStatus(gameId, GameDownloadStatus.downloading);
    try {
      final client = ref.read(supabaseProvider);
      if (client == null) {
        await setStatus(gameId, GameDownloadStatus.failed);
        return;
      }
      final dir = await _gameDir(gameId);
      // Download manifest
      final manifestResp = await client.storage.from('game-assets').download('$gameId/manifest.json');
      final manifest = jsonDecode(String.fromCharCodes(manifestResp)) as Map<String, dynamic>;
      final assets = manifest['assets'] as List? ?? [];
      for (int i = 0; i < assets.length; i++) {
        final assetPath = assets[i] as String;
        final bytes = await client.storage.from('game-assets').download('$gameId/$assetPath');
        final file = File('$dir/$assetPath');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      }
      await setStatus(gameId, GameDownloadStatus.downloaded);
    } catch (e) {
      debugPrint('⚠️ GameAssetManager download error: $e');
      await setStatus(gameId, GameDownloadStatus.failed);
    }
  }

  /// Load a downloaded asset file
  static Future<String?> loadAsset(String gameId, String assetPath) async {
    try {
      final dir = await _gameDir(gameId);
      final file = File('$dir/$assetPath');
      if (!file.existsSync()) return null;
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }
}

/// Riverpod provider for watching a game's download status
final gameDownloadStatusProvider =
    StateNotifierProvider.autoDispose.family<GameDownloadNotifier, GameDownloadState, String>(
  (ref, gameId) => GameDownloadNotifier(ref, gameId),
);

class GameDownloadNotifier extends StateNotifier<GameDownloadState> {
  GameDownloadNotifier(this._ref, this.gameId) : super(const GameDownloadState());
  final WidgetRef _ref;
  final String gameId;

  Future<void> checkStatus() async {
    final status = await GameAssetManager.getStatus(gameId);
    state = GameDownloadState(status: status, progress: status == GameDownloadStatus.downloaded ? 1.0 : 0.0);
  }

  Future<void> download() async {
    state = state.copyWith(status: GameDownloadStatus.downloading, progress: 0.1);
    await GameAssetManager.download(gameId, _ref);
    await checkStatus();
  }
}
