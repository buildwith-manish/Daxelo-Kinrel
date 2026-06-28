// lib/widgets/asset_setup_screen.dart
//
// DAXELO KINREL — Asset Setup Screen
//
// Shown on first launch while downloading kinship data files.
// Displays download progress, handles errors, and offers a "basic mode"
// fallback that uses the math engine without downloaded files.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/asset_download_service.dart';
import '../providers/kinship_providers.dart';

class AssetSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const AssetSetupScreen({super.key, this.onComplete});

  @override
  ConsumerState<AssetSetupScreen> createState() => _AssetSetupScreenState();
}

class _AssetSetupScreenState extends ConsumerState<AssetSetupScreen> {
  DownloadProgress? _currentProgress;
  String _statusMessage = 'Preparing...';
  bool _hasError = false;
  String _errorMessage = '';
  bool _isBasicMode = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _hasError = false;
      _statusMessage = 'Checking existing assets...';
    });

    try {
      final downloadService = ref.read(assetDownloadProvider);

      // Check if already downloaded
      final ready = await downloadService.areAssetsReady();
      if (ready) {
        _statusMessage = 'Assets ready. Initializing...';
        await _initializeResolver();
        widget.onComplete?.call();
        return;
      }

      // Start download
      setState(() {
        _statusMessage = 'Starting download...';
      });

      await for (final progress in downloadService.downloadAssetsWithProgress()) {
        setState(() {
          _currentProgress = progress;
          _statusMessage = progress.message;
        });
      }

      // Initialize resolver with downloaded files
      await _initializeResolver();

      widget.onComplete?.call();
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _initializeResolver() async {
    final downloadService = ref.read(assetDownloadProvider);

    // Get the downloaded JSON path
    final jsonPath = await downloadService.getJsonPath();

    // Reload KinshipService with the full JSON
    // (KinshipService is a singleton accessed via KinshipService.instance)
    // The resolver uses KinshipService internally — no separate init needed.
    // Legacy stubs initializeSqlite/initializeJson are no-ops kept for compat.
    final resolver = ref.read(kinshipResolverProvider);
    await resolver.initializeJson(jsonPath);

    ref.read(kinshipReadyProvider.notifier).state = true;
  }

  Future<void> _continueInBasicMode() async {
    setState(() {
      _isBasicMode = true;
      _statusMessage = 'Running in basic mode (math fallback)...';
    });

    // Initialize only the math fallback (no SQLite, no JSON)
    // The resolver will automatically use the math fallback
    ref.read(kinshipReadyProvider.notifier).state = true;

    widget.onComplete?.call();
  }

  Future<void> _retryDownload() async {
    final downloadService = ref.read(assetDownloadProvider);
    await downloadService.resetAssets();
    await _startDownload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _currentProgress?.progress ?? 0.0;
    final bytesDownloaded = _currentProgress?.bytesDownloaded ?? 0;
    final totalBytes = _currentProgress?.totalBytes ?? 0;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Icon(
                Icons.family_restroom,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Kinrel',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                'Setting up kinship intelligence...',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),

              if (_hasError) ...[
                // Error state
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Download Failed',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilledButton.icon(
                      onPressed: _retryDownload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _continueInBasicMode,
                      icon: const Icon(Icons.offline_bolt),
                      label: const Text('Basic Mode'),
                    ),
                  ],
                ),
              ] else if (_isBasicMode) ...[
                // Basic mode active
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ] else ...[
                // Download progress
                LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 16),

                // Progress percentage
                Text(
                  progress > 0
                      ? '${(progress * 100).toStringAsFixed(1)}%'
                      : 'Connecting...',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Current file
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),

                // File size info
                if (totalBytes > 0)
                  Text(
                    '${_formatBytes(bytesDownloaded)} / ${_formatBytes(totalBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                const SizedBox(height: 32),

                // Note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This happens only once. Future launches will be instant.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // Cancel / basic mode link (only during download, not error)
              if (!_hasError && !_isBasicMode)
                TextButton(
                  onPressed: _continueInBasicMode,
                  child: Text(
                    'Continue in basic mode (offline)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
