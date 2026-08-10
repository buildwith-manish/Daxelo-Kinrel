// lib/features/chat/presentation/wallpaper_settings_screen.dart
//
// DAXELO KINREL — Wallpaper Settings Screen
//
// A dedicated settings screen for managing chat wallpapers. Shows a
// preview of the current default wallpaper, lets the user set/remove
// the default, and lists all per-chat wallpapers with the ability to
// remove individual ones.
//
// Route: /settings/wallpaper

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../data/chat_wallpaper_provider.dart';
import '../data/wallpaper_picker.dart';

class WallpaperSettingsScreen extends ConsumerWidget {
  const WallpaperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaperMap = ref.watch(chatWallpaperProvider);
    final defaultPath = wallpaperMap['default'];

    // Per-chat wallpapers (exclude 'default').
    final perChatEntries = wallpaperMap.entries
        .where((e) => e.key != 'default' && e.value != null)
        .toList();

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        title: Text(
          'Chat Wallpaper',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: KinrelSpacing.lg),

          // ── Default Wallpaper Preview ────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(KinrelRadius.card),
              child: Container(
                width: double.infinity,
                height: 200,
                child: defaultPath != null
                    ? Image.file(
                        File(defaultPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholderGradient(),
                      )
                    : _buildPlaceholderGradient(),
              ),
            ),
          ),
          // Centred label over the preview
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                'Default Wallpaper',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
          ),

          const SizedBox(height: KinrelSpacing.xl),

          // ── Section: Default ─────────────────────────────────────
          _buildSectionHeader('Default'),
          _buildSectionCard([
            ListTile(
              leading: Icon(
                Icons.photo_library_rounded,
                color: KinrelColors.orange,
              ),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () async {
                final path = await WallpaperPicker.pickFromGallery(context);
                if (path != null) {
                  await ref
                      .read(chatWallpaperProvider.notifier)
                      .setWallpaper('default', path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Default wallpaper set!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            if (defaultPath != null) ...[
              Divider(
                  color: KinrelColors.border, height: 1, indent: 56),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: Text(
                  'Remove Default Wallpaper',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    color: KinrelColors.textWhite,
                  ),
                ),
                onTap: () async {
                  await ref
                      .read(chatWallpaperProvider.notifier)
                      .clearWallpaper('default');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Default wallpaper removed'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ]),

          const SizedBox(height: KinrelSpacing.xl),

          // ── Section: Per-Chat Wallpapers ─────────────────────────
          _buildSectionHeader('Per-Chat Wallpapers'),
          if (perChatEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.xl),
              child: Center(
                child: Text(
                  'No per-chat wallpapers set',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim,
                  ),
                ),
              ),
            )
          else
            _buildSectionCard(
              perChatEntries.map((entry) {
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(entry.value!),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: KinrelColors.darkElevated,
                        child: Icon(Icons.broken_image,
                            color: KinrelColors.textDim, size: 20),
                      ),
                    ),
                  ),
                  title: Text(
                    entry.key,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                    onPressed: () async {
                      await ref
                          .read(chatWallpaperProvider.notifier)
                          .clearWallpaper(entry.key);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Wallpaper removed'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: KinrelSpacing.xxl),
        ],
      ),
    );
  }

  /// Placeholder gradient shown when no default wallpaper is set.
  Widget _buildPlaceholderGradient() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KinrelColors.darkSurface,
            KinrelColors.ember.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.wallpaper_rounded,
          size: 48,
          color: KinrelColors.textWhite.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base, 4, KinrelSpacing.base, 8,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KinrelColors.orange,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.card),
      ),
      child: Column(children: children),
    );
  }
}
