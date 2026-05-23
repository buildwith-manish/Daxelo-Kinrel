import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../kinship/kinship_provider.dart';
import 'graph_service.dart';

final graphServiceProvider = Provider<GraphService>((ref) {
  final kinshipService = ref.watch(kinshipServiceProvider);
  return GraphService(kinshipService);
});
