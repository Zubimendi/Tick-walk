# Tickwalk: Demo Guide

## Goals

- A 90 to 120 second recorded demo for the README and portfolio
- A 5 minute live version for interviews
- Prove three things: an inspection is fully usable offline, evidence is captured and stamped, and uploads are queued, visible and safe

## Setup (the evening before)

| Item | Detail |
|---|---|
| Phone | A real phone is strongly recommended (camera and GPS); emulators fake both |
| Photos | Take real photos of harmless subjects (a corridor, an extension cord, a fire extinguisher). No faces, number plates or private property details |
| Demo data | A dev-only "Load demo data" action (absent from release builds) that creates one completed inspection with fictional text |
| Templates | Starter templates loaded |
| Backend | PocketBase running and reachable over Wi-Fi; admin UI open on a laptop to show files arriving |
| Network control | Airplane mode toggle; mobile data off for the Wi-Fi-only segment |
| Recording | Android built-in recorder or `adb shell screenrecord` (note: camera apps may not appear in a screen recording on some phones; record the in-app parts and the result) |
| Cleanup | Notifications cleared, battery above 50%, location on |

## 90 second script

| Time | Screen | Action | Voiceover |
|---|---|---|---|
| 0:00 | Inspections | Show the list and an upload chip | "Tickwalk is an offline-first inspection app with photo and GPS evidence." |
| 0:08 | New inspection | Pick the safety template, enter the site, Start | "A template is copied into the inspection, so later edits never change it." |
| 0:16 | Phone | Turn on airplane mode | "I'm offline. Nothing changes for the inspector." |
| 0:20 | Checklist | Tap Pass on two items, Fail on one | "Every answer is saved instantly." |
| 0:30 | Checklist | On the failed item, tap Add photo, take a photo | "A failed item needs a photo. The camera opens while a GPS fix runs in parallel." |
| 0:42 | Checklist | Show the thumbnail with a clock icon and GPS badge | "The photo is compressed, hashed, stamped and queued, all in one step." |
| 0:50 | Photo viewer | Show metadata (time, coordinates, accuracy, size) | "Time, location with accuracy and a file hash." |
| 0:58 | Review | Open Review and finish, show a blocker, fix it, Complete | "The review screen says exactly what is missing." |
| 1:08 | Uploads | Show "5 photos waiting, offline" | "Nothing is lost. The queue shows exactly what is waiting." |
| 1:14 | Phone | Turn on Wi-Fi; watch items go clock, spinner, check | "On Wi-Fi they upload on their own, two at a time." |
| 1:24 | Laptop | Show the PocketBase admin with the files and receive times | "The server adds its own receive time." |
| 1:32 | Detail | Share the PDF report | "And a PDF report with the failed items and their photo evidence." |

## Failure demos (live version)

1. **Kill during capture:** open the camera, force-stop the app from recents, reopen; the photo is recovered and attached to the right item.
2. **Kill during upload:** force-stop while a photo uploads; reopen; it retries and the server shows one record, not two.
3. **Wi-Fi only:** turn off Wi-Fi with mobile data on; Uploads shows "Waiting for Wi-Fi" and offers "Upload now over mobile data".
4. **No GPS:** deny location; capture a photo; it saves with "No GPS (permission off)" and nothing breaks.

## Evidence honesty (say it out loud)

"These stamps are context, not proof. A device clock or GPS can be faked, so the server also records its own receive time and the file hash, and the report says this."

## Shots to capture for the README

1. Checklist with a failed item and photo strip
2. Photo viewer with metadata
3. Uploads tab with mixed states
4. Review screen with blockers
5. PDF report page
6. Dark theme checklist

## Turning the recording into a GIF

```bash
ffmpeg -i demo.mp4 -vf "fps=12,scale=360:-1:flags=lanczos" -loop 0 demo.gif
```

Keep the GIF under about 8 MB; keep the full MP4 for the portfolio site.

## Pre-demo checklist

- [ ] Real phone with location on and permissions granted
- [ ] Backend reachable over Wi-Fi; admin UI open
- [ ] Airplane mode and Wi-Fi toggles tested
- [ ] Demo photos are harmless and fictional context only
- [ ] 10 second test recording done
- [ ] Fallback video ready

## If something breaks live

Say what you expect, open the Uploads tab (it reports what the app thinks is happening), and switch to the recorded demo.