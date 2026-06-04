/// Data class for offline write operations that need to be synced later.
/// When the device is offline, write operations are stored here and
/// retried automatically when connectivity is restored.
class PendingOperation {
  int? isarId;

  /// Operation type: 'create', 'update', 'delete'
  late String operationType;

  /// Target collection: 'family', 'person', 'relationship', 'profile'
  late String collection;

  /// Target record ID (for updates and deletes)
  String? recordId;

  /// JSON payload for the operation (the data to create/update)
  String? payload;

  /// When this operation was originally attempted
  late String createdAt;

  /// Number of retry attempts so far
  late int retryCount;

  /// Last retry attempt time
  String? lastRetryAt;

  /// Priority: 0 = high (auth/profile), 1 = normal (family data), 2 = low (analytics)
  late int priority;

  /// Whether this operation is currently being processed
  late bool isProcessing;

  /// Create a new pending operation
  static PendingOperation create({
    required String operationType,
    required String collection,
    String? recordId,
    String? payload,
    int priority = 1,
  }) {
    return PendingOperation()
      ..operationType = operationType
      ..collection = collection
      ..recordId = recordId
      ..payload = payload
      ..createdAt = DateTime.now().toIso8601String()
      ..retryCount = 0
      ..lastRetryAt = null
      ..priority = priority
      ..isProcessing = false;
  }

  /// Maximum number of retry attempts before giving up
  static const int maxRetries = 5;
}
