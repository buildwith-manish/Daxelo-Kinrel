// lib/features/chat/presentation/widgets/sticker_pack_sheet.dart
//
// DAXELO KINREL — Sticker Pack Sheet (Tier 3 chat feature)
//
// A modal bottom sheet for searching + sending Giphy stickers
// (transparent-background animated stickers). Reached from a
// "Stickers" button in the chat input bar (next to the emoji button).
//
// Flow:
//   1. User opens the sheet → trending stickers load.
//   2. User types a search query → debounced Giphy API call returns
//      matching stickers.
//   3. User taps a sticker → onStickerSelected callback fires with
//      the sticker URL. The caller inserts a MessageType.gif
//      ChatMessage (stickers are transparent GIFs — same rendering).
//
// Uses the Giphy public beta API (same as GifSearchSheet) with the
// /v1/gifs/trending and /v1/stickers/search endpoints.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

typedef StickerSelectedCallback = void Function(String stickerUrl, String title);

class StickerPackSheet extends StatefulWidget {
  const StickerPackSheet({super.key, required this.onStickerSelected});

  final StickerSelectedCallback onStickerSelected;

  static Future<void> show(
    BuildContext context, {
    required StickerSelectedCallback onStickerSelected,
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
        child: StickerPackSheet(onStickerSelected: onStickerSelected),
      ),
    );
  }

  @override
  State<StickerPackSheet> createState() => _StickerPackSheetState();
}

class _StickerPackSheetState extends State<StickerPackSheet> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  List<_StickerResult> _results = [];
  bool _isLoading = false;
  String? _error;
  bool _isTrending = true;

  static const _giphyApiKey = 'dc6zaTOxFJmzC';
  static const _giphyBase = 'https://api.giphy.com/v1';
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
      // Giphy stickers trending endpoint
      final response =
          await _dio.get('$_giphyBase/stickers/trending', queryParameters: {
        'api_key': _giphyApiKey,
        'limit': 32,
        'rating': 'g',
      });
      final data = response.data['data'] as List;
      if (mounted) {
        setState(() {
          _results = data.map(_parseSticker).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load stickers: $e';
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
      final response =
          await _dio.get('$_giphyBase/stickers/search', queryParameters: {
        'api_key': _giphyApiKey,
        'q': trimmed,
        'limit': 32,
        'rating': 'g',
      });
      final data = response.data['data'] as List;
      if (mounted) {
        setState(() {
          _results = data.map(_parseSticker).toList();
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

  _StickerResult _parseSticker(dynamic raw) {
    final sticker = raw as Map<String, dynamic>;
    final images = sticker['images'] as Map<String, dynamic>;
    // Use fixed_height_small for the grid preview
    final preview =
        (images['fixed_height_small'] ?? images['fixed_height']) as Map<String, dynamic>;
    // Use original for the sent message
    final full = images['original'] as Map<String, dynamic>;
    return _StickerResult(
      id: sticker['id'] as String? ?? '',
      previewUrl: preview['url'] as String? ?? '',
      fullUrl: full['url'] as String? ?? '',
      title: sticker['title'] as String? ?? '',
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
                  Icon(Icons.emoji_emotions_rounded,
                      size: 22, color: KinrelColors.ember),
                  const SizedBox(width: 10),
                  Text(
                    'Stickers',
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
                  hintText: 'Search stickers…',
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
            // Body: sticker grid
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
                onPressed: () =>
                    _isTrending ? _loadTrending() : _search(_searchController.text),
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
              Icon(Icons.emoji_emotions_outlined,
                  size: 40, color: KinrelColors.textDim),
              const SizedBox(height: 10),
              Text(
                _isTrending
                    ? 'No trending stickers right now'
                    : 'No stickers found for "${_searchController.text}"',
                textAlign: TextAlign.center,
                style: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    // 4-column grid (stickers are square + smaller than GIFs)
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) => _stickerTile(_results[index]),
    );
  }

  Widget _stickerTile(_StickerResult sticker) {
    return GestureDetector(
      onTap: () {
        widget.onStickerSelected(
          sticker.fullUrl,
          sticker.title.isNotEmpty ? sticker.title : 'Sticker',
        );
        Navigator.of(context).pop();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: const Color(0xFF11132A),
          child: CachedNetworkImage(
            imageUrl: sticker.previewUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => Container(
              color: const Color(0xFF11132A),
            ),
            errorWidget: (_, __, ___) => Container(
              color: const Color(0xFF11132A),
              child: Icon(Icons.broken_image_outlined,
                  color: KinrelColors.textDim, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerResult {
  const _StickerResult({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
    required this.title,
  });

  final String id;
  final String previewUrl;
  final String fullUrl;
  final String title;
}
