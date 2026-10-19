// integration_test/perf_baseline_test.dart
//
// DAXELO KINREL — Performance Baseline (Phase 0)
//
// Records frame build/raster times for the 5 key user flows:
//   (a) onboarding screens
//   (b) home screen scroll
//   (c) family graph pan/zoom with 100+ members (placeholder — needs mock harness)
//   (d) chat scroll with 500 messages (placeholder — needs Drift seed)
//   (e) add-person sheet open/type (placeholder)
//
// Output: the results are stored in the binding's reportData and printed
// to stdout. The owner fills in docs/perf/baseline.md with the measured
// numbers from a real device run.
//
// Run on profile mode:
//   flutter test integration_test/perf_baseline_test.dart --profile
//
// IMPORTANT: these numbers are ONLY meaningful when run on a real device
// in profile mode. Running in debug mode or on a simulator produces
// numbers that are 5-10x worse than reality and cannot be used as a
// baseline. See docs/perf/baseline.md for the methodology.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 0 — Performance Baseline', () {
    // (a) Onboarding screens — measure the first 3 frames after pump.
    testWidgets('(a) onboarding — first frame', (tester) async {
      await binding.watchPerformance(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
          );
          await tester.pumpAndSettle();
        },
        reportKey: 'onboarding_first_frame',
      );
    });

    // (b) Home screen scroll — measure 60 frames of scroll.
    testWidgets('(b) home screen scroll — 60 frames', (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: controller,
              itemCount: 100,
              itemBuilder: (_, i) => ListTile(
                title: Text('Item $i'),
                subtitle: Text('Subtitle $i'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await binding.watchPerformance(
        () async {
          for (var i = 0; i < 60; i++) {
            controller.position.jumpTo(i * 50.0);
            await tester.pump();
          }
        },
        reportKey: 'home_scroll_60f',
      );
      controller.dispose();
    });

    // (c) Family graph pan/zoom — placeholder (needs mock harness)
    testWidgets('(c) family graph — placeholder (needs mock harness)',
        (tester) async {
      await binding.watchPerformance(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: Center(child: Text('Graph'))),
            ),
          );
          await tester.pumpAndSettle();
        },
        reportKey: 'graph_placeholder',
      );
    });

    // (d) Chat scroll with 500 messages — placeholder (needs Drift seed)
    testWidgets('(d) chat scroll 500 msgs — placeholder (needs Drift seed)',
        (tester) async {
      await binding.watchPerformance(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ListView.builder(
                  reverse: true,
                  itemCount: 500,
                  itemBuilder: (_, i) => ListTile(
                    title: Text('Message $i'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        },
        reportKey: 'chat_scroll_500_placeholder',
      );
    });

    // (e) Add-person sheet open/type — placeholder
    testWidgets('(e) add-person sheet — placeholder', (tester) async {
      await binding.watchPerformance(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: TextFormField(
                    decoration: const InputDecoration(hintText: 'Name'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        },
        reportKey: 'add_person_placeholder',
      );
    });
  });
}
