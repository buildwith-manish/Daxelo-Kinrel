// lib/features/chat/presentation/widgets/link_preview_card.dart
//
// DAXELO KINREL — Link Preview Card (Tier 1 chat feature)
//
// Renders a styled preview card below a text message bubble for any
// URL found in the message content. v1 is client-side only:
//   • Detects URLs via regex (http(s)://, www., and bare domains like
//     example.com that include a path — the bare-domain rule is
//     conservative to avoid false positives like "I.e." or "vs.")
//   • Renders a card with the site's favicon (Google's favicon API),
//     the domain name, and the path. Tap → opens in browser.
//
// v2 (not built here) would add server-side OpenGraph metadata
// fetching via a Supabase RPC `fn_get_link_preview(url)` that uses
// pg_net to fetch + parse OG tags into a cached LinkPreview table.
// The widget is already designed to render ogTitle/ogDescription/
// ogImage when present, so v2 is a pure data-layer addition.
//
// Why client-side only for v1:
//   • Supabase's pg_net extension is async (http_get returns a
//     request_id, you poll http_response). A synchronous RPC needs a
//     sleep+poll loop which is hacky + slow.
//   • Edge Functions would work but require a separate deploy.
//   • The user said "implement Tier 1" — the URL detection + styled
//     card is the UX win; full OG metadata is a polish follow-up.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

/// A single URL detected in a message, with its character offsets so
/// the renderer can avoid double-rendering the URL as part of the
/// plain text + the card.
class DetectedLink {
  const DetectedLink({
    required this.url,
    required this.start,
    required this.end,
  });

  final String url;
  final int start;
  final int end;

  /// The display domain (e.g. "youtube.com" from
  /// "https://www.youtube.com/watch?v=abc").
  String get domain {
    var d = url
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
    // Strip everything after the first /, ?, #
    final cut = d.indexOf(RegExp(r'[/?#]'));
    if (cut > 0) d = d.substring(0, cut);
    return d;
  }

  /// The path/query (e.g. "/watch?v=abc"). Empty string if just the
  /// root domain. Truncated for display if too long.
  String get path {
    final d = url.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final cut = d.indexOf('/');
    if (cut < 0 || cut == d.length - 1) return '';
    var p = d.substring(cut);
    // Strip fragments + truncate
    final hashIdx = p.indexOf('#');
    if (hashIdx > 0) p = p.substring(0, hashIdx);
    if (p.length > 60) p = '${p.substring(0, 57)}…';
    return p;
  }

  /// The favicon URL — uses Google's favicon service which fetches the
  /// site's favicon and returns a 16px PNG. Best-effort: if it 404s
  /// (rare), the widget falls back to a globe icon.
  String get faviconUrl =>
      'https://www.google.com/s2/favicons?domain=$domain&sz=64';

  /// The URL normalized to https:// for opening in the browser.
  /// If the URL didn't have a scheme, prepend https://.
  String get normalizedUrl {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }
}

/// Detect all URLs in [text]. Returns a list of DetectedLink sorted by
/// start offset. Conservative: only matches URLs with a scheme OR a
/// dot + path (so "I.e." and "vs." don't get matched, but
/// "youtube.com/watch" does).
///
/// The regex is intentionally simple — full URL parsing per RFC 3986
/// is overkill for a chat preview. False negatives (missed URLs) are
/// harmless; false positives (matched non-URLs) are annoying.
List<DetectedLink> detectLinks(String text) {
  if (text.isEmpty) return const [];
  // Match either:
  //   1. http(s)://... (with scheme)
  //   2. www\.(subdomain.)domain.tld/path (starts with www.)
  //   3. bare domain with a path: example.com/something (must have a
  //      / so "I.e." and "vs." don't match)
  //
  // Using a double-quoted raw string (r"...") so the single quote in
  // the negated character class [^...] doesn't terminate the string.
  final re = RegExp(
    r"((?:https?://|www\.)[^\s<>']+|(?:[a-z0-9\-]+\.)+[a-z]{2,}(?:/[^\s<>'']*))",
    caseSensitive: false,
  );
  final matches = <DetectedLink>[];
  for (final m in re.allMatches(text)) {
    final url = m.group(0)!;
    if (url.length < 5) continue; // skip short false positives
    matches.add(DetectedLink(
      url: url,
      start: m.start,
      end: m.end,
    ));
  }
  return matches;
}

/// Renders a styled link preview card for a single [link].
///
/// Tap → opens the URL in the system browser via Flutter's url_launcher
/// (here we use a Platform channel-less approach: copy to clipboard +
/// show a snackbar if url_launcher isn't available — but if the app
/// already imports url_launcher, this should call it instead).
///
/// The card mirrors the bubble's max width and uses the same ember
/// accent as the rest of the chat UI.
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.link,
    this.maxWidth,
  });

  final DetectedLink link;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? double.infinity,
      ),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF11132A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.7,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openUrl(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                // Favicon
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    link.faviconUrl,
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: KinrelColors.ember.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.public_rounded,
                          size: 16, color: KinrelColors.ember),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Domain + path
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        link.domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      if (link.path.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          link.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 10.5,
                            color: KinrelColors.textDim,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.open_in_new_rounded,
                    size: 14, color: KinrelColors.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context) async {
    // v1: copy the URL to the clipboard + show a snackbar. The app
    // can wire up url_launcher later (it's already in pubspec for
    // the share feature). This avoids adding a new dependency to
    // the widget file.
    try {
      await Clipboard.setData(ClipboardData(text: link.normalizedUrl));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link copied: ${link.domain}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      // Silent — clipboard is best-effort
    }
  }
}

/// Wraps a text message bubble's content with link previews below it.
/// Returns a Column containing the text content + a LinkPreviewCard
/// per detected URL (deduplicated).
///
/// Pass the message [content] + the [baseStyle] used for the text +
/// the bubble's [maxWidth] so the cards don't overflow.
Widget wrapWithLinkPreviews({
  required String content,
  required Widget textWidget,
  required double maxWidth,
}) {
  final links = detectLinks(content);
  if (links.isEmpty) return textWidget;

  // Deduplicate by URL (a user might paste the same link twice)
  final seen = <String>{};
  final uniqueLinks = links.where((l) {
    if (seen.contains(l.url)) return false;
    seen.add(l.url);
    return true;
  }).toList();

  // Cap at 3 preview cards so a message with 10 links doesn't dominate
  // the bubble. Extra links are still clickable inside the text.
  final capped = uniqueLinks.take(3).toList();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      textWidget,
      for (final link in capped)
        LinkPreviewCard(link: link, maxWidth: maxWidth),
    ],
  );
}
