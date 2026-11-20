import '../db/app_database.dart' as db;
import '../../domain/models.dart';

Template templateFromRow(db.Template row) {
  return Template(
    id: row.id,
    name: row.name,
    description: row.description,
    structure: row.structure,
    isStarter: row.isStarter,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );
}

Inspection inspectionFromRow(db.Inspection row) {
  return Inspection(
    id: row.id,
    templateId: row.templateId,
    templateName: row.templateName,
    siteName: row.siteName,
    siteAddress: row.siteAddress,
    inspectorName: row.inspectorName,
    status: InspectionStatus.fromString(row.status),
    startedAt: row.startedAt,
    completedAt: row.completedAt,
    reopenedCount: row.reopenedCount,
    startLat: row.startLat,
    startLng: row.startLng,
    startAccuracyM: row.startAccuracyM,
    startGpsStatus: row.startGpsStatus != null
        ? GpsFixStatus.fromString(row.startGpsStatus!)
        : null,
    startGpsAt: row.startGpsAt,
    signatureAttachmentId: row.signatureAttachmentId,
    notes: row.notes,
    totalItems: row.totalItems,
    answeredItems: row.answeredItems,
    passCount: row.passCount,
    failCount: row.failCount,
    naCount: row.naCount,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );
}

InspectionItem inspectionItemFromRow(db.InspectionItem row) {
  return InspectionItem(
    id: row.id,
    inspectionId: row.inspectionId,
    sectionTitle: row.sectionTitle,
    sectionOrder: row.sectionOrder,
    itemOrder: row.itemOrder,
    prompt: row.prompt,
    itemType: ItemType.fromString(row.itemType),
    unit: row.unit,
    required: row.required,
    photoRequiredOnFail: row.photoRequiredOnFail,
    response: ItemResponse.fromString(row.response),
    severity: Severity.fromString(row.severity),
    textValue: row.textValue,
    numberValue: row.numberValue,
    note: row.note,
    respondedAt: row.respondedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

Attachment attachmentFromRow(db.Attachment row) {
  return Attachment(
    id: row.id,
    inspectionId: row.inspectionId,
    itemId: row.itemId,
    kind: AttachmentKind.fromString(row.kind),
    localPath: row.localPath,
    thumbPath: row.thumbPath,
    sha256: row.sha256,
    bytes: row.bytes,
    width: row.width,
    height: row.height,
    compressionProfile: row.compressionProfile,
    capturedAt: row.capturedAt,
    gpsLat: row.gpsLat,
    gpsLng: row.gpsLng,
    gpsAccuracyM: row.gpsAccuracyM,
    gpsStatus: GpsFixStatus.fromString(row.gpsStatus),
    gpsAt: row.gpsAt,
    caption: row.caption,
    uploadedAt: row.uploadedAt,
    serverReceivedAt: row.serverReceivedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );
}

OutboxEntry outboxEntryFromRow(db.OutboxData row) {
  return OutboxEntry(
    seq: row.seq,
    entity: OutboxEntity.fromString(row.entity),
    entityId: row.entityId,
    op: OutboxOp.fromString(row.op),
    payload: row.payload,
    lane: OutboxLane.fromString(row.lane),
    attempts: row.attempts,
    nextAttemptAt: row.nextAttemptAt,
    status: OutboxStatus.fromString(row.status),
    lastError: row.lastError,
    createdAt: row.createdAt,
  );
}
