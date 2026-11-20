# Title: Offline-First Is a Concurrency Problem in Disguise — How Tickwalk Survives Zero-Signal Field Inspections

---

**Medium Tags:** `#flutter` `#offlinefirst` `#mobiledevelopment` `#softwarearchitecture` `#sqlite`

**LinkedIn Hashtags:** `#Flutter` `#Dart` `#MobileDev` `#OfflineFirst` `#SoftwareArchitecture` `#SQLite` `#PocketBase` `#DistributedSystems` `#FieldTech` `#TechLeadership`

---

## Short version (LinkedIn Post)

Site inspection walk-rounds almost always happen where connectivity fails: basement boiler rooms, concrete shafts, or rural substations. Most inspection apps either freeze when signal drops, or dump hundreds of megabytes into a silent upload failure.

For Project 4 of my portfolio (Tickwalk), I built an offline-first mobile inspection engine in Flutter & Drift (SQLite) with an optional PocketBase sync backend. Three key engineering lessons from building it:

1. **Snapshots, Not References:** Modifying an inspection template must never mutate past inspections. Starting an inspection deep-copies template items into an immutable inspection snapshot. Changing a safety rule tomorrow won't quietly rewrite history from last month.
2. **The Camera-Kill Problem on Low-RAM Devices:** Opening the native camera on a budget Android phone frequently triggers OS low-memory process termination. If your app is killed, the captured photo is lost. I solved this with an interruption state machine: persist a `pending_capture` record to disk *before* launching the camera intent, then recover lost picker data on resume and attach it safely to the originating checklist item.
3. **Two-Lane Sync Architecture:** Never mix ordered metadata and bulky media in a single queue. Tickwalk runs two decoupled sync lanes:
   - **Lane 1 (Records):** Strictly ordered JSON operations (parents before children) with outbox coalescing (rapid edits collapse to the latest state).
   - **Lane 2 (Media):** Parallel multipart uploads (bounded concurrency of 2) with per-file exponential backoff, SHA-256 hashing, and "Wi-Fi Only" data gating.

Evidence stamps (device time, GPS accuracy, server `received_at`) are treated honestly: they provide context, not tamper-proof cryptographic proof, and the auto-generated PDF report states that limitation upfront.

GitHub repository: <your-repo-link>

---

## Medium Article Outline & Publishing Angle

### Working Title
**Offline-First Is Not Just "Caching": Building a Crash-Proof Mobile Inspection Pipeline in Flutter**

### Core Narrative Arc
- **The Hook:** The nightmare of the "silent upload failure": an inspector spends 3 hours walking a sub-basement, drives home, and finds out none of the 45 photos saved because the app assumed a continuous WebSocket.
- **The Core Tension:** Local SQLite vs. Remote Cloud. Why local SQLite must be the absolute arbiter of state, and why the UI must never await an HTTP roundtrip.
- **Deep Dive 1: Surviving the Android Camera Kill.** Walking through the lifecycle: `pending_capture` persistence -> `retrieveLostData()` on Flutter cold boot -> re-attaching orphaned files.
- **Deep Dive 2: Two-Lane Sync & Write Coalescing.** Why a single FIFO queue causes head-of-line blocking when a 5MB photo stalls behind an answer update.
- **Honest Framing on Evidence:** Why device clocks and GPS can be spoofed, how server `received_at` provides a verifiable second anchor, and why transparent disclaimers build more user trust than false claims of "unhackable timestamps".

---

## The problem

A supervisor walks a site with a checklist on paper, takes photos with the phone camera, and sends them to a chat group at the end of the day, if there is signal. Later nobody can say which photo goes with which finding, when it was taken or where. Checklists get rewritten from memory. Data runs out uploading big photos. In a basement or rural area the app that needs a connection simply does not work.

The inspection itself is not hard. Keeping the evidence attached to the right item, on a phone with no signal, without losing anything, is the hard part.

## Who it's for

- **The site supervisor or safety officer:** needs a fast, repeatable walk-round with proof of findings.
- **The facility or property manager:** needs consistent checks (generator room, move-in condition) with photos and a report to share.

*(Validation note, fill in after talking to 2 or 3 people who do inspections: what they use today, how they send evidence, what goes wrong.)*

## Honest framing

Inspection apps already exist and are mature, SafetyCulture being the best known. Tickwalk is not trying to out-feature them. It is a vehicle for demonstrating the hard parts of field apps: an offline media pipeline, a queue that uploads large files over unreliable networks without losing or duplicating anything, and honest status for the user. Cradlepath and Skillkiln later reuse these patterns. I say that plainly in interviews.

## What I set out to prove

1. I can build a photo pipeline that is fast on low-end phones: native compression, thumbnails, no full-resolution decoding in Dart.
2. I can make capture robust: GPS fix in parallel with the camera, recovery when the OS kills the app during capture.
3. I can design an upload queue with two lanes, ordered records and parallel media, with per-file retry, Wi-Fi gating and idempotent creates.
4. I can keep derived data (inspection summary counts) consistent in the same transaction as the writes.
5. I can model templates versus inspections correctly with snapshots, so history never changes when templates do.
6. I am honest about evidence: stamps are context, not proof, and the product says so.

## Key decisions

| Decision | Why |
|---|---|
| Template snapshot into inspection items | Editing a template must never change completed inspections |
| Template stored as one JSON document | One editable unit, simple sync, schema version for evolution |
| Camera-only capture by default (image_picker) | Reduces misuse of old photos; far simpler than a custom camera |
| Native compression and thumbnails, EXIF stripped | Fast on low-end phones; location metadata kept in the database, not leaked in shared files |
| Metadata in the database, stamp burned into the PDF | Photos stay clean; the report carries visible evidence |
| Photo pending-capture record and lost-data recovery | Low-RAM phones can kill the app while the camera is open |
| Two sync lanes (records ordered, media parallel) | Records need ordering; photos should not block each other |
| Client IDs and idempotent multipart create | A retried upload cannot create a duplicate |
| Wi-Fi only for photos, with "upload now" | Data costs are real; the user stays in control |
| Whole-file retry, no chunking | Files are a few hundred KB; resumable upload is Skillkiln's job |
| Server records `received_at` | A second timestamp the device cannot set |
| Optional account | Time-to-value first; same pattern as my previous projects |

## What happened (fill in after the build)

- Built in: __ hours over __ days
- Measured on [device] in profile mode: capture to thumbnail visible __ ms; checklist scroll with 60 items __ ; cold start __ ms; APK per ABI __ MB
- Compression: average photo __ MB before, __ KB after on the Standard profile
- Airplane-mode test: __ photos queued offline, __ uploaded, __ lost, __ duplicated
- Camera-kill recovery test: result
- Bugs worth telling: (the capture, GPS or upload edge case that surprised you)
- What I would change: (honest list)

## What I'd do next

Team workspaces and reviewers, on-demand photo download on other devices, chunked resumable uploads, an offline map of findings, encryption at rest, and a Go or Python backend on Postgres.

## Interview pitch (2 minutes)

"Tickwalk is an offline-first inspection app. A template is copied into the inspection as a snapshot, answers autosave to SQLite, and summary counts are recomputed in the same transaction. Photos go through a pipeline: the camera opens while a GPS fix runs in parallel, the image is compressed natively, hashed, thumbnailed and recorded with time, coordinates and accuracy. If the OS kills the app while the camera is open, a stored pending-capture record lets me recover the photo on restart. If the user signs in, a sync engine runs two lanes: records upload in strict order, and photos upload two at a time with per-file backoff, Wi-Fi gating and client-generated IDs so retries are idempotent. The server adds its own receive time. I'm explicit that the stamps are context and not tamper-proof."

## Likely deep-dive questions

| Question | Short answer |
|---|---|
| Why a snapshot of the template? | Inspections are records of what was checked at the time. Referencing a mutable template would rewrite history. |
| How do you keep photos from slowing the phone? | Native compression off the main thread, 320 px thumbnails for lists, one image processed at a time, no full-resolution decode in Dart. |
| What if the OS kills the app during capture? | Before opening the camera I persist where the photo belongs. On restart I ask the picker for lost data and attach it to that item. |
| Why two sync lanes? | Records have dependencies and need order. Photos are independent, large and slow, so they run in parallel with their own retry timers and do not block records. |
| How do you avoid duplicate uploads? | The attachment ID is generated on the device and used as the server record ID. A duplicate create returns the existing record and is treated as success. |
| Why not resumable uploads? | Photos are a few hundred KB after compression, so whole-file retry is acceptable. Resumable chunking is a later project because it needs server support. |
| Are the stamps trustworthy? | Not on their own. Device time and GPS can be faked. The server receive time and file hash add context. The report states the limits. |
| Why strip EXIF? | Shared files would leak precise location. Metadata is kept in the database and shown in the report instead. |
| What about data costs? | Compression profiles, Wi-Fi only mode and an "upload now" override with an estimated size. |
| How would you add teams? | Add a workspace owner field and membership rules in the API; the client's outbox and merge logic stay the same. |
