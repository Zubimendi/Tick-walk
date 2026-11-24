import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/capture_pipeline.dart';
import 'capture/gps_service.dart';
import 'core/clock.dart';
import 'data/api/auth.dart';
import 'data/api/pb_client.dart';
import 'data/api/token_storage.dart';
import 'data/db/app_database.dart' hide Template, Inspection, InspectionItem, Attachment;
import 'data/repositories/attachment_repository.dart';
import 'data/repositories/inspection_repository.dart';
import 'data/repositories/mappers.dart';
import 'data/repositories/outbox_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/template_repository.dart';
import 'data/sync/connectivity.dart';
import 'data/sync/media_lane.dart';
import 'data/sync/record_lane.dart';
import 'data/sync/upload_scheduler.dart';
import 'domain/models.dart';
import 'domain/validation.dart';
import 'ui/widgets/status_chip.dart';

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in ProviderScope');
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  );
});

final inspectionRepositoryProvider = Provider<InspectionRepository>((ref) {
  return InspectionRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  );
});

final attachmentRepositoryProvider = Provider<AttachmentRepository>((ref) {
  return AttachmentRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  );
});

final gpsServiceProvider = Provider<GpsService>((ref) {
  return GpsService();
});

final capturePipelineProvider = Provider<CapturePipeline>((ref) {
  return CapturePipeline(
    attachmentRepository: ref.watch(attachmentRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    clock: ref.watch(clockProvider),
    gpsFixProvider: ref.watch(gpsServiceProvider),
  );
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const SecureTokenStorage();
});

final pbClientProvider = Provider<PbClient>((ref) {
  return PbClient(tokenStorage: ref.watch(tokenStorageProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    pbClient: ref.watch(pbClientProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    db: ref.watch(databaseProvider),
  );
});

final settingsMapProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(settingsRepositoryProvider).watchAll();
});

final onboardingDoneProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsMapProvider).value ?? {};
  return settings['onboarding_done'] == 'true';
});

final inspectorNameProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsMapProvider).value ?? {};
  return settings['inspector_name'] ?? '';
});

final templatesStreamProvider = StreamProvider<List<Template>>((ref) {
  return ref.watch(templateRepositoryProvider).watchTemplates();
});

final inspectionsStreamProvider =
    StreamProvider.family<List<Inspection>, InspectionStatus?>((ref, status) {
  return ref.watch(inspectionRepositoryProvider).watchInspections(status: status);
});

final singleInspectionProvider =
    StreamProvider.family<Inspection?, String>((ref, id) {
  return ref.watch(inspectionRepositoryProvider).watchInspection(id);
});

final inspectionItemsProvider =
    StreamProvider.family<List<InspectionItem>, String>((ref, inspectionId) {
  return ref.watch(inspectionRepositoryProvider).watchItems(inspectionId);
});

final inspectionAttachmentsProvider =
    StreamProvider.family<List<Attachment>, String>((ref, inspectionId) {
  return ref.watch(attachmentRepositoryProvider).watchAttachments(inspectionId);
});

final singleAttachmentProvider =
    StreamProvider.family<Attachment?, String>((ref, id) {
  return ref.watch(attachmentRepositoryProvider).watchAttachment(id);
});

final inspectionPhotoCountsProvider =
    StreamProvider.family<Map<String, int>, String>((ref, inspectionId) {
  return ref.watch(inspectionRepositoryProvider).watchPhotoCountByItem(inspectionId);
});

final inspectionBlockersProvider =
    Provider.family<List<CompletionBlocker>, String>((ref, inspectionId) {
  final items = ref.watch(inspectionItemsProvider(inspectionId)).value ?? [];
  final photoCounts =
      ref.watch(inspectionPhotoCountsProvider(inspectionId)).value ?? {};
  return validateCompletion(items: items, photoCountByItem: photoCounts);
});

final outboxRepositoryProvider = Provider<OutboxRepository>((ref) {
  return OutboxRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  );
});

final recordLaneProvider = Provider<RecordLane>((ref) {
  return RecordLane(
    pbClient: ref.watch(pbClientProvider),
    db: ref.watch(databaseProvider),
    outboxRepo: ref.watch(outboxRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

final mediaLaneProvider = Provider<MediaLane>((ref) {
  return MediaLane(
    pbClient: ref.watch(pbClientProvider),
    db: ref.watch(databaseProvider),
    outboxRepo: ref.watch(outboxRepositoryProvider),
    settingsRepo: ref.watch(settingsRepositoryProvider),
    clock: ref.watch(clockProvider),
  );
});

final pendingOutboxCountProvider = StreamProvider<int>((ref) {
  return ref.watch(outboxRepositoryProvider).watchPendingCount();
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

final connectivityStateProvider = StreamProvider<NetworkConnectionType>((ref) {
  return ref.watch(connectivityServiceProvider).watch();
});

final inspectionSyncStateProvider =
    StreamProvider.family<UploadVisualState?, String>((ref, inspectionId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.attachments)
        ..where((t) => t.inspectionId.equals(inspectionId))
        ..where((t) => t.deletedAt.isNull()))
      .watch()
      .asyncMap((attachments) async {
    if (attachments.isEmpty) return null;

    final syncOwner = await (db.select(db.settings)
          ..where((t) => t.key.equals('sync_owner_id')))
        .getSingleOrNull();
    if (syncOwner == null || syncOwner.value.trim().isEmpty) {
      return null; // Not signed in
    }

    final unsynced = attachments.where((a) => a.uploadedAt == null).toList();
    if (unsynced.isEmpty) {
      return UploadVisualState.uploaded;
    }

    final attIds = unsynced.map((a) => a.id).toSet();
    final outboxRows = await (db.select(db.outbox)
          ..where((t) => t.entityId.isIn(attIds)))
        .get();

    if (outboxRows.any((r) => r.status == 'parked')) {
      return UploadVisualState.failed;
    }
    if (outboxRows.any((r) => r.attempts > 0)) {
      return UploadVisualState.retrying;
    }

    final mediaLane = ref.read(mediaLaneProvider);
    if (attIds.any((id) => mediaLane.inFlight.contains(id))) {
      return UploadVisualState.uploading;
    }
    if (attIds.any((id) =>
        mediaLane.waitingReasons[id] == UploadWaitingReason.waitingForWifi)) {
      return UploadVisualState.waitingWifi;
    }

    return UploadVisualState.waiting;
  });
});

class UploadQueueItem {
  const UploadQueueItem({
    required this.outboxEntry,
    this.attachment,
    this.siteName,
    required this.visualState,
    this.failureReason,
  });

  final OutboxEntry outboxEntry;
  final Attachment? attachment;
  final String? siteName;
  final UploadVisualState visualState;
  final String? failureReason;
}

final uploadQueueProvider = StreamProvider<List<UploadQueueItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final mediaLane = ref.watch(mediaLaneProvider);

  final query = db.select(db.outbox)
    ..where((t) => t.lane.equals('media'))
    ..orderBy([(t) => drift.OrderingTerm.desc(t.seq)]);

  final joined = query.join([
    drift.leftOuterJoin(
      db.attachments,
      db.attachments.id.equalsExp(db.outbox.entityId),
    ),
    drift.leftOuterJoin(
      db.inspections,
      db.inspections.id.equalsExp(db.attachments.inspectionId),
    ),
  ]);

  return joined.watch().map((rows) {
    return rows.map((row) {
      final outboxRow = row.readTable(db.outbox);
      final attRow = row.readTableOrNull(db.attachments);
      final inspRow = row.readTableOrNull(db.inspections);

      final entry = outboxEntryFromRow(outboxRow);
      final att = attRow != null ? attachmentFromRow(attRow) : null;
      final siteName = inspRow?.siteName;

      UploadVisualState visualState;
      String? failureReason;

      if (entry.status == OutboxStatus.parked) {
        visualState = UploadVisualState.failed;
        failureReason = entry.lastError ?? 'Failed to upload';
      } else if (mediaLane.inFlight.contains(entry.entityId)) {
        visualState = UploadVisualState.uploading;
      } else if (mediaLane.waitingReasons[entry.entityId] ==
          UploadWaitingReason.waitingForWifi) {
        visualState = UploadVisualState.waitingWifi;
      } else if (entry.attempts > 0) {
        visualState = UploadVisualState.retrying;
        failureReason = entry.lastError;
      } else {
        visualState = UploadVisualState.waiting;
      }

      return UploadQueueItem(
        outboxEntry: entry,
        attachment: att,
        siteName: siteName,
        visualState: visualState,
        failureReason: failureReason,
      );
    }).toList();
  });
});
