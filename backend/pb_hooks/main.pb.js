/// PocketBase server hooks for Tickwalk.
/// Invariant: Sets server received_at on attachments; enforces 409 stale_write conflict guard.

onRecordBeforeCreateRequest((e) => {
  // Attachments: assign server-controlled received_at timestamp
  if (e.collection.name === "attachments") {
    e.record.set("received_at", Date.now());

    // Validate uploaded file size against bytes field if file is present
    const uploadedFiles = e.httpContext.findUploadedFiles("file");
    if (uploadedFiles && uploadedFiles.length > 0) {
      const file = uploadedFiles[0];
      const declaredBytes = e.record.get("bytes");
      if (declaredBytes && Math.abs(file.size - declaredBytes) > 1024) {
        // Discrepancy > 1KB between declared bytes and actual file
        e.record.set("bytes", file.size);
      }
    }
  }

  // Set owner if not explicitly passed
  if (e.httpContext.get("authRecord")) {
    const authId = e.httpContext.get("authRecord").id;
    if (!e.record.get("owner")) {
      e.record.set("owner", authId);
    }
  }
}, "templates", "inspections", "inspection_items", "attachments");

onRecordBeforeUpdateRequest((e) => {
  const collectionName = e.collection.name;
  if (!["templates", "inspections", "inspection_items", "attachments"].includes(collectionName)) {
    return;
  }

  const now = Date.now();
  const original = e.record.originalCopy();
  const currentUpdated = original.get("client_updated_at") || 0;
  let incomingUpdated = e.record.get("client_updated_at") || 0;

  // 1. Clock skew guard: clamp if more than 5 minutes in future
  const maxFuture = now + 5 * 60 * 1000;
  if (incomingUpdated > maxFuture) {
    incomingUpdated = now;
    e.record.set("client_updated_at", now);
  }

  // 2. Conflict guard: 409 stale_write if incoming write timestamp is older than stored
  if (incomingUpdated < currentUpdated) {
    throw new ApiError(409, "stale_write", {
      message: "Server has a newer version of this record",
      serverRecord: original,
    });
  }
}, "templates", "inspections", "inspection_items", "attachments");
