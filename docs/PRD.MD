# Tickwalk: Product Requirements Document

| Field | Value |
|---|---|
| Owner | Francis Offiong |
| Status | Draft v1 |
| Track | Mobile portfolio, Week 2, Project 4 |
| Stack | Flutter (Dart 3) |
| Build window | Fri 20 Nov to Sat 21 Nov 2026 (adjust if different) |
| Target ship | Sat 21 Nov 2026, 11 PM (hard stop) |

## 1. Summary

Tickwalk lets inspectors run checklist walk-rounds fully offline, capture photo evidence stamped with time and GPS, and upload everything later through a visible, safe queue. An optional account backs up records and photos, and a PDF report can be shared.

## 2. Problem

Field inspections happen where signal is poor and are recorded on paper or as loose photos in chat apps, with no reliable link between a finding, its photo, its time and its place. Large photos burn mobile data and uploads fail silently. (Validate with 2 or 3 inspectors or facility managers before or during the build.)

## 3. Users

| Persona | Needs |
|---|---|
| Site supervisor or safety officer | Repeatable checklist, fast evidence capture, a report to send |
| Facility or property manager | Consistent checks with photos and history |

## 4. Goals and non-goals

**Goals**
- G1. A complete inspection works offline with no account
- G2. Photo capture is fast, stamped (time, GPS with accuracy) and survives interruptions
- G3. Uploads are queued, visible, retried and never duplicated
- G4. Template edits never change past inspections
- G5. Data-aware: compressed photos and optional Wi-Fi only uploads
- G6. Smooth on a low-end Android phone

**Non-goals**
- Teams, reviewer roles, assignments
- Custom camera UI, video, annotation drawing
- Offline maps, geofencing, continuous location tracking
- Regulatory compliance claims; starter templates are samples
- Encryption at rest

## 5. Scope and priorities

| Priority | Items |
|---|---|
| **P0** (must ship) | Onboarding; starter templates; inspections list; new inspection with site; checklist with pass/fail/NA, text and number items, notes, required rules, autosave and summary counts; photo capture with GPS stamp, compression, thumbnails, hashing, recovery from camera kill; photo viewer with metadata; review and completion validation; read-only completed state; optional account; record sync lane; media upload lane with per-file retry, Uploads tab and status; empty and error states; docs |
| **P1** (should ship) | PDF report with photo evidence and share; signature pad; Wi-Fi only for photos with "Upload now"; severity on failed items; template create and edit; dark theme; background upload (Android); photo quality profiles |
| **P2** (if time allows) | Dev demo-data loader; share stamped photo; storage usage and cleanup; on-demand photo download on another device; JSON export |

**Cut order if behind schedule:** signature pad, then dark theme, then severity, then background upload, then template editor (keep starter templates and duplicate), then PDF report. Never cut photo capture with GPS stamps or the upload queue. If account sync is not finished, ship local-only and say so in Known limitations.

## 6. User stories and acceptance criteria

| ID | Story | Acceptance criteria | Pri |
|---|---|---|---|
| US-01 | As a new user, I can start without an account | First launch asks for an inspector name only; no signup, no permission prompt | P0 |
| US-02 | I get starter templates | Three editable sample templates appear on first run | P0 |
| US-03 | I can start an inspection | Choose template, enter a site name, Start; the template is copied into inspection items | P0 |
| US-04 | Template edits do not change past inspections | Edit a template after an inspection exists; the inspection is unchanged | P0 |
| US-05 | I can answer items | Pass, Fail, N/A buttons; text and number items; changes persist instantly and offline | P0 |
| US-06 | I can add a note to an item | Note saved with the item | P0 |
| US-07 | Failing an item can require a photo | Items flagged "photo required on fail" show a badge and block completion until a photo exists | P0 |
| US-08 | I can capture a stamped photo | Camera opens, GPS fix runs in parallel, thumbnail appears quickly, photo is saved with time, coordinates and accuracy (or a clear no-GPS reason) | P0 |
| US-09 | Photos are compressed | Longest edge and quality follow the chosen profile; EXIF is stripped; original temp file removed | P0 |
| US-10 | Capture survives interruptions | Killing the app while the camera is open, then reopening, attaches the photo to the right item | P0 |
| US-11 | I can view and delete photos | Viewer shows metadata; delete has an undo toast | P0 |
| US-12 | I can see progress | Header shows answered count, pass, fail and N/A counts, always consistent with items | P0 |
| US-13 | Completion is validated | Review lists blockers (unanswered required items, missing required photos) with links; Complete enabled only when none remain | P0 |
| US-14 | Completed inspections are read-only | Editing is locked; Reopen is explicit and recorded | P0 |
| US-15 | I can browse inspections | In progress and Completed lists with progress, fail count and upload status | P0 |
| US-16 | I can sign in to back up | Optional; local data uploads; app stays fully usable without it | P0 |
| US-17 | Records sync in order | Templates, inspections and items sync before their photos; retries use backoff | P0 |
| US-18 | Photos upload safely | Queued, two at a time, per-file retry; a retry never creates a duplicate record; killing the app mid-upload loses nothing | P0 |
| US-19 | I can see what is uploaded | Uploads tab shows per-photo state, counts and reasons; Retry for failed | P0 |
| US-20 | I control mobile data use | Wi-Fi only setting; waiting photos explain why; Upload now over mobile data for the current batch | P1 |
| US-21 | I can produce a PDF report | PDF with header, summary, failed items with photos and stamps, full checklist, signature and an evidence disclaimer; shared via the share sheet | P1 |
| US-22 | I can sign the report | Signature pad (or typed name) stored with the inspection | P1 |
| US-23 | I can set severity on failed items | Low, Medium, High chips; shown in report | P1 |
| US-24 | I can create and edit templates | Sections, items, types, required, photo on fail; duplicate and delete with undo | P1 |
| US-25 | Uploads can run in the background | Periodic task uploads queued items when conditions allow (Android; best effort on iOS) | P1 |
| US-26 | I can choose photo quality | Low data, Standard, High profiles with estimated sizes | P1 |
| US-27 | Accounts never mix silently | Signing in as a different account than the local data's owner prompts to replace or cancel | P0 |
| US-28 | The app is accessible | Semantics, 48 dp targets (answer buttons 56 dp), 200% text scale, reduce motion | P0 |
| US-29 | I can demo with fictional data | Dev-only loader absent from release builds | P2 |

## 7. Functional requirements

- FR-1. Every read comes from local SQLite via Drift streams; no screen blocks on the network
- FR-2. Starting an inspection copies the template into `inspection_items` in one transaction
- FR-3. Every item answer change recomputes the inspection's cached counts in the same transaction
- FR-4. A photo is recorded (file, thumbnail, hash, stamps, attachment row, outbox row if signed in) in one transaction after the files exist on disk
- FR-5. Before launching the camera, persist a pending-capture record; clear it after the photo is saved or cancelled
- FR-6. GPS fix: request on capture start with a 10 s limit; store status `fix`, `stale`, `none` or `denied` with accuracy and fix time
- FR-7. IDs are generated on the client; deletes are soft (tombstones)
- FR-8. Sync lane 1 (records) is strictly ordered and stops on retryable errors; lane 2 (photos) runs up to 2 uploads in parallel with per-file backoff
- FR-9. Photo uploads use the attachment ID as the server record ID; a duplicate create is treated as success after a GET
- FR-10. Tokens are stored in secure storage
- FR-11. API rules restrict each user to their own records

## 8. Non-functional requirements

| Area | Requirement (targets, measure in profile or release mode on a low-end Android phone) |
|---|---|
| Capture | Thumbnail visible within 1.5 s of returning from the camera |
| Autosave | Item answer reflected in UI under 100 ms |
| Frames | Under 1% of frames over budget scrolling a 60-item checklist with 40 photos |
| Startup | Cold start to first interactive frame under 2 s |
| Size | Release APK per ABI under 30 MB |
| Photo size | Standard profile averages under 500 KB per photo (record the measured value) |
| Reliability | 0 lost or duplicated photos across the manual matrix |
| Offline | All P0 flows pass in airplane mode |
| Security | Token in secure storage; owner-scoped rules; protected file access; no secrets in repo |
| Privacy | No analytics SDKs; EXIF stripped; location used only at capture and inspection start; nothing leaves the phone unless the user signs in |
| Accessibility | WCAG AA contrast targets; Semantics labels; 200% text scale |

## 9. Success criteria

- [ ] Airplane-mode test: a 20-item inspection with 15 photos completes offline, then all 15 upload with 0 lost and 0 duplicated
- [ ] Camera-kill recovery test passes
- [ ] Upload-kill test passes (one server record per photo)
- [ ] Template snapshot test passes
- [ ] Summary consistency test passes (cached counts equal recomputation)
- [ ] Performance budgets and average photo size recorded in `story.md`
- [ ] All seven docs complete and the demo recorded

## 10. Schedule

| When | Work | Done when |
|---|---|---|
| Fri AM | Docs done, SDK and plugin check | `cursorcontext.md` ready for the agent |
| Fri midday | Scaffold, theme, Drift schema, utilities, template schema, validation with tests, starter templates | T1 to T8 pass |
| Fri PM | Inspections list, new inspection, checklist, autosave, summary recompute, review and completion | Full local inspection without photos |
| Fri evening | Capture pipeline: camera, GPS, compression, thumbnail, hash, viewer, recovery | A photo with stamps appears on an item on a real phone |
| Sat AM | Backend, auth, outbox record lane, media lane, Uploads tab | Records and photos reach the server; kill tests pass |
| Sat midday | PDF report, Wi-Fi only, signature, template editor (as time allows) | P1 items per the cut order |
| Sat PM | Tests, performance measurements, docs sync, demo | Everything recorded |
| Sat 11 PM | **Hard stop.** Unfinished items go to Known limitations | Shipped |

Sunday is the only slack before Week 3 (React Native) starts Monday. It is not planned work.

## 11. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Heaviest scope so far in the shortest window | Misses the ship date | Strict P0 first, cut order, local-only fallback |
| `image_picker` loses the result when Android kills the app | Lost photos | Pending-capture record and lost-data recovery, tested early on a real phone |
| Compression library resize semantics differ from expectations | Oversized or tiny photos | Verify with a test photo, assert output dimensions and size in a test |
| GPS slow or unavailable indoors | Missing stamps | 10 s limit, best-of fix, last-known fallback flagged as approximate, never block capture |
| PocketBase multipart create with a client-supplied ID | Upload design changes | Verify in the first backend task; fallback is a two-step create then file update |
| PDF generation runs out of memory with many photos | Crash | Downscale photos for the PDF, cap photos per failed item, build in an isolate |
| Storage fills up | Capture failures | Check free space before capture, clear error message |
| OEM battery managers block background upload | Uploads stall in the background | Foreground upload on open; background is best effort; Uploads tab explains |
| Dart sync port from Emberday not available | Time lost | Implement from the architecture spec; keep the engine small |

## 12. Assumptions and open questions

- Assumption: up to 60 items and 40 photos per inspection, under 500 inspections per user
- Assumption: one inspector per phone
- Question: should reopened inspections keep a visible history? (MVP: a counter and last reopened time)
- Question: should the PDF include every photo or only failed items? (MVP: failed items, up to 4 photos each)

## 13. Future

Team workspaces, on-demand photo download on other devices, chunked resumable uploads, offline maps, encryption at rest, Go or Python backend on Postgres.