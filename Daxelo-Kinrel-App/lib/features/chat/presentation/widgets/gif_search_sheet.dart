// lib/features/chat/presentation/widgets/gif_search_sheet.dart
//
// DAXELO KINREL — GIF Search Sheet (Tier 2 chat feature)
//
// A modal bottom sheet for searching GIFs via the Giphy public API.
// Reached from a "GIF" button in the sticker panel.
//
// Flow:
//   1. User opens the sheet → trending GIFs load.
//   2. User types a search query → debounced Giphy API call returns
//      matching GIFs.
//   3. User taps a GIF → onGifSelected callback fires with the GIF's
//      URL + preview URL. The caller inserts a MessageType.gif
//      ChatMessage with the GIF URL as the content (or mediaUrl).
//
// Uses the Giphy public beta API key. For production, the app should
// ship its own Giphy API key (created at developers.giphy.com) — the
// public beta key is rate-limited and not for production. The key is
// passed as a constant so it can be easily swapped via --dart-define
// or a .env var.
//
// No new pubspec dependency — uses `dio` (already in pubspec) + the
// CachedNetworkImage widget (already in pubspec) for the grid.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

/// A single GIF result from the Giphy search API.
class GifResult {
  const GifResult({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
    required this.title,
  });

  /// Giphy GIF id (for de-dup / future "favorite" features).
  final String id;

  /// Low-res preview URL (used in the grid).
  final String previewUrl;

  /// High-res URL (sent in the chat message).
  final String fullUrl;

  /// Giphy's title (displayed on long-press).
  final String title;
}

/// Callback type for "user selected a GIF".
typedef GifSelectedCallback = void Function(GifResult gif);

class GifSearchSheet extends StatefulWidget {
  const GifSearchSheet({super.key, required this.onGifSelected});

  final GifSelectedCallback onGifSelected;

  /// Opens the sheet. The [onGifSelected] callback fires when the
  /// user picks a GIF — the caller is responsible for inserting the
  /// MessageType.gif ChatMessage.
  static Future<void> show(
    BuildContext context, {
    required GifSelectedCallback onGifSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: GifSearchSheet(onGifSelected: onGifSelected),
      ),
    );
  }

  @override
  State<GifSearchSheet> createState() => _GifSearchSheetState();
}

class _GifSearchSheetState extends State<GifSearchSheet> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<GifResult> _results = [];
  bool _isLoading = false;
  String? _error;
  bool _isTrending = true;

  // Giphy public beta API key — for development / testing. Replace
  // with the app's own key (developers.giphy.com) for production. The
  // key is intentionally hardcoded here so the feature works out of
  // the box; a future task should move it to app_config.
  static const _giphyApiKey = 'dc6zaTOxFJmzC';
  static const _giphyBase = 'https://api.giphy.com/v1/gifs';

  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isTrending = true;
    });
    try {
      final response = await _dio.get('$_giphyBase/trending', queryParameters: {
        'api_key': _giphyApiKey,
        'limit': 24,
        'rating': 'pg',
      });
      final data = response.data['data'] as List;
      if (mounted) {
        setState(() {
          _results = data.map(_parseGif).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load GIFs: $e';
        });
      }
    }
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _loadTrending();
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _isTrending = false;
    });
    try {
      final response = await _dio.get('$_giphyBase/search', queryParameters: {
        'api_key': _giphyApiKey,
        'q': trimmed,
        'limit': 24,
        'rating': 'pg',
      });
      final data = response.data['data'] as List;
      if (mounted) {
        setState(() {
          _results = data.map(_parseGif).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Search failed: $e';
        });
      }
    }
  }

  GifResult _parseGif(dynamic raw) {
    final gif = raw as Map<String, dynamic>;
    final images = gif['images'] as Map<String, dynamic>;
    // preview = fixed_height_small (low-res, fast load)
    final preview = (images['fixed_height_small'] ??
        images['fixed_height']) as Map<String, dynamic>;
    // full = original (high-res, sent in the message)
    final full = images['original'] as Map<String, dynamic>;
    return GifResult(
      id: gif['id'] as String? ?? '',
      previewUrl: preview['url'] as String? ?? '',
      fullUrl: full['url'] as String? ?? '',
      title: gif['title'] as String? ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                decoration: BoxDecoration(
                  color: KinrelColors.textDim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.gif_box_rounded,
                      size: 22, color: KinrelColors.ember),
                  const SizedBox(width: 10),
                  Text(
                    'GIFs',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (v) {
                  // Simple debounce via a Future.delayed — fine for v1.
                  // A Timer-based debounce would be more efficient.
                  Future.delayed(const Duration(milliseconds: 400), () {
                    if (_searchController.text == v) _search(v);
                  });
                },
                onSubmitted: _search,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                ),
                decoration: InputDecoration(
                  hintText: 'Search GIFs…',
                  hintStyle: TextStyle(
                      color: KinrelColors.textDim.withValues(alpha: 0.7)),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 20, color: KinrelColors.textDim),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: KinrelColors.textDim),
                          onPressed: () {
                            _searchController.clear();
                            _loadTrending();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF11132A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            // Body: GIF grid
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.ember),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: KinrelColors.error),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _isTrending ? _loadTrending() : _search(_searchController.text),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.gif_box_outlined,
                  size: 40, color: KinrelColors.textDim),
              const SizedBox(height: 10),
              Text(
                _isTrending
                    ? 'No trending GIFs right now'
                    : 'No GIFs found for "${_searchController.text}"',
                textAlign: TextAlign.center,
                style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) => _gifTile(_results[index]),
    );
  }

  Widget _gifTile(GifResult gif) {
    return GestureDetector(
      onTap: () {
        widget.onGifSelected(gif);
        Navigator.of(context).pop();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: gif.previewUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: const Color(0xFF11132A),
          ),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFF11132A),
            child: Icon(Icons.broken_image_outlined,
                color: KinrelColors.textDim, size: 24),
          ),
        ),
      ),
    );
  }
}
