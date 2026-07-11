// lib/features/pulse/presentation/celebrations_screen.dart
//
// DAXELO KINREL — Celebrations Screen
//
// Tabbed screen combining Blessing Chain + Festivals.
// Both are occasion/calendar-triggered content, grouped together
// per the Pulse hub consolidation plan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'festival_screen.dart';
import 'blessing_chain_screen.dart';

class CelebrationsScreen extends ConsumerWidget {
  const CelebrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Celebrations'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Festivals', icon: Icon(Icons.celebration)),
              Tab(text: 'Blessings', icon: Icon(Icons.volunteer_activism)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FestivalScreen(embedded: true),
            BlessingChainScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}
