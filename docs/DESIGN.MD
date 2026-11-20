# Tickwalk: Design

## 1. Design goals

1. **Usable outdoors, one-handed, possibly with gloves.** High contrast, big targets, minimal typing.
2. **Evidence in two taps.** Failing an item and attaching a photo must be the fastest path in the app.
3. **Never lose work.** Autosave, recover from camera interruptions, and always show what is safe on the phone and what is uploaded.
4. **Honest about state.** Upload status is visible per photo, in plain language, with no silent failures.
5. **Light on data and low-end phones.** Compressed photos, thumbnails in lists, system fonts.

## 2. Patterns replicated from top apps

| Pattern | Seen in | How Tickwalk uses it | Why it works |
|---|---|---|---|
| Template-driven inspections with Pass, Fail, N/A | SafetyCulture (iAuditor) | Segmented answer buttons per item | Fast to scan and complete |
| Fail triggers evidence | Inspection apps | Failing an item expands note and photo controls | Evidence is captured at the moment of finding |
| Timestamp and location camera overlays | Timestamp-camera apps | Metadata chip on every photo; stamp burned into the PDF | Findings are traceable |
| Message status ticks | WhatsApp | Photo state icons: clock (waiting), spinner (uploading), check (uploaded), alert (failed) | Familiar, glanceable delivery state |
| Backup status and "waiting for Wi-Fi" | Google Photos, Drive | Uploads tab and banner with counts and reason | Explains why nothing is happening |
| Progress bar with counts | Checklist apps | Header shows "12 of 20, 2 failed" | Gives a finish line |
| Undo toast instead of confirm | Gmail | Photo or item removal shows "Removed. Undo" | Fast and recoverable |
| Contextual permission request | Mobile best practice | Location permission asked when starting the first inspection, with a plain reason | Higher grant rates |
| Skeletons only where the network is unavoidable | Instagram | Only during the first pull on a new device | Local reads are instant |

## 3. Design tokens

All colors are targets; confirm contrast with a checker before release. Expose through a `ThemeExtension`; widgets never use raw colors.

### Color (light)

| Token | Hex | Use | Approx. contrast |
|---|---|---|---|
| `bg` | `#F4F6F8` | Screen background | n/a |
| `surface` | `#FFFFFF` | Cards, sheets | n/a |
| `text` | `#111827` | Primary text | about 15:1 on bg |
| `textSecondary` | `#4B5563` | Secondary text | about 7:1 on bg |
| `primary` | `#0B5CAD` | Buttons, active states | about 6.7:1 with white text |
| `primaryPressed` | `#084A8C` | Pressed | higher |
| `accent` | `#F5B301` | Highlights (use with dark text `#1A1A1A`) | about 10:1 with dark text |
| `pass` | `#15803D` | Pass state | about 5:1 on white |
| `fail` | `#B91C1C` | Fail state | about 6.5:1 on white |
| `na` | `#4B5563` | N/A state | about 7:1 on white |
| `warning` | `#92400E` | Waiting, no GPS, stale | about 7:1 on white |
| `border` | `#D1D5DB` | Dividers | decorative |

### Color (dark)

| Token | Hex |
|---|---|
| `bg` | `#0F1419` |
| `surface` | `#18202A` |
| `text` | `#F3F4F6` |
| `textSecondary` | `#9CA3AF` |
| `primary` | `#60A5FA` (use `#0F1419` text on it) |
| `accent` | `#FBBF24` |
| `pass` / `fail` / `na` / `warning` | `#4ADE80` / `#F87171` / `#9CA3AF` / `#FBBF24` |
| `border` | `#2A3441` |

Result states always combine color with an icon and a text label (check "Pass", cross "Fail", dash "N/A").

### Typography (system fonts)

| Style | Size / line height | Weight |
|---|---|---|
| Title | 28 / 34 | Bold |
| Heading | 20 / 26 | Semibold |
| Item prompt | 17 / 24 | Medium |
| Body | 16 / 22 | Regular |
| Label | 14 / 20 | Medium |
| Caption | 13 / 18 | Regular |

Item prompts wrap up to 4 lines at normal scale and must remain readable at 200% text scale.

### Spacing, shape, motion

| Token | Value |
|---|---|
| Spacing scale | 4, 8, 12, 16, 24, 32 |
| Screen horizontal padding | 16 |
| Minimum touch target | 48 x 48 (answer buttons 56 high) |
| Radius | 12 (cards, inputs), 999 (chips) |
| Motion | 120 ms taps, 200 ms layout, 250 ms sheets, ease-out |

## 4. Information architecture

```text
Onboarding (first run): inspector name, starter templates
Main tabs
  Inspections (In progress, Completed)
    New inspection (sheet)
    Checklist
      Photo viewer
      Review and finish
    Inspection detail (completed): report, reopen
  Templates
    Template editor
  Uploads (queue and sync center)
  Settings
    Account (sign in)
```

Rules: four tabs with a badge on Uploads when items are waiting; any screen within 3 taps; back always pops one level; leaving a checklist never loses data.

## 5. Screen specifications

### S1. Onboarding
- One screen: pitch, inspector name field (used in reports), "Add starter templates" toggle on, Start button. No account prompt, no permission prompt.

### S2. Inspections
- Segmented: In progress, Completed
- Card: template name, site name, progress "12 of 20", fail count chip, upload chip ("3 photos waiting", "Uploaded"), date
- FAB: New inspection
- Empty state: "No inspections yet. Start your first walk-round." with a button

### S3. New inspection (sheet)
- Template picker, site name (with recent sites as chips), optional site address, inspector name (prefilled)
- "Use current location for this site" switch (default on); permission explained and requested here
- Start button creates the inspection and a GPS fix runs in the background (non-blocking)

### S4. Checklist
- Header: template and site, progress bar, counts (pass, fail, N/A), GPS badge for the start fix
- Sections as expandable groups with per-section progress
- Item row: prompt; for pass/fail items three 56 dp buttons Pass, Fail, N/A; text and number items show an inline field
- On Fail: panel expands with note field, severity chips (P1: Low, Medium, High), photo strip with an Add photo button, and a "Photo required" badge if the item demands it
- Photos: 72 dp thumbnails with a status icon; tap opens the viewer
- Bottom bar: "Review and finish" with a count of blockers
- States: nothing answered, in progress, all answered, completed (read-only banner "Completed. Reopen to edit.")

```text
+------------------------------------------+
| < Site safety walk          GPS +-8 m    |
| Yard B                                   |
| [#########-----] 12 of 20   2 failed     |
+------------------------------------------+
| ACCESS AND HOUSEKEEPING          3/3     |
| Walkways and access routes are clear     |
| [ Pass ] [ FAIL ] [ N/A ]                |
|   Note: Pallets blocking east gate       |
|   Photo required                         |
|   [img +clock] [img +check] [ + Photo ]  |
| ...                                      |
+------------------------------------------+
| 3 things to finish        Review and finish |
+------------------------------------------+
```

### S5. Photo capture
- Add photo launches the system camera (camera source only by default); a GPS fix starts at the same moment
- On return: thumbnail appears immediately with a clock icon; compression and hashing happen off the main thread
- Errors: camera cancelled (nothing happens), storage full ("Not enough space to save the photo"), compress failure (keeps the original and shows a size note)

### S6. Photo viewer
- Full photo (pinch to zoom), caption field, metadata panel: captured time, coordinates with accuracy ("+-8 m") or "No GPS (permission off)" / "Approximate (last known)", size, short hash, upload state
- Actions: Delete (undo toast), Share stamped copy (P2)

### S7. Review and finish
- Summary counts, list of blockers with jump links ("Unanswered: Fire extinguisher", "Photo needed: Walkways")
- Failed items list with thumbnails
- Signature pad (P1) and a Complete button, enabled only when there are no blockers
- Completion locks editing

### S8. Inspection detail (completed)
- Summary, failed items, upload status per photo, Share PDF report (P1), Reopen (records that it was reopened)

### S9. Templates
- List: starter and mine; duplicate, edit, delete (undo)
- Editor: name, description, sections (add, reorder, delete), items (prompt, type: Pass/Fail, Text, Number with optional unit, required, photo required on fail)
- Starter templates are editable copies

### S10. Uploads
- Summary: records waiting, photos waiting, estimated MB, connection type
- Banner states: Uploading, Waiting for Wi-Fi, Offline, All caught up, Problem
- Controls: Upload now over mobile data (one batch), Retry failed, Wi-Fi only switch
- List: each photo with thumbnail, inspection name, state (waiting, uploading, uploaded, failed with reason in plain language), Retry for failed
- Empty: "Everything is uploaded."

### S11. Settings
- Inspector name, theme, photo quality (Low data, Standard, High) with sizes explained, Wi-Fi only for photos, allow gallery import (off), storage used, account, About

### S12. Account
- Optional sign in or sign up; copy: "Optional. Your inspections stay on this phone unless you sign in."
- Different-account prompt as described in the PRD

## 6. Widget inventory

`AppScaffold`, `ProgressBar`, `InspectionCard`, `SectionHeader`, `ChecklistItem`, `AnswerButtons`, `SeverityChips`, `PhotoStrip`, `PhotoThumb` (with status icon), `GpsBadge`, `UploadStatusChip`, `BlockerList`, `SignaturePad` (CustomPainter), `TemplateItemEditor`, `EmptyState`, `Toast` (SnackBar with action), `BottomSheet`, `Skeleton`, `ErrorFallback`. All take tokens from the theme extension.

## 7. Upload states

| State | Icon | Label |
|---|---|---|
| Waiting | clock | "Waiting" (or "Waiting for Wi-Fi") |
| Uploading | spinner | "Uploading" |
| Uploaded | check | "Uploaded" |
| Failed (will retry) | alert with clock | "Retrying soon" |
| Failed (needs action) | alert | Plain reason: "File too large", "File missing on this phone" |

## 8. Motion and haptics

- Answer buttons: 120 ms fill and `HapticFeedback.selectionClick`; Fail uses `lightImpact`
- Fail panel expands in 200 ms
- Photo thumbnail fades in 150 ms
- Respect `MediaQuery.disableAnimations`

## 9. Accessibility

- Every control has `Semantics` with label, role and state; answer buttons read as "Walkways clear: Fail, selected"
- Targets at least 48 dp (answer buttons 56 dp); 8 dp spacing
- Contrast at least 4.5:1 for text and 3:1 for icons; results never rely on color alone
- Layout holds at 200% text scale
- Photos have captions as accessible descriptions when present, otherwise "Photo for {item}"
- Signature pad has a typed-name alternative

## 10. Microcopy

| Situation | Copy |
|---|---|
| Empty inspections | "No inspections yet. Start your first walk-round." |
| Location permission reason | "Tickwalk stamps photos with where they were taken. Location is used only when you take a photo or start an inspection." |
| Permission denied | "Location is off. Photos will be saved without a GPS stamp." |
| Waiting on Wi-Fi | "3 photos are waiting for Wi-Fi. Upload now over mobile data?" |
| Offline | "You're offline. Everything is saved on this phone and will upload later." |
| Blocker | "Photo needed: Walkways and access routes are clear" |
| Photo removed | "Photo removed. Undo" |
| File missing | "This photo's file is missing on this phone, so it can't upload." |
| Reopen | "Reopen this inspection? It will be marked as reopened." |
| Different account | "This phone has data from another account. Replace it with this account's data, or cancel?" |

Tone: short, calm, plain. No jargon like "outbox" in the UI.

## 11. Low-end device considerations

- Never decode full-resolution images in Dart; use native compression and `cacheWidth` for previews
- Lists show 320 px thumbnails only; the full photo loads in the viewer
- `ListView.builder` with section slivers; memoize item rows
- Limit concurrent uploads to 2 and photo processing to 1 at a time
- Defer sync boot, GPS warm-up and report assets until after the first frame
- Test on a phone with 3 GB RAM or less with a 60-item, 40-photo inspection