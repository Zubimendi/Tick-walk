# Tickwalk PocketBase Backend

This directory contains the database migrations, access rules, and JavaScript hooks for the PocketBase backend supporting Tickwalk.

## Requirements
- PocketBase version: **0.22.22** (pinned in `backend/PB_VERSION`)

## Running Locally

1. Download PocketBase:
```bash
# Linux amd64
curl -L -o pocketbase.zip https://github.com/pocketbase/pocketbase/releases/download/v0.22.22/pocketbase_0.22.22_linux_amd64.zip
unzip pocketbase.zip -d backend/
chmod +x backend/pocketbase
```

2. Start the server:
```bash
./backend/pocketbase serve --http="0.0.0.0:8090" --dir="backend/pb_data" --migrationsDir="backend/pb_migrations" --hooksDir="backend/pb_hooks"
```

3. Open Admin UI at `http://127.0.0.1:8090/_/` and create the initial superuser admin.

## Collections & Rules
- `templates`: Checklist schema definitions.
- `inspections`: Site walks with progress, answers count, GPS fix, and status.
- `inspection_items`: Individual questions with pass/fail/notes.
- `attachments`: Evidence photos with protected file upload, SHA-256 hash, and GPS accuracy.

All collections enforce owner isolation:
- `owner = @request.auth.id` for list, view, update, and delete.
- Files in `attachments` have `protected: true` ensuring authenticated access only.

## Hooks
- `main.pb.js`:
  - Enforces `received_at` server timestamp on all photo uploads.
  - Returns `409 stale_write` when an incoming client update has an older `client_updated_at` than the server.
  - Clamps future-skewed timestamps (> 5 min).
