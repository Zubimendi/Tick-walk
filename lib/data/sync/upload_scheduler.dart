library;

/// Pure domain upload scheduler.
/// Invariant: Pure domain logic without Flutter, Drift, or platform imports (Rule 2).
/// Follows Section 8.4:
/// nextUploads(queue, now, inFlight, concurrency = 2, wifiOnly, connection, oneBatchOverride)
/// Returns attachment ops that are ready: pending, next_attempt_at <= now,
/// parents synced, local file present, and permitted by connectivity.

enum NetworkConnectionType {
  wifi,
  cellular,
  ethernet,
  none,
}

enum UploadWaitingReason {
  waitingForWifi,
  offline,
  waitingForParent,
  backoff,
  fileMissing,
  inFlight,
  concurrencyLimit,
}

class UploadCandidate {
  const UploadCandidate({
    required this.outboxSeq,
    required this.attachmentId,
    required this.inspectionId,
    this.itemId,
    required this.localPath,
    required this.fileExists,
    this.nextAttemptAt = 0,
    this.attempts = 0,
  });

  final int outboxSeq;
  final String attachmentId;
  final String inspectionId;
  final String? itemId;
  final String? localPath;
  final bool fileExists;
  final int nextAttemptAt;
  final int attempts;
}

class ScheduleResult {
  const ScheduleResult({
    required this.toUpload,
    required this.waitingReasons,
  });

  final List<UploadCandidate> toUpload;
  final Map<String, UploadWaitingReason> waitingReasons;
}

/// Evaluates candidates in the queue and schedules the next batch of uploads.
ScheduleResult nextUploads({
  required List<UploadCandidate> queue,
  required int now,
  required Set<String> inFlight,
  int concurrency = 2,
  required bool wifiOnly,
  required NetworkConnectionType connection,
  bool oneBatchOverride = false,
  required Set<String> pendingRecordEntityIds,
}) {
  final toUpload = <UploadCandidate>[];
  final waitingReasons = <String, UploadWaitingReason>{};

  final isOffline = connection == NetworkConnectionType.none;
  final isMeteredBlocked = wifiOnly &&
      !oneBatchOverride &&
      connection != NetworkConnectionType.wifi &&
      connection != NetworkConnectionType.ethernet;

  final availableSlots = concurrency - inFlight.length;

  for (final candidate in queue) {
    final id = candidate.attachmentId;

    if (inFlight.contains(id)) {
      waitingReasons[id] = UploadWaitingReason.inFlight;
      continue;
    }

    if (isOffline) {
      waitingReasons[id] = UploadWaitingReason.offline;
      continue;
    }

    if (isMeteredBlocked) {
      waitingReasons[id] = UploadWaitingReason.waitingForWifi;
      continue;
    }

    if (!candidate.fileExists || candidate.localPath == null || candidate.localPath!.isEmpty) {
      waitingReasons[id] = UploadWaitingReason.fileMissing;
      continue;
    }

    // Parents must be synced (no pending record mutations in records lane for inspection or item)
    final parentInspectionPending = pendingRecordEntityIds.contains(candidate.inspectionId);
    final parentItemPending = candidate.itemId != null && pendingRecordEntityIds.contains(candidate.itemId!);
    if (parentInspectionPending || parentItemPending) {
      waitingReasons[id] = UploadWaitingReason.waitingForParent;
      continue;
    }

    // Per-op backoff check
    if (candidate.nextAttemptAt > now) {
      waitingReasons[id] = UploadWaitingReason.backoff;
      continue;
    }

    // Check available concurrency slots
    if (toUpload.length < availableSlots) {
      toUpload.add(candidate);
    } else {
      waitingReasons[id] = UploadWaitingReason.concurrencyLimit;
    }
  }

  return ScheduleResult(
    toUpload: toUpload,
    waitingReasons: waitingReasons,
  );
}
