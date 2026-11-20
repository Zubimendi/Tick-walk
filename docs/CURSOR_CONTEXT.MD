# Tickwalk: Agent Context (Cursor)

Read this file, `docs/architecture.md`, `docs/prd.md` and `docs/design.md` before writing code. Work one task at a time from section 12. After each task, stop, summarize what changed, and wait for the next instruction.

## 1. Project snapshot

Tickwalk is an offline-first inspection checklist app with photo and GPS evidence. Flutter (Dart 3), Riverpod, Drift. Optional account syncs to PocketBase through an outbox with two lanes (ordered records, parallel photo uploads). No paid services, no analytics SDKs.

If the Emberday repository is available, copy and generalize `lib/core` (clock, ids, result, errors, logger) and `lib/data/sync` (outbox, backoff, merge) from it. If not, implement from `docs/architecture.md` section 8.

## 2. Non-negotiable rules

1. **Time is injected.** Never call `DateTime.now()` outside `lib/core/clock.dart`.
2. **Domain logic is pure.** `template_schema.dart`, `validation.dart`, `report_model.dart`, `compression_profiles.dart` and the upload scheduler have no Flutter, Drift or platform imports.
3. UI code never touches the network, files, camera, GPS or database directly; it uses providers and repositories.
4. **Capture order:** (a) persist pending-capture, (b) launch camera and start GPS in parallel, (c) compress and thumbnail natively, (d) hash, (e) move files into app storage, (f) one Drift transaction for the attachment row, summary effects and outbox row, (g) clear pending-capture. Never insert a database row for a file that does not exist on disk.
5. Never decode full-resolution images in Dart. Use native compression and `cacheWidth` or thumbnails for display.
6. Every item answer or attachment change runs in **one Drift transaction**: the change, recompute of the inspection's cached counts, and (if signed in) an outbox row.
7. Inspection items are a **snapshot**; never read prompts from the template after the inspection starts.
8. Completed inspections are read-only in repositories (reject writes with a typed error) until reopened.
9. UI reads via Drift streams through Riverpod providers.
10. Tokens live in `flutter_secure_storage` only.
11. No new dependency without a one-line justification and my approval.
12. No raw colors, spacing or font sizes in widgets; use theme extension tokens.
13. No `dynamic`. No `// ignore` without an explanatory comment and my approval. Strict analysis (`strict-casts`, `strict-inference`, `strict-raw-types`).
14. Minimal diffs when editing existing files; do not rewrite whole files or reformat unrelated code.
15. Do not invent package APIs. Read the installed package source or docs and say what you checked; versions change.
16. Never log notes, captions, site names, coordinates, file paths or emails. Log ids, counts and error classes only.
17. No silent TODOs. State anything deferred in your summary.

## 3. Tech stack and install policy

- Flutter stable, Dart 3
- State: `flutter_riverpod` (manual providers)
- Data: `drift`, `drift_flutter` (or `sqlite3_flutter_libs` and `path_provider`), dev: `drift_dev`, `build_runner`
- Navigation: `go_router` with a shell route
- Capture: `image_picker` (camera source only; gallery only if the setting is on), `geolocator`, `flutter_image_compress`, `crypto`, `path`, `path_provider`
- Reports: `pdf`, `share_plus`
- Network and storage: `pocketbase`, `connectivity_plus`, `flutter_secure_storage`
- Background (P1): `workmanager`
- Utilities: `intl`
- Tests: `flutter_test`, `mocktail`
- Lints: `flutter_lints` plus strict analysis
- Platform setup (follow each package README, verify): Android location permissions, camera intent handling, image picker lost-data retrieval; iOS Info.plist usage strings for camera and location; WorkManager initialization

## 4. Folder structure

```text
lib/
  main.dart, app.dart
  core/                       clock, ids, logger, result, errors, dates
  domain/
    models.dart               Template, Inspection, InspectionItem, Attachment, enums
    template_schema.dart      parse, serialize, validate (schemaVersion 1)
    validation.dart           validateCompletion -> List<Blocker>
    report_model.dart         build report data from inspection data
  data/
    db/                       app_database.dart, tables.dart, daos
    repositories/             template_repo, inspection_repo, attachment_repo, settings_repo, outbox_repo
    sync/                     outbox, engine, record_lane, media_lane, upload_scheduler, backoff, merge, status
    api/                      pb_client.dart, auth.dart, error_mapper.dart
  capture/                    capture_pipeline.dart, gps.dart, compression_profiles.dart, recovery.dart
  reports/                    pdf_builder.dart
  features/                   inspections/, checklist/, templates/, uploads/, settings/, onboarding/, account/
  ui/                         theme.dart, tokens.dart, widgets/
test/
backend/
docs/
```

## 5. Domain rules

- Item types: `pass_fail` (responses `pass`, `fail`, `na`), `text`, `number` (optional unit).
- An item is **answered** if `response` is set (pass_fail), `text_value` is non-empty (text), or `number_value` is non-null (number).
- Completion blockers: any `required` item unanswered; any pass_fail item with `fail` and `photo_required_on_fail` that has zero non-deleted photos.
- Cached counts on the inspection: total, answered, pass, fail, na. Recompute from items in the same transaction as any item change.
- Starter templates are normal templates with `is_starter = 1`; editing them edits the copy.
- Template schema JSON: `{schemaVersion: 1, sections: [{id, title, items: [{id, prompt, type, required, photoRequiredOnFail, unit}]}]}`. Reject unknown `schemaVersion` with a typed error.
- Reopening sets status to `in_progress` and increments `reopened_count`; completing again sets `completed_at`.

## 6. Capture rules

- Compression profiles: Low data (longest edge 1280, quality 65), Standard (1600, 75), High (2048, 85). Thumbnail: longest edge 320, quality 70. Strip EXIF. Verify the library's resize semantics with a test image and assert the output size in a test.
- If compression fails, keep the original file, set a flag on the attachment and continue.
- Check free storage before capture; if low, show "Not enough space to save the photo".
- GPS: request a fix at capture start with `high` accuracy and a 10 s limit. Accept the first fix with accuracy at or below 50 m, otherwise take the best fix at the limit. If none, use last known and mark `stale`. If permission is denied, mark `denied`; if no fix, mark `none`. Capture must never block on GPS beyond the limit and never fail because of it.
- Request location permission when the user starts the first inspection (contextual), not at launch.
- Pending-capture: store `{inspectionId, itemId, startedAt}` in settings before launching the camera. On app start and resume, call the picker's lost-data retrieval (verify the API); if a file is returned and a pending-capture exists, run the pipeline for it; otherwise discard.
- `captured_at` is the time the picker returns, using the injected clock (approximate within seconds); document that in code comments.

## 7. Sync rules (only when signed in)

- Entities: template, inspection, inspection_item, attachment. One LWW timestamp (`updated_at`) per record.
- **Lane 1 (records):** ordered by `seq`: template, inspection, inspection_item. Coalesce before drain (create+updates becomes one create; create+delete for an unsynced entity drops both; updates+delete becomes delete). Stop the drain on retryable errors.
- **Lane 2 (media):** attachment creates only, run after the parent inspection and item are synced. Up to 2 concurrent uploads. Each op has its own `next_attempt_at`; a failing upload does not block others.
- Upload as multipart with the client attachment ID as the record ID and metadata fields. Duplicate create: GET the record and treat as success. Missing local file: park with reason "file missing". 413 or 400: park with a plain reason.
- Attachment updates (caption) and deletes are JSON patches through lane 1 rules (after the create has synced).
- Wi-Fi only: before starting each upload, check connectivity type; if on mobile data and the setting is on, leave the op waiting with reason `waitingForWifi`. "Upload now" sets a one-batch override flag in memory.
- Retryable (network, timeout, 5xx, 429): record backoff base 2 s, media backoff base 5 s, factor 2, jitter plus or minus 20%, caps 5 min (records) and 15 min (media). Permanent (400, 403, 413, 422): park. 401: refresh once, then flag "needs sign-in" and keep local use intact. 409 `stale_write`: fetch the server record, apply, drop the op.
- Pull `updated >= cursor`, sorted `updated,id`, 200 per page, idempotent apply, skip entities with pending outbox ops; recompute affected inspection counts after applying items. Attachments pulled from the server have `local_path = null` and show a placeholder.
- Account guard: store `sync_owner_id`; signing in as a different user prompts "Replace local data or cancel".
- Start the engine after the first frame, never during startup.

## 8. Error handling rules

- `Result<T, AppError>` in repositories and API wrappers.
- Error classes: `network`, `transient`, `auth`, `forbidden`, `validation`, `conflict`, `notFound`, `local`, `storageFull`, `permission`, `unknown`.
- UI never shows raw exception text; use microcopy from `docs/design.md`.
- Global handlers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`) log and show a fallback; route-level error widgets.
- Local database failure shows a recovery screen with Restart; never auto-delete data or photo files.

## 9. UI rules

- Follow `docs/design.md`: tokens, 48 dp targets (answer buttons 56 dp), results use icon plus text plus color.
- Every tappable has `Semantics` (label, role, state). Respect `MediaQuery.disableAnimations`.
- Lists use builders with stable keys; thumbnails use the 320 px files with `cacheWidth`.
- The signature pad is a `CustomPainter`; export to PNG and store as an attachment of kind `signature`.

## 10. Testing rules

- Pure first: `template_schema`, `validation`, `compression_profiles`, `upload_scheduler`, `backoff`, outbox coalescing, `report_model`, capture recovery decision logic.
- Repository tests with an in-memory Drift database (verify it runs under `flutter test`): template snapshot, summary consistency (random answers, cache equals recomputation), read-only enforcement after completion.
- Upload scheduler tests: concurrency of 2, per-op backoff, Wi-Fi gating, parent-first ordering, missing file, duplicate create.
- Sync integration tests with a fake server and injected failures: network timeout mid-upload, 500, 429, 401, 409, 413, duplicate create, crash between server success and outbox delete.
- Widget tests: answering an item, fail panel with photo required, review blockers.
- Run `flutter analyze` and `flutter test` before declaring a task done.

## 11. Code style

- Explicit return types on public functions; sealed classes and pattern matching for states and errors
- Files `snake_case.dart`; one responsibility per file
- Comments explain why
- Conventional Commits, one commit per task

## 12. Build order

Each task is done only when its acceptance check passes.

| Task | Work | Acceptance |
|---|---|---|
| T1 | Scaffold Flutter app, strict analysis, structure, go_router shell with four tabs | App boots; analyze passes |
| T2 | Theme tokens (light and dark), base widgets | Both themes render; no raw literals |
| T3 | Core utilities (clock, ids, dates, logger, errors, Result) with tests | Tests pass |
| T4 | Domain models, `template_schema` with tests | Parse, serialize and unknown-version tests pass |
| T5 | Drift schema, database, migrations, settings | DB created on first launch |
| T6 | Starter templates (appendix A) seeded as data | Three templates appear on first run |
| T7 | Template, inspection and item repositories: snapshot on start, answer writes with count recompute | Snapshot and consistency tests pass |
| T8 | `validation.dart` and completion flow in the repository | Blocker tests pass; completed is read-only |
| T9 | Onboarding and Inspections list | Works offline |
| T10 | New inspection sheet and start | Items copied from the template |
| T11 | Checklist screen: sections, answer buttons, text and number fields, notes, progress, autosave | A 60-item checklist scrolls smoothly |
| T12 | Review and finish screen with blockers and complete or reopen | Blockers link to items |
| T13 | Compression profiles and `capture_pipeline` (camera, compress, thumbnail, hash, files) | Output size and dimension tests pass; photo appears on a real phone |
| T14 | GPS service with status model | All four statuses reachable (fix, stale, none, denied) |
| T15 | Pending-capture and lost-data recovery | Camera-kill test passes on a real phone |
| T16 | Photo strip, viewer, metadata panel, delete with undo | Matches design |
| T17 | Backend: collections (with protected file field), rules, hooks, migrations | Cross-user access rejected; multipart create with client ID works (verify) |
| T18 | PocketBase client, secure-storage auth, optional sign in, owner guard | Different-account prompt works |
| T19 | Outbox, coalescing, record lane | Records converge on a second device |
| T20 | Upload scheduler and media lane with per-file retry | Upload and kill tests pass |
| T21 | Uploads tab and per-photo status, retry, sync chips on inspections | All states reachable |
| T22 | Wi-Fi only gating and Upload now (P1) | Gating tests pass |
| T23 | Report model and PDF builder with photos downscaled for the PDF (P1) | PDF opens with failed items and stamps |
| T24 | Signature pad and severity chips (P1) | Appear in the report |
| T25 | Template editor (P1) | Create, edit, duplicate, delete with undo |
| T26 | Background upload task (P1, Android) | Task uploads queued items on device |
| T27 | Error handlers, accessibility pass, empty states | Screen reader and 200% text checks pass |
| T28 | Dev tools, profile-mode measurements, docs sync, README | Budgets recorded in `story.md`; new clone runs from README |

## 13. Definition of done (every task)

- Acceptance check passes
- `flutter analyze` and `flutter test` green
- No new dependency without approval
- No raw literals in UI; Semantics present
- Summary lists files changed, decisions made, and anything deferred

## 14. Stop and ask when

- A requirement conflicts with a package's actual behavior
- A new dependency seems necessary
- The data model would need to change
- Lost-data recovery or multipart create with a client ID does not work as planned
- Emberday's sync code is unavailable and a design choice is unclear

## 15. Starter prompts

> "Read cursorcontext.md, architecture.md, prd.md and design.md. Do T1 only. Stop when its acceptance check passes and summarize."

> "Do T13. Before coding, list the capture pipeline steps and the failure at each step, and the test you will write for each."