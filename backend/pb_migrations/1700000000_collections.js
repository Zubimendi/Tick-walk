/// PocketBase migration defining collections for Tickwalk.
/// Invariant: Cross-user access rejected; multipart create with client ID supported; file field protected.

migrate((db) => {
  const usersCollection = new Dao(db).findCollectionByNameOrId("users");

  const commonRules = {
    listRule: "@request.auth.id != '' && owner = @request.auth.id",
    viewRule: "@request.auth.id != '' && owner = @request.auth.id",
    createRule: "@request.auth.id != '' && @request.data.owner = @request.auth.id",
    updateRule: "@request.auth.id != '' && owner = @request.auth.id",
    deleteRule: "@request.auth.id != '' && owner = @request.auth.id",
  };

  // 1. Templates collection
  const templates = new Collection({
    name: "templates",
    type: "base",
    ...commonRules,
    schema: [
      { name: "owner", type: "relation", required: true, options: { collectionId: usersCollection.id, cascadeDelete: true, maxSelect: 1 } },
      { name: "name", type: "text", required: true },
      { name: "description", type: "text", required: false },
      { name: "structure", type: "json", required: true },
      { name: "is_starter", type: "bool", required: false },
      { name: "client_updated_at", type: "number", required: true },
      { name: "deleted_at", type: "number", required: false },
    ],
  });
  new Dao(db).saveCollection(templates);

  // 2. Inspections collection
  const inspections = new Collection({
    name: "inspections",
    type: "base",
    ...commonRules,
    schema: [
      { name: "owner", type: "relation", required: true, options: { collectionId: usersCollection.id, cascadeDelete: true, maxSelect: 1 } },
      { name: "template_id", type: "text", required: false },
      { name: "template_name", type: "text", required: true },
      { name: "site_name", type: "text", required: true },
      { name: "site_address", type: "text", required: false },
      { name: "inspector_name", type: "text", required: true },
      { name: "status", type: "text", required: true },
      { name: "started_at", type: "number", required: true },
      { name: "completed_at", type: "number", required: false },
      { name: "reopened_count", type: "number", required: false },
      { name: "start_lat", type: "number", required: false },
      { name: "start_lng", type: "number", required: false },
      { name: "start_accuracy_m", type: "number", required: false },
      { name: "start_gps_status", type: "text", required: false },
      { name: "start_gps_at", type: "number", required: false },
      { name: "signature_attachment_id", type: "text", required: false },
      { name: "notes", type: "text", required: false },
      { name: "total_items", type: "number", required: false },
      { name: "answered_items", type: "number", required: false },
      { name: "pass_count", type: "number", required: false },
      { name: "fail_count", type: "number", required: false },
      { name: "na_count", type: "number", required: false },
      { name: "client_updated_at", type: "number", required: true },
      { name: "deleted_at", type: "number", required: false },
    ],
  });
  new Dao(db).saveCollection(inspections);

  // 3. Inspection Items collection
  const inspectionItems = new Collection({
    name: "inspection_items",
    type: "base",
    ...commonRules,
    schema: [
      { name: "owner", type: "relation", required: true, options: { collectionId: usersCollection.id, cascadeDelete: true, maxSelect: 1 } },
      { name: "inspection", type: "text", required: true },
      { name: "section_title", type: "text", required: true },
      { name: "section_order", type: "number", required: true },
      { name: "item_order", type: "number", required: true },
      { name: "prompt", type: "text", required: true },
      { name: "item_type", type: "text", required: true },
      { name: "unit", type: "text", required: false },
      { name: "required", type: "bool", required: false },
      { name: "photo_required_on_fail", type: "bool", required: false },
      { name: "response", type: "text", required: false },
      { name: "severity", type: "text", required: false },
      { name: "text_value", type: "text", required: false },
      { name: "number_value", type: "number", required: false },
      { name: "note", type: "text", required: false },
      { name: "responded_at", type: "number", required: false },
      { name: "client_updated_at", type: "number", required: true },
      { name: "deleted_at", type: "number", required: false },
    ],
  });
  new Dao(db).saveCollection(inspectionItems);

  // 4. Attachments collection
  const attachments = new Collection({
    name: "attachments",
    type: "base",
    ...commonRules,
    schema: [
      { name: "owner", type: "relation", required: true, options: { collectionId: usersCollection.id, cascadeDelete: true, maxSelect: 1 } },
      { name: "inspection", type: "text", required: true },
      { name: "item", type: "text", required: false },
      { name: "kind", type: "text", required: true },
      {
        name: "file",
        type: "file",
        required: false,
        options: {
          maxSelect: 1,
          maxSize: 5242880, // 5 MB
          mimeTypes: ["image/jpeg", "image/png"],
          protected: true, // Protected file field per Section 9.1 & T17
        },
      },
      { name: "sha256", type: "text", required: true },
      { name: "bytes", type: "number", required: true },
      { name: "width", type: "number", required: false },
      { name: "height", type: "number", required: false },
      { name: "compression_profile", type: "text", required: false },
      { name: "captured_at", type: "number", required: true },
      { name: "gps_lat", type: "number", required: false },
      { name: "gps_lng", type: "number", required: false },
      { name: "gps_accuracy_m", type: "number", required: false },
      { name: "gps_status", type: "text", required: true },
      { name: "gps_at", type: "number", required: false },
      { name: "caption", type: "text", required: false },
      { name: "received_at", type: "number", required: false },
      { name: "client_updated_at", type: "number", required: true },
      { name: "deleted_at", type: "number", required: false },
    ],
  });
  new Dao(db).saveCollection(attachments);
}, (db) => {
  const dao = new Dao(db);
  const collections = ["attachments", "inspection_items", "inspections", "templates"];
  for (const name of collections) {
    try {
      const col = dao.findCollectionByNameOrId(name);
      if (col) dao.deleteCollection(col);
    } catch (_) {}
  }
});
