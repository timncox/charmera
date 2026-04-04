# Charmera v2 — Self-Hosted GitHub Pages App

## Problem

Charmera v1 requires manual Vercel setup with tokens and env vars. Users should be able to download the app, sign in with GitHub, and start importing — nothing else.

## Solution

A macOS menu bar app distributed as a DMG and via Homebrew. One-click GitHub sign-in creates a repo and GitHub Pages site automatically. Photos import from the Kodak Charmera camera to the user's own `username.github.io/charmera` gallery.

## Architecture

Three components:

1. **Charmera Mac app** (Swift) — menu bar app with setup wizard, import pipeline, photo management
2. **Auth proxy** (serverless) — single function at `auth.charmera.app` that exchanges GitHub OAuth codes for tokens
3. **Static website template** — vanilla HTML/CSS/JS bundled in the app, pushed to the user's GitHub repo

No React, no Node.js, no Vercel, no database. The user's gallery is a static GitHub Pages site.

## Setup Flow

1. App launches → no config in Keychain → shows native SwiftUI setup window
2. Kodak-branded window with "Sign in with GitHub" button
3. Click opens browser to `https://github.com/login/oauth/authorize?client_id=xxx&scope=repo`
4. User authorizes → GitHub redirects to `charmera://callback?code=xxx`
5. App catches URL scheme, sends code to `auth.charmera.app/api/github`
6. Auth proxy exchanges code for access token using client secret, returns token
7. App stores GitHub token in macOS Keychain
8. App creates repo `charmera` via GitHub API (or uses existing if present)
9. App enables GitHub Pages on the repo (main branch, `/docs` folder)
10. App pushes initial website template (index.html, styles, data.json) to repo
11. Setup window shows "Ready! Your gallery is at username.github.io/charmera"
12. Checkbox: "Start at login" — registers as login item via SMAppService
13. Window closes, "K" appears in menu bar

## Import Pipeline

When user clicks "K" in menu bar:

1. Discover `PICT*.jpg` and `MOVI*.avi` in `/Volumes/Charmera/DCIM/`
2. SHA-256 hash each file, skip already-imported (hashes stored in `~/Pictures/Charmera/.imported-hashes`)
3. Copy to `~/Pictures/Charmera/{YYYY-MM-DD}/`
4. Orientation detection via Apple Vision framework (faces → text → horizon lines)
5. Rotate with `sips` if needed
6. Convert AVI → MP4 via bundled ffmpeg
7. Import to Photos.app "Charmera" album via AppleScript
8. Upload photos + videos to GitHub repo `docs/media/` via GitHub Contents API (base64, one file at a time)
9. Update `docs/data.json` — append new entries
10. GitHub Pages auto-rebuilds
11. Delete imported files from camera (only if all uploads succeeded)
12. macOS notification: "Imported X photos, Y videos"

For large batches (50+ files), uploads are chunked into batches of 20 to stay within GitHub API rate limits.

## Photo Management (from the app)

Right-click the "K" menu bar icon → context menu:
- **Open Gallery** — opens `username.github.io/charmera` in browser
- **Manage Photos** — opens a native window showing the contact sheet grid
- **Import** — same as left-click
- **Preferences** — login item toggle, gallery URL

Manage Photos window:
- Grid view of all photos from `data.json`
- Click to enlarge in a native lightbox
- Rotate button — updates `rotation` field in `data.json`, pushes to GitHub
- Delete button — removes file from repo + entry from `data.json`, pushes to GitHub
- Changes push to GitHub in background, site updates automatically

## Website (Static GitHub Pages)

### Repository Structure

```
username/charmera/
├── docs/                    ← GitHub Pages root
│   ├── index.html           ← Self-contained gallery page
│   ├── data.json            ← Media metadata array
│   └── media/               ← Photos and videos
│       ├── PICT0000.jpg
│       ├── PICT0001.jpg
│       └── MOVI0020.mp4
└── README.md
```

### index.html

Single self-contained HTML file with embedded CSS and JS:
- Fetches `data.json` on load
- Renders Kodak Charmera branded contact sheet grid
- Kodak gold header + rainbow stripes
- Click thumbnail → lightbox with keyboard navigation
- Video playback with first-frame preview
- Applies CSS rotation from `rotation` field in data.json
- Responsive: 4 columns desktop, 3 tablet, 2 mobile
- Barlow font from Google Fonts (only external dependency)

### data.json

```json
[
  {
    "filename": "PICT0000.jpg",
    "type": "photo",
    "timestamp": "2026-04-04T11:51:00Z",
    "rotation": 0
  },
  {
    "filename": "MOVI0004.mp4",
    "type": "video",
    "timestamp": "2026-04-04T11:52:00Z",
    "rotation": 0
  }
]
```

Media URLs are relative: `media/PICT0000.jpg`.

## Auth Proxy

Deployed at `auth.charmera.app` (on Tim's Vercel account):

```
auth-proxy/
└── api/
    └── github.ts   ← POST {code} → exchanges → returns {access_token}
```

- Single serverless function, ~15 lines
- Uses `GITHUB_CLIENT_SECRET` env var
- No user data stored, no database, stateless
- Client ID is public, ships with the app

GitHub OAuth App registered at `github.com/settings/developers`:
- App name: Charmera
- Callback URL: `charmera://callback`

## Distribution

### DMG

- `.app` bundle in `/Applications`
- Info.plist with `charmera://` URL scheme
- Kodak camera icon
- Bundled: compressed ffmpeg binary (~30MB), website template files
- Signed with Apple Developer ID (or unsigned initially)
- Hosted as GitHub Release on `timncox/charmera`

### Homebrew

```
brew tap timncox/charmera
brew install charmera
```

- Formula downloads the release DMG/binary from GitHub Releases
- Tap repo: `timncox/homebrew-charmera`

### Login Item

- `SMAppService.mainApp.register()` (macOS 13+)
- Toggle in setup window and preferences

## ffmpeg

- Compressed static binary bundled in `.app/Contents/Resources/ffmpeg.xz`
- On first video import: decompress to `~/Library/Application Support/Charmera/ffmpeg`
- ~30MB compressed, ~80MB decompressed
- Only decompressed when first needed
- If decompression fails, videos are skipped with a notification

## Dependencies

**User installs:** Nothing. Just the app.

**Bundled in app:**
- ffmpeg (compressed)
- Website template (index.html, etc.)

**Required accounts:**
- GitHub (free)

## Migration from v1

Existing v1 users (Vercel-based) can:
- Run the new app, sign in with GitHub
- Existing photos on Vercel stay as-is
- New photos go to GitHub
- Manual migration: download from Vercel, re-import via the app (or we add a migration command later)
