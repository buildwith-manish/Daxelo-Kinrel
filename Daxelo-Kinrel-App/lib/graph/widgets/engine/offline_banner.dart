// lib/graph/widgets/engine/offline_banner.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter/material.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Offline. Showing cached graph.',
      liveRegion: true,
      child: Material(
        color: Colors.orange.shade800,
        child: const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Offline — showing cached graph',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
