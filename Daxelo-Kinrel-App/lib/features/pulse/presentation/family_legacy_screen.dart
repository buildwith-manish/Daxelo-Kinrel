// lib/features/pulse/presentation/family_legacy_screen.dart
//
// DAXELO KINREL — Family Legacy Screen
//
// Tabbed screen combining Memorials + Family Chronicle.
// Both are "preserve/look back at family history" features,
// grouped together per the Pulse hub consolidation plan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'memorials_screen.dart';
import 'family_chronicle_screen.dart';

class FamilyLegacyScreen extends ConsumerWidget {
  const FamilyLegacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Family Legacy'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Memorials', icon: Icon(Icons.auto_awesome)),
              Tab(text: 'Chronicle', icon: Icon(Icons.menu_book)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            MemorialsScreen(embedded: true),
            FamilyChronicleScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}
