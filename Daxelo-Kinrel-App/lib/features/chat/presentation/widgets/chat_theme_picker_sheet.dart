// lib/features/chat/presentation/widgets/chat_theme_picker_sheet.dart
//
// DAXELO KINREL — Chat Theme Picker (v132)
//
// A bottom sheet that lets users browse the curated catalog of
// [ChatBackgroundTheme]s and apply one to the current chat. Each
// theme is previewed as a small swatch showing its base gradient +
// accent glow, so users can feel the atmosphere before applying.
//
// The sheet also offers:
//   - "Custom Wallpaper" → opens the existing image wallpaper picker
//     (gallery photo) for users who want a personal image instead
//     of a curated theme.
//   - "Remove" → clears the per-chat override, falling back to the
//     global default.
//
// Selected theme is persisted via chatWallpaperProvider as
// "theme:<id>" so the [ChatBackground] widget picks it up on rebuild.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../data/chat_wallpaper_provider.dart';
import 'chat_background_theme.dart';

/// Opens a modal bottom sheet showing the theme catalog.
///
/// [chatId] is the conversation whose theme should be changed.
/// [onPickCustomWallpaper] is called when the user taps "Custom
/// Wallpaper" — the parent should open the existing image picker
/// (WallpaperPicker.pickFromGallery) and save the result via
/// chatWallpaperProvider.setWallpaper.
Future<void> showChatThemePickerSheet(
  BuildContext context, {
  required String chatId,
  required VoidCallback onPickCustomWallpaper,
  required WidgetRef ref,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KinrelColors.darkCard,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(24),
      ),
    ),
    builder: (ctx) => _ChatThemePickerSheet(
      chatId: chatId,
      onPickCustomWallpaper: onPickCustomWallpaper,
      ref: ref,
    ),
  );
}

class _ChatThemePickerSheet extends ConsumerWidget {
  const _ChatThemePickerSheet({
    required this.chatId,
    required this.onPickCustomWallpaper,
    required this.ref,
  });

  final String chatId;
  final VoidCallback onPickCustomWallpaper;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = ref.watch(wallpaperPathProvider(chatId));
    final currentThemeId = ChatBackgroundTheme.isThemeValue(currentPath)
        ? currentPath!.substring('theme:'.length)
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: KinrelColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              'Chat Atmosphere',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a curated atmosphere for this conversation',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12.5,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: 20),

            // Theme grid — 2 columns so each swatch is large enough
            // to read the atmosphere without scrolling forever.
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemCount: ChatBackgroundTheme.allThemes.length,
              itemBuilder: (ctx, index) {
                final theme = ChatBackgroundTheme.allThemes[index];
                final isSelected = theme.id == currentThemeId;
                return _ThemeSwatch(
                  theme: theme,
                  isSelected: isSelected,
                  onTap: () {
                    ref
                        .read(chatWallpaperProvider.notifier)
                        .setWallpaper(chatId, 'theme:${theme.id}');
                    Navigator.pop(context);
                  },
                );
              },
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFF2A2A3D)),
            const SizedBox(height: 12),

            // Custom wallpaper option
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  color: KinrelColors.orange,
                  size: 20,
                ),
              ),
              title: Text(
                'Custom Wallpaper',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              subtitle: Text(
                'Choose a photo from your gallery',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: KinrelColors.textDim,
                size: 20,
              ),
              onTap: () {
                Navigator.pop(context);
                onPickCustomWallpaper();
              },
            ),

            // Remove wallpaper / reset to default
            if (currentPath != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Remove',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
                subtitle: Text(
                  'Reset to default Midnight atmosphere',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
                onTap: () {
                  ref
                      .read(chatWallpaperProvider.notifier)
                      .clearWallpaper(chatId);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A single theme preview swatch. Renders the theme's base gradient +
/// accent glow in a rounded rectangle so the user can feel the
/// atmosphere before applying.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  final ChatBackgroundTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            children: [
              // Base radial gradient — matches ChatBackground layer 1
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: theme.baseColors,
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              // Accent glow — matches ChatBackground layer 2
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: theme.accentAlignment,
                      radius: 0.9,
                      colors: [
                        theme.accentColor.withValues(alpha: 0.30),
                        theme.accentColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              // Label
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      theme.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      theme.description,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 9.5,
                        color: Colors.white.withValues(alpha: 0.6),
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Selected checkmark
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.orange,
                      boxShadow: [
                        BoxShadow(
                          color: KinrelColors.orange.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
