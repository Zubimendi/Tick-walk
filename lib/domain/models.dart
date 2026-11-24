// Core domain models and enums for Tickwalk.
// Invariant: Pure Dart — no Flutter, Drift, or platform imports.

enum InspectionStatus {
  inProgress('in_progress'),
  completed('completed');

  const InspectionStatus(this.value);
  final String value;

  static InspectionStatus fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => inProgress);
}

enum ItemType {
  passFail('pass_fail'),
  text('text'),
  number('number');

  const ItemType(this.value);
  final String value;

  static ItemType fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => passFail);
}

enum ItemResponse {
  pass('pass'),
  fail('fail'),
  na('na');

  const ItemResponse(this.value);
  final String value;

  static ItemResponse? fromString(String? val) {
    if (val == null) return null;
    for (final e in values) {
      if (e.value == val) return e;
    }
    return null;
  }
}

enum Severity {
  low('low'),
  medium('medium'),
  high('high');

  const Severity(this.value);
  final String value;

  static Severity? fromString(String? val) {
    if (val == null) return null;
    for (final e in values) {
      if (e.value == val) return e;
    }
    return null;
  }
}

enum AttachmentKind {
  photo('photo'),
  signature('signature');

  const AttachmentKind(this.value);
  final String value;

  static AttachmentKind fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => photo);
}

enum GpsFixStatus {
  fix('fix'),
  stale('stale'),
  none('none'),
  denied('denied');

  const GpsFixStatus(this.value);
  final String value;

  static GpsFixStatus fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => none);
}

enum OutboxEntity {
  template('template'),
  inspection('inspection'),
  inspectionItem('inspection_item'),
  attachment('attachment');

  const OutboxEntity(this.value);
  final String value;

  static OutboxEntity fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => inspection);
}

enum OutboxOp {
  create('create'),
  update('update'),
  delete('delete');

  const OutboxOp(this.value);
  final String value;

  static OutboxOp fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => create);
}

enum OutboxLane {
  records('records'),
  media('media');

  const OutboxLane(this.value);
  final String value;

  static OutboxLane fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => records);
}

enum OutboxStatus {
  pending('pending'),
  parked('parked');

  const OutboxStatus(this.value);
  final String value;

  static OutboxStatus fromString(String val) =>
      values.firstWhere((e) => e.value == val, orElse: () => pending);
}

/// Template entity representing a checklist definition.
class Template {
  const Template({
    required this.id,
    required this.name,
    this.description,
    required this.structure,
    this.isStarter = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String structure; // Raw JSON schema v1 string
  final bool isStarter;
  final int createdAt; // epoch millis
  final int updatedAt;
  final int? deletedAt;

  Template copyWith({
    String? id,
    String? name,
    String? description,
    String? structure,
    bool? isStarter,
    int? createdAt,
    int? updatedAt,
    int? deletedAt,
  }) {
    return Template(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      structure: structure ?? this.structure,
      isStarter: isStarter ?? this.isStarter,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Active or completed inspection instance.
class Inspection {
  const Inspection({
    required this.id,
    this.templateId,
    required this.templateName,
    required this.siteName,
    this.siteAddress,
    required this.inspectorName,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.reopenedCount = 0,
    this.startLat,
    this.startLng,
    this.startAccuracyM,
    this.startGpsStatus,
    this.startGpsAt,
    this.signatureAttachmentId,
    this.notes,
    this.totalItems = 0,
    this.answeredItems = 0,
    this.passCount = 0,
    this.failCount = 0,
    this.naCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String? templateId;
  final String templateName; // Snapshot at start
  final String siteName;
  final String? siteAddress;
  final String inspectorName;
  final InspectionStatus status;
  final int startedAt;
  final int? completedAt;
  final int reopenedCount;
  final double? startLat;
  final double? startLng;
  final double? startAccuracyM;
  final GpsFixStatus? startGpsStatus;
  final int? startGpsAt;
  final String? signatureAttachmentId;
  final String? notes;

  // Cached summary counts
  final int totalItems;
  final int answeredItems;
  final int passCount;
  final int failCount;
  final int naCount;

  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get isCompleted => status == InspectionStatus.completed;

  Inspection copyWith({
    String? id,
    String? templateId,
    String? templateName,
    String? siteName,
    String? siteAddress,
    String? inspectorName,
    InspectionStatus? status,
    int? startedAt,
    int? completedAt,
    int? reopenedCount,
    double? startLat,
    double? startLng,
    double? startAccuracyM,
    GpsFixStatus? startGpsStatus,
    int? startGpsAt,
    String? signatureAttachmentId,
    String? notes,
    int? totalItems,
    int? answeredItems,
    int? passCount,
    int? failCount,
    int? naCount,
    int? createdAt,
    int? updatedAt,
    int? deletedAt,
  }) {
    return Inspection(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      templateName: templateName ?? this.templateName,
      siteName: siteName ?? this.siteName,
      siteAddress: siteAddress ?? this.siteAddress,
      inspectorName: inspectorName ?? this.inspectorName,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      reopenedCount: reopenedCount ?? this.reopenedCount,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      startAccuracyM: startAccuracyM ?? this.startAccuracyM,
      startGpsStatus: startGpsStatus ?? this.startGpsStatus,
      startGpsAt: startGpsAt ?? this.startGpsAt,
      signatureAttachmentId: signatureAttachmentId ?? this.signatureAttachmentId,
      notes: notes ?? this.notes,
      totalItems: totalItems ?? this.totalItems,
      answeredItems: answeredItems ?? this.answeredItems,
      passCount: passCount ?? this.passCount,
      failCount: failCount ?? this.failCount,
      naCount: naCount ?? this.naCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Snapshot item copied from template into an inspection.
class InspectionItem {
  const InspectionItem({
    required this.id,
    required this.inspectionId,
    required this.sectionTitle,
    required this.sectionOrder,
    required this.itemOrder,
    required this.prompt,
    required this.itemType,
    this.unit,
    this.required = false,
    this.photoRequiredOnFail = false,
    this.response,
    this.severity,
    this.textValue,
    this.numberValue,
    this.note,
    this.respondedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String inspectionId;
  final String sectionTitle;
  final int sectionOrder;
  final int itemOrder;
  final String prompt;
  final ItemType itemType;
  final String? unit;
  final bool required;
  final bool photoRequiredOnFail;
  final ItemResponse? response;
  final Severity? severity;
  final String? textValue;
  final double? numberValue;
  final String? note;
  final int? respondedAt;
  final int createdAt;
  final int updatedAt;

  bool get isAnswered => switch (itemType) {
        ItemType.passFail => response != null,
        ItemType.text => textValue != null && textValue!.trim().isNotEmpty,
        ItemType.number => numberValue != null,
      };

  InspectionItem copyWith({
    String? id,
    String? inspectionId,
    String? sectionTitle,
    int? sectionOrder,
    int? itemOrder,
    String? prompt,
    ItemType? itemType,
    String? unit,
    bool? required,
    bool? photoRequiredOnFail,
    ItemResponse? response,
    Severity? severity,
    String? textValue,
    double? numberValue,
    String? note,
    int? respondedAt,
    int? createdAt,
    int? updatedAt,
  }) {
    return InspectionItem(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      sectionOrder: sectionOrder ?? this.sectionOrder,
      itemOrder: itemOrder ?? this.itemOrder,
      prompt: prompt ?? this.prompt,
      itemType: itemType ?? this.itemType,
      unit: unit ?? this.unit,
      required: required ?? this.required,
      photoRequiredOnFail: photoRequiredOnFail ?? this.photoRequiredOnFail,
      response: response ?? this.response,
      severity: severity ?? this.severity,
      textValue: textValue ?? this.textValue,
      numberValue: numberValue ?? this.numberValue,
      note: note ?? this.note,
      respondedAt: respondedAt ?? this.respondedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Attachment model for photo evidence or inspector signatures.
class Attachment {
  const Attachment({
    required this.id,
    required this.inspectionId,
    this.itemId,
    required this.kind,
    this.localPath,
    this.thumbPath,
    required this.sha256,
    required this.bytes,
    this.width,
    this.height,
    this.compressionProfile,
    required this.capturedAt,
    this.gpsLat,
    this.gpsLng,
    this.gpsAccuracyM,
    required this.gpsStatus,
    this.gpsAt,
    this.caption,
    this.uploadedAt,
    this.serverReceivedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String inspectionId;
  final String? itemId;
  final AttachmentKind kind;
  final String? localPath;
  final String? thumbPath;
  final String sha256;
  final int bytes;
  final int? width;
  final int? height;
  final String? compressionProfile;
  final int capturedAt;
  final double? gpsLat;
  final double? gpsLng;
  final double? gpsAccuracyM;
  final GpsFixStatus gpsStatus;
  final int? gpsAt;
  final String? caption;
  final int? uploadedAt;
  final int? serverReceivedAt;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get isUploaded => uploadedAt != null;
  bool get isDeleted => deletedAt != null;
  bool get isPhoto => kind == AttachmentKind.photo;
  bool get isSignature => kind == AttachmentKind.signature;

  Attachment copyWith({
    String? id,
    String? inspectionId,
    String? itemId,
    AttachmentKind? kind,
    String? localPath,
    String? thumbPath,
    String? sha256,
    int? bytes,
    int? width,
    int? height,
    String? compressionProfile,
    int? capturedAt,
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracyM,
    GpsFixStatus? gpsStatus,
    int? gpsAt,
    String? caption,
    int? uploadedAt,
    int? serverReceivedAt,
    int? createdAt,
    int? updatedAt,
    int? deletedAt,
  }) {
    return Attachment(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      itemId: itemId ?? this.itemId,
      kind: kind ?? this.kind,
      localPath: localPath ?? this.localPath,
      thumbPath: thumbPath ?? this.thumbPath,
      sha256: sha256 ?? this.sha256,
      bytes: bytes ?? this.bytes,
      width: width ?? this.width,
      height: height ?? this.height,
      compressionProfile: compressionProfile ?? this.compressionProfile,
      capturedAt: capturedAt ?? this.capturedAt,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      gpsAccuracyM: gpsAccuracyM ?? this.gpsAccuracyM,
      gpsStatus: gpsStatus ?? this.gpsStatus,
      gpsAt: gpsAt ?? this.gpsAt,
      caption: caption ?? this.caption,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      serverReceivedAt: serverReceivedAt ?? this.serverReceivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

/// Outbox mutation entry for two-lane sync.
class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.entity,
    required this.entityId,
    required this.op,
    required this.payload,
    required this.lane,
    this.attempts = 0,
    this.nextAttemptAt = 0,
    this.status = OutboxStatus.pending,
    this.lastError,
    required this.createdAt,
  });

  final int seq;
  final OutboxEntity entity;
  final String entityId;
  final OutboxOp op;
  final String payload; // JSON payload
  final OutboxLane lane;
  final int attempts;
  final int nextAttemptAt;
  final OutboxStatus status;
  final String? lastError;
  final int createdAt;

  OutboxEntry copyWith({
    int? seq,
    OutboxEntity? entity,
    String? entityId,
    OutboxOp? op,
    String? payload,
    OutboxLane? lane,
    int? attempts,
    int? nextAttemptAt,
    OutboxStatus? status,
    String? lastError,
    int? createdAt,
  }) {
    return OutboxEntry(
      seq: seq ?? this.seq,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      lane: lane ?? this.lane,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
