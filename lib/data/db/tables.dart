import 'package:drift/drift.dart';

class Templates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get structure => text()(); // JSON string (schemaVersion 1)
  BoolColumn get isStarter => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Inspections extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().nullable()();
  TextColumn get templateName => text()(); // Snapshot at start
  TextColumn get siteName => text()();
  TextColumn get siteAddress => text().nullable()();
  TextColumn get inspectorName => text()();
  TextColumn get status => text()(); // 'in_progress', 'completed'
  IntColumn get startedAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get reopenedCount => integer().withDefault(const Constant(0))();

  RealColumn get startLat => real().nullable()();
  RealColumn get startLng => real().nullable()();
  RealColumn get startAccuracyM => real().nullable()();
  TextColumn get startGpsStatus => text().nullable()(); // 'fix', 'stale', 'none', 'denied'
  IntColumn get startGpsAt => integer().nullable()();

  TextColumn get signatureAttachmentId => text().nullable()();
  TextColumn get notes => text().nullable()();

  // Cached summary counters recomputed in the same transaction as item writes
  IntColumn get totalItems => integer().withDefault(const Constant(0))();
  IntColumn get answeredItems => integer().withDefault(const Constant(0))();
  IntColumn get passCount => integer().withDefault(const Constant(0))();
  IntColumn get failCount => integer().withDefault(const Constant(0))();
  IntColumn get naCount => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class InspectionItems extends Table {
  TextColumn get id => text()();
  TextColumn get inspectionId => text().references(Inspections, #id)();
  TextColumn get sectionTitle => text()();
  IntColumn get sectionOrder => integer()();
  IntColumn get itemOrder => integer()();
  TextColumn get prompt => text()();
  TextColumn get itemType => text()(); // 'pass_fail', 'text', 'number'
  TextColumn get unit => text().nullable()();
  BoolColumn get required => boolean().withDefault(const Constant(false))();
  BoolColumn get photoRequiredOnFail => boolean().withDefault(const Constant(false))();

  TextColumn get response => text().nullable()(); // 'pass', 'fail', 'na'
  TextColumn get severity => text().nullable()(); // 'low', 'medium', 'high'
  TextColumn get textValue => text().nullable()();
  RealColumn get numberValue => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get respondedAt => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get inspectionId => text().references(Inspections, #id)();
  TextColumn get itemId => text().nullable().references(InspectionItems, #id)();
  TextColumn get kind => text()(); // 'photo', 'signature'
  TextColumn get localPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();
  TextColumn get sha256 => text()();
  IntColumn get bytes => integer()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get compressionProfile => text().nullable()(); // 'low', 'standard', 'high', 'original'
  IntColumn get capturedAt => integer()();

  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLng => real().nullable()();
  RealColumn get gpsAccuracyM => real().nullable()();
  TextColumn get gpsStatus => text()(); // 'fix', 'stale', 'none', 'denied'
  IntColumn get gpsAt => integer().nullable()();

  TextColumn get caption => text().nullable()();
  IntColumn get uploadedAt => integer().nullable()();
  IntColumn get serverReceivedAt => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()(); // 'template', 'inspection', 'inspection_item', 'attachment'
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // 'create', 'update', 'delete'
  TextColumn get payload => text()(); // JSON string
  TextColumn get lane => text().withDefault(const Constant('records'))(); // 'records', 'media'
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // 'pending', 'parked'
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer()();
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
