# Tickwalk

[![Flutter](https://img.shields.io/badge/Flutter-Dart%203-02569B.svg?logo=flutter)](https://flutter.dev/)
[![SQLite](https://img.shields.io/badge/SQLite-Drift-5C6BC0.svg)](https://drift.simonbinder.eu/)
[![PocketBase](https://img.shields.io/badge/Backend-PocketBase-B8DBE4.svg)](https://pocketbase.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://img.shields.io/badge/Tests-Passing-brightgreen.svg)]()
[![Postman](https://img.shields.io/badge/Postman-17%2F17%20Passing-brightgreen.svg)]()

A production-grade, offline-first mobile inspection engine in Flutter. Project 4 of the mobile portfolio roadmap.

Field inspections happen where signal is weakest: basement power rooms, active construction sites, and remote substations. When connectivity drops, most inspection apps freeze, drop photos, or burn cellular quotas with silent upload failures. Tickwalk keeps the entire inspection workflow local on device, stamps evidence with time and GPS, and syncs reliably in the background when connectivity returns.

---

## Architectural Core: The Three Pillars

Tickwalk is designed around three foundational architectural principles documented in `docs/ARCHITECTURE.MD`:

### 1. The Device DB Decides; The Server Backs Up

Inspection data and photo evidence are captured in high-stress, zero-connectivity environments. The phone's local storage and database cannot depend on network roundtrips:

- **Local SQLite (via Drift)** is the authoritative source of truth: templates, inspections, items, attachment metadata, and sync outbox state live on-device. All UI reads stream directly from reactive Drift DAOs.
- **The PocketBase server** is an optional cloud backup and synchronization target. The app is 100% operational without an account or an internet connection.
- **Write order:** Local SQLite transaction first (durable intent), outbox queue second (if signed in). A network failure never rolls back or halts a local inspection.

The failure matrix is asymmetric and dictates the engine design:

| Divergence | Harm | Handling |
|---|---|---|
| In local SQLite, not yet in PocketBase | None (offline mode or queueing) | Queued in outbox; two-lane sync engine drains automatically upon reconnect |
| Concurrent remote edit arrives | Low (LWW model) | Server clamps future clocks; responds 409 `stale_write` to older mutations |
| Outbox row exists without local file | High (media upload failure) | Upload scheduler detects missing file, parks operation with `fileMissing` status |

### 2. Atomic Snapshots & In-Transaction Derivations

Inspections are permanent historical audit records. They must reflect exactly what was checked at the time of inspection, immune to future configuration edits:

- **Template Snapshotting:** Starting an inspection deep-copies template definitions into `inspection_items`. Editing, deleting, or reordering a checklist template tomorrow never mutates an active or completed inspection.
- **Transactional Summary Invariant:** Derived counters (`total_items`, `answered_items`, `pass_count`, `fail_count`, `na_count`) are recalculated and stored within the exact same database transaction as the item response write:

```dart
await db.transaction(() async {
  // 1. Persist item answer mutation
  await (update(inspectionItems)..where((tbl) => tbl.id.equals(itemId)))
      .write(InspectionItemsCompanion(
        response: Value(newResponse),
        respondedAt: Value(now),
      ));

  // 2. Atomically recompute and update inspection summary counts
  final counts = await _aggregateCounts(inspectionId);
  await (update(inspections)..where((tbl) => tbl.id.equals(inspectionId)))
      .write(InspectionsCompanion(
        answeredItems: Value(counts.answered),
        passCount: Value(counts.pass),
        failCount: Value(counts.fail),
        naCount: Value(counts.na),
        updatedAt: Value(now),
      ));
});
```

### 3. Resilient Two-Lane Sync & Evidence Context

Bulk media uploads should never starve or block lightweight record updates. Tickwalk runs two decoupled synchronization lanes:

- **Lane 1 (Records):** Strictly ordered by sequence (`seq`), enforcing parent-first topology (Template -> Inspection -> Item -> Attachment updates). Halts on retryable errors to maintain referential integrity.
- **Lane 2 (Media):** Multipart file uploads run concurrently (max 2 parallel streams) with per-file exponential backoff and jitter. A failed photo upload never impedes item answers.
- **Evidence Honesty:** Device clocks and GPS coordinates are context, not cryptographic proof. The app records device timestamp, GPS fix status (`fix`, `stale`, `none`, `denied`), horizontal accuracy in meters, and SHA-256 hash. Upon cloud arrival, the server sets a non-forgeable `received_at` timestamp. The generated PDF report explicitly details these boundaries.

---

## Additional Systems

- **Interruption & Camera-Kill State Machine:** Budget Android devices frequently terminate background activities when the system camera opens. Tickwalk records a `pending_capture` record in SQLite *prior* to launching the camera intent. On application cold start or resume, `retrieveLostData()` recovers the file and associates it with the waiting item.
- **Parallel GPS Fix:** Launching the camera triggers a concurrent 10-second high-accuracy GPS fix. If GPS takes longer than 10 seconds or signal is shielded, the pipeline falls back gracefully to `stale`, `none`, or `denied` without blocking the user.
- **Native Off-Thread Compression:** Images are compressed and thumbnailed (320px) via native platform bindings off the Dart main thread. Full-resolution bitmaps never enter Dart memory space, preventing garbage-collection frame drops during rapid inspections.
- **Outbox Write Coalescing:** Rapid offline toggles on the same item collapse into a single pending `update` operation. Transient items created and deleted offline are discarded from the outbox entirely.
- **Data-Aware Network Gating:** Users can enforce "Wi-Fi Only for Photos", keeping cellular data usage at zero while continuing to sync text records. An explicit "Upload current batch now" override lets supervisors force an upload when needed.
- **Offline PDF Generation & Signing:** Creates a self-contained, publication-ready PDF report containing company header, site summary, failed items evidence gallery with coordinates/timestamps, complete checklist audit table, and inspector signature pad graphic.

---

## System Architecture

```text
  Inspector Action (Offline or Online)
          │
          ▼
┌──────────────────────────────────────────────┐
│ UI Widgets & Riverpod Reactive Streams       │
└──────────────────────┬───────────────────────┘
                       │
       ┌───────────────┴───────────────┐
       ▼                               ▼
┌──────────────┐               ┌──────────────────────────────┐
│ Capture      │               │ Local Repositories           │
│ Pipeline     │               │ (Drift SQLite Transactions)  │
└──────┬───────┘               └──────────────┬───────────────┘
       │                                      │
       │ 1. Launch Camera + GPS in parallel   │ 1. Snapshot template into items
       │ 2. Native compress & SHA-256         │ 2. Write answer + update summary counts
       │ 3. Write photo files to disk         │ 3. If signed in: enqueue outbox
       ▼                                      ▼
┌──────────────────────┐               ┌──────────────────────────────┐
│ App Private Storage  │               │ Drift SQLite Local DB        │
│ (<app>/inspections/) │               │ (Source of Truth)            │
└──────┬───────────────┘               └──────────────┬───────────────┘
       │                                              │
       │                                ┌─────────────┴─────────────┐
       │                                ▼                           ▼
       │                    ┌──────────────────────┐    ┌──────────────────────┐
       │                    │ Outbox: Lane 1       │    │ Outbox: Lane 2       │
       │                    │ (Records, Ordered)   │    │ (Media, Parallel)    │
       │                    └──────────┬───────────┘    └──────────┬───────────┘
       │                               │                           │
       │                               │ HTTP JSON                 │ Multipart Stream
       │                               │ Strict parent-first       │ Max 2 concurrent
       ▼                               ▼                           ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ Optional PocketBase Cloud Backend (Hooks, Auth, Storage, Server received_at) │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```text
Tick-walk/
├── README.MD                           # Project overview & system architecture
├── docs/
│   ├── ARCHITECTURE.MD                 # Full system design, schema, and sync lanes
│   ├── PRD.MD                          # Product requirements & user stories
│   ├── DESIGN.MD                       # UI tokens, components, and interaction patterns
│   ├── STORY.MD                        # Engineering narrative, Medium tags & LinkedIn post
│   ├── DEMO.MD                         # Walkthrough script & recording guide
│   ├── CURSOR_CONTEXT.MD               # Engineering milestones & build instructions
│   └── tickwalk.postman_collection.json # 7-folder Postman API test suite
├── lib/
│   ├── main.dart                       # App entrypoint & global error boundary
│   ├── app.dart                        # MaterialApp, router config, and theme initialization
│   ├── core/
│   │   ├── clock/                      # Injectable system clock interface
│   │   ├── errors/                     # App-wide typed error taxonomy
│   │   ├── logger/                     # Structured logger & GlitchTip breadcrumbs
│   │   └── ids/                        # UUIDv4 client generation utilities
│   ├── domain/
│   │   ├── models/                     # Immutable domain entities
│   │   ├── template_schema.dart        # JSON schemaVersion 1 validator
│   │   └── validation.dart             # Pure completion validation function
│   ├── data/
│   │   ├── db/                         # Drift SQLite database, tables, DAOs & migrations
│   │   ├── repositories/               # Templates, inspections, items, attachments repos
│   │   ├── sync/                       # Outbox engine, record lane, media lane, scheduler
│   │   └── api/                        # PocketBase HTTP client, auth, and error mapper
│   ├── capture/
│   │   ├── capture_pipeline.dart       # Orchestrator: camera, GPS, compression, hashing
│   │   ├── gps_service.dart            # Geolocator integration with 10s parallel timeout
│   │   ├── compression_profiles.dart   # Native image resize & thumbnail calculator
│   │   └── recovery.dart               # Pending-capture crash recovery state machine
│   ├── reports/
│   │   └── pdf_builder.dart            # Offline PDF document generator with photo stamps
│   └── features/
│       ├── onboarding/                 # First-run inspector identity setup
│       ├── templates/                  # Starter templates & template editor
│       ├── inspections/                # Active & completed inspection lists
│       ├── checklist/                  # Sliver checklist screen, inputs & review blockers
│       ├── uploads/                    # Upload queue monitor, retry triggers & Wi-Fi toggle
│       └── settings/                   # Data usage, quality profiles & account backup
├── backend/
│   ├── PB_VERSION                      # Pinned PocketBase release version
│   ├── pb_hooks/                       # Server-side hooks (received_at, validation, 409 guard)
│   └── pb_migrations/                  # Auto-applied collection schemas
└── test/
    ├── domain/                         # Template parsing & completion validation tests
    ├── db/                             # Transactional summary recompute & Drift DAO tests
    ├── sync/                           # Outbox coalescing, scheduler & two-lane sync tests
    └── capture/                        # Crash recovery & GPS fallback tests
```

---

## Getting Started

### 1. Start Infrastructure via PocketBase (Optional)

```bash
cd backend
# Create superuser admin credentials
./pocketbase superuser create admin@tickwalk.io 'StrongPassword123!'
# Serve PocketBase locally
./pocketbase serve --http=0.0.0.0:8090
```

PocketBase Admin UI is accessible at `http://localhost:8090/_/`.

### 2. Configure Environment

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

| Target Device | API_URL in `.env` |
|---|---|
| Android Emulator | `http://10.0.2.2:8090` |
| iOS Simulator | `http://localhost:8090` |
| Physical Device (USB) | `http://localhost:8090` (after `adb reverse tcp:8090 tcp:8090`) |
| Physical Device (Wi-Fi) | `http://<your-computer-ip>:8090` |

### 3. Generate Drift Database Code

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 4. Run the Flutter App

```bash
flutter run
```

---

## API Capabilities

| Area | Method | Path | Auth | Purpose |
|---|---|---|---|---|
| **Health** | `GET` | `/api/health` | — | Backend liveness and health probe |
| **Auth** | `POST` | `/api/collections/users/auth-with-password` | — | Authenticate inspector and obtain JWT |
| **Templates** | `POST` | `/api/collections/templates/records` | Bearer Token | Push template record (Lane 1) |
| | `GET` | `/api/collections/templates/records` | Bearer Token | List user templates or starters |
| | `GET` | `/api/collections/templates/records/{id}` | Bearer Token | Retrieve single template schema |
| | `PATCH` | `/api/collections/templates/records/{id}` | Bearer Token | Update or soft-delete template |
| **Inspections**| `POST` | `/api/collections/inspections/records` | Bearer Token | Sync new inspection with cached summary |
| | `GET` | `/api/collections/inspections/records` | Bearer Token | List active/completed inspections |
| | `PATCH` | `/api/collections/inspections/records/{id}` | Bearer Token | Update status or notes (409 guard) |
| **Items** | `POST` | `/api/collections/inspection_items/records` | Bearer Token | Push snapshot item record (Lane 1) |
| | `GET` | `/api/collections/inspection_items/records` | Bearer Token | Query items for inspection |
| | `PATCH` | `/api/collections/inspection_items/records/{id}` | Bearer Token | Update answer response/severity/note |
| **Media** | `POST` | `/api/collections/attachments/records` | Bearer Token | Multipart upload photo with GPS (Lane 2) |
| | `GET` | `/api/collections/attachments/records/{id}` | Bearer Token | Inspect photo metadata & `received_at` |
| | `POST` | `/api/files/token` | Bearer Token | Request protected short-lived media token |
| **Pull Sync** | `GET` | `/api/collections/{col}/records?filter=...` | Bearer Token | Incremental pull ordered by `updated,id` |

---

## Core Performance Benchmarks & Targets

Measured on low-end reference hardware (Android 11, 2GB RAM, Quad-Core 1.8GHz):

| Metric | Target | Rationale |
|---|---|---|
| **Capture to Thumbnail Visible** | < 800 ms | Native background compression ensures camera shutter returns immediately |
| **Checklist 60-item Scroll** | 60 FPS | Sliver list with lazy thumbnail loading and scoped Riverpod item providers |
| **App Cold Start** | < 1200 ms | SQLite initial stream query directly to home screen with no network gate |
| **Photo Compression Ratio** | ~85% reduction | Standard profile reduces 4.2MB raw capture down to ~350KB (1600px, 75q) |
| **APK Release Footprint** | < 18 MB per ABI | Split APK per ABI with zero heavy third-party tracking or bloated UI kits |

---

## Test Suite

The automated test suite exercises each architectural invariant under edge-case conditions:

```bash
flutter test
```

| Test Class | Invariant Claim Verified |
|---|---|
| `TestTemplateSnapshotIsolation` | Modifying/deleting parent template never changes existing inspection items |
| `TestSummaryRecomputeConsistency` | Cache summary equals brute-force recompute across randomized answer sequences |
| `TestOutboxWriteCoalescing` | Multiple rapid item answers collapse into one; created-then-deleted records dropped |
| `TestCameraKillRecovery` | Restores `pending_capture` and re-attaches image retrieved via `retrieveLostData` |
| `TestGpsTimeoutFallback` | Exceeding 10s deadline stores `stale` or `none` without failing photo capture |
| `TestTwoLaneSyncOrdering` | Lane 1 guarantees parent inspection exists on server before Lane 2 uploads photos |
| `TestUploadSchedulerWifiGating` | Pauses photo queue on metered mobile data; allows batch override when toggled |
| `TestAttachmentIdempotentCreate` | Re-uploading attachment with existing UUID returns 200/verified record, not duplicate |
| `TestStaleWriteConflict409` | Server rejects outdated `client_updated_at` with 409 and client applies server record |
| `TestPdfReportEvidenceDisclaimer` | Generated PDF audit includes explicit unverified-timestamp legal notice |

---

## Postman Collection

A complete Postman test collection covering all sync endpoints, auth, cursor pulls, and validation edge cases is located in:

```text
docs/tickwalk.postman_collection.json
```

Run via the Newman CLI against a running PocketBase instance:

```bash
newman run docs/tickwalk.postman_collection.json \
  --env-var "baseUrl=http://localhost:8090" \
  --env-var "userEmail=inspector@tickwalk.io" \
  --env-var "userPassword=TestPass12345!"
```

---

## Design Decisions (Settled — Don't Relitigate)

1. **Local SQLite is the arbiter.** The local database holds the master copy; PocketBase is an optional backup. The UI never awaits remote sync.
2. **Template snapshot into inspection items.** Inspections are immutable historical audits; they copy template contents at instantiation time.
3. **In-transaction summary recalculation.** Counts are recalculated and saved within the exact same database transaction as the item response write.
4. **Camera-only evidence capture.** Direct camera capture prevents attaching unverified gallery photos from external sources.
5. **Native off-thread compression & thumbnails.** Images are compressed natively before entering Dart VM memory; full-resolution images are never decoded into Dart widgets.
6. **Two decoupled sync lanes.** Ordered record metadata runs sequentially in Lane 1; multipart photo uploads run concurrently in Lane 2.
7. **Client UUIDs & duplicate-as-success idempotency.** Retrying an upload with an identical client ID is safe and never creates duplicate records.
8. **Evidence stamps are context, not proof.** Timestamps and GPS coordinates can be spoofed on rooted phones. The system relies on server `received_at` as a corroborating indicator and documents this transparently.

---

## Known Limitations & Out of Scope (v1 Scope vs v2 Roadmap)

### MVP v1 Known Limitations
- Single user per local account; multi-inspector sharing occurs via exported PDF reports.
- Photos captured on another device display local placeholders until explicitly fetched.
- Whole-file upload retry without byte-level chunking (individual compressed photos average ~350 KB).
- Local SQLite database and cached photos are unencrypted at rest.

### Planned for Version 2 (v2)
- **Multi-Tenant Workspaces & RBAC:** Team dispatch, supervisor sign-offs, and compliance auditor roles.
- **Real-Time Collaborative Walk-Rounds:** Simultaneous inspections across different floors using CRDTs.
- **Geofencing & Offline Map Overlays:** Site boundary verification and interactive offline finding pins.
- **On-Device Computer Vision ML:** Automated safety violation detection (missing helmets, blocked fire hoses).
- **Resumable Chunked Uploads:** Support for multi-megabyte high-resolution imagery and video evidence.

---

## Documentation

| Document | Purpose |
|---|---|
| [docs/PRD.MD](docs/PRD.MD) | Product requirements, user stories & acceptance criteria |
| [docs/ARCHITECTURE.MD](docs/ARCHITECTURE.MD) | Deep-dive architectural specs, schemas, and sync lane algorithms |
| [docs/DESIGN.MD](docs/DESIGN.MD) | Design system tokens, interaction patterns, and outdoor accessibility |
| [docs/STORY.MD](docs/STORY.MD) | Engineering narrative, Medium tags, LinkedIn post & interview talking points |
| [docs/DEMO.MD](docs/DEMO.MD) | Video demo script and recording walkthrough |
| [docs/CURSOR_CONTEXT.MD](docs/CURSOR_CONTEXT.MD) | Build plan, sprint milestones, and agent guidelines |
| [docs/tickwalk.postman_collection.json](docs/tickwalk.postman_collection.json) | Comprehensive 7-folder API verification test suite |

---

## License

MIT licensed. Engineering design and implementation architecture.
