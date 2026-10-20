// lib/features/family/presentation/widgets/kinship_language_selector.dart
//
// DAXELO KINREL — Kinship Language Selector (2026-10-20)
//
// A small tappable pill (~32dp tall) showing the current kinship term
// language short name. Tap opens a bottom sheet with searchable list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/kinship/kinship_term_language_provider.dart';
import '../../../../core/kinship/language_code_map.dart';

class KinshipLanguageSelector extends ConsumerWidget {
  const KinshipLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langPref = ref.watch(kinshipTermLanguageProvider);
    final label = langPref == 'auto' ? 'Auto' : langPref.toUpperCase();
    final fg = Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;

    return SizedBox(
      height: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showSheet(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: fg.withValues(alpha: 0.7)),
            ]),
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F1318),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => const _LanguageSheet(),
    );
  }
}

class _LanguageSheet extends ConsumerStatefulWidget {
  const _LanguageSheet();
  @override
  ConsumerState<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends ConsumerState<_LanguageSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cur = ref.watch(kinshipTermLanguageProvider);
    final showEn = ref.watch(showEnglishSubtitleProvider);
    final filtered = languageCodeToName.entries.where((e) {
      if (_q.isEmpty) return true;
      final q = _q.toLowerCase();
      return e.key.toLowerCase().contains(q) || e.value.toLowerCase().contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Kinship Term Language', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl, onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search language...', hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
              filled: true, fillColor: const Color(0xFF1A1F2B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Expanded(child: Text('Show English underneath', style: TextStyle(color: Colors.white70, fontSize: 14))),
            // ignore: deprecated_member_use
            Switch(value: showEn, onChanged: (v) => ref.read(showEnglishSubtitleProvider.notifier).set(v), activeColor: const Color(0xFFE8863A)),
          ]),
        ),
        const Divider(color: Color(0xFF2A3040), height: 1),
        Flexible(child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 8), children: [
          // ignore: deprecated_member_use
          RadioListTile<String>(value: 'auto', groupValue: cur,
            title: const Text('Auto (follow app language)', style: TextStyle(color: Colors.white, fontSize: 14)),
            activeColor: const Color(0xFFE8863A),
            // ignore: deprecated_member_use
            onChanged: (v) { if (v != null) { ref.read(kinshipTermLanguageProvider.notifier).set(v); Navigator.of(context).pop(); } },
          ),
          const Divider(color: Color(0xFF2A3040), height: 1, indent: 16, endIndent: 16),
          ...filtered.map((e) => RadioListTile<String>(
            // ignore: deprecated_member_use
            value: e.key, groupValue: cur,
            title: Text(e.value[0].toUpperCase() + e.value.substring(1), style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: e.key == cur ? FontWeight.w600 : FontWeight.w400)),
            subtitle: Text(e.key.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 12)),
            activeColor: const Color(0xFFE8863A),
            // ignore: deprecated_member_use
            onChanged: (v) { if (v != null) { ref.read(kinshipTermLanguageProvider.notifier).set(v); Navigator.of(context).pop(); } },
          )),
        ])),
        const SizedBox(height: 16),
      ]),
    );
  }
}
