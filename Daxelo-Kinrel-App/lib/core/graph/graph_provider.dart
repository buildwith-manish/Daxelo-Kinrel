import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../kinship/kinship_provider.dart';
import 'graph_service.dart';

/// Provider for the GraphService singleton.
/// Uses the KinshipService for kinship term resolution and composition.
final graphServiceProvider = Provider<GraphService>((ref) {
  final kinshipService = ref.watch(kinshipServiceProvider);
  return GraphService(kinshipService);
});
