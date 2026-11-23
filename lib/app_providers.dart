import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/capture_pipeline.dart';
import 'capture/gps_service.dart';
import 'core/clock.dart';
import 'data/db/app_database.dart' hide Template, Inspection, InspectionItem, Attachment;
import 'data/repositories/attachment_repository.dart';
import 'data/repositories/inspection_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/template_repository.dart';
import 'domain/models.dart';
import 'domain/validation.dart';

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
  return ref.watch(inspectionRepositoryProvider).watchAttachments(inspectionId);
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
