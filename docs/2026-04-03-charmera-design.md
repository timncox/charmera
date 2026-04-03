# Charmera — Design Document

## Problem

Tim has a Kodak Charmera keychain digital camera that mounts as a USB drive at `/Volumes/Charmera`. Getting photos/videos off it and onto the web requires manual file copying, format conversion, uploading, and Photos.app importing — too many steps for what should be a one-click action.

## Solution

Two components:

1. **macOS menu bar app** (Swift) — one-click import from the Charmera camera to local backup, Photos.app, and Vercel Blob
2. **Website** (Next.js on Vercel) — retro Kodak-branded contact sheet gallery at charmera.vercel.app

## Camera Details

- **Device:** Kodak Charmera keychain digital camera
- **Mount path:** `/Volumes/Charmera/DCIM/`
- **Photos:** `PICT####.jpg` — 1440x1080 JPEG (MJPEG encoder, Exif metadata)
- **Videos:** `MOVI####.avi` — 1440x1080 AVI, Motion JPEG codec, 30fps, mono PCM audio at 16kHz
- **Shared counter:** Photos and videos share the same incrementing number sequence

## Component 1: Menu Bar App (Swift)

### Appearance
- macOS menu bar icon: Kodak "K" logo or small camera glyph
- **Gray** when no camera connected
- **Yellow** (#ffb700) when `/Volumes/Charmera` is mounted

### Click Action (silent pipeline)
1. Detect `/Volumes/Charmera/DCIM/` — abort with notification if not mounted
2. Copy all `PICT*.jpg` and `MOVI*.avi` files to `~/Pictures/Charmera/{YYYY-MM-DD}/`
3. Convert `MOVI*.avi` → MP4 (H.264 + AAC) via `ffmpeg` for web playback
4. Import originals into Photos.app → "Charmera" album (create album if it doesn't exist) via AppleScript/PhotoKit
5. Upload JPEGs (as-is) and converted MP4s to Vercel Blob
6. POST metadata to `charmera.vercel.app/api/import` with array of `{url, type, timestamp, hash}`
7. Send macOS notification: "Charmera: Imported {N} photos, {M} videos" with thumbnail of first image

### Duplicate Detection
- SHA-256 hash of each file stored in `~/Pictures/Charmera/.imported-hashes`
- Skip files whose hash is already recorded
- Allows safe re-clicking without double imports

### Dependencies
- `ffmpeg` — must be installed (`brew install ffmpeg`). App checks on first run and shows notification if missing.

## Component 2: Website (Next.js on Vercel)

### URL
`charmera.vercel.app`

### Design — Kodak Charmera Aesthetic
- **Header:** Gold (#ffb700) background, Kodak logo (from provided AVIF), "KODAK" in red (#e4002b), "CHARMERA" subtitle
- **Rainbow stripes:** 6-color bar below header — #e4002b, #e85d00, #f5a623, #ffb700, #7ab648, #00a3e0
- **Grid background:** Warm white (#f5f3ef)
- **Page background:** White (#ffffff)
- **Typography:** Barlow font family (Google Fonts)
- **Footer strip:** Gold (#ffb700) with photo/video count and latest import date

### Layout — Contact Sheet
- **4 columns** on desktop, **3** on tablet, **2** on mobile
- Tight 4px gaps between tiles, minimal border-radius (1px)
- All thumbnails cropped to 4:3 aspect ratio
- Frame numbers (monospace, small) in bottom-left corner of each tile
- Newest photos first (reverse chronological)

### Photo Tiles
- Display JPEG thumbnail directly (1440x1080 is web-friendly, no resizing needed)
- Frame number overlay: `0001`, `0002`, etc.

### Video Tiles
- Dark thumbnail (first frame or dark placeholder)
- Play icon (circle + triangle) centered
- Duration badge in bottom-right corner
- Frame number in bottom-left

### Lightbox (click to enlarge)
- Full-screen dark overlay
- Full-size image or auto-playing video (muted by default, tap to unmute)
- Close button (X) top-right
- Left/right arrow navigation (keyboard arrows + swipe on mobile)
- Caption bar: filename, date, time
- Esc to close

### API
- `POST /api/import` — receives array of `{url, type, timestamp, hash}`, appends to metadata store
- Auth: simple shared secret in `Authorization` header (env var `IMPORT_SECRET`)

### Data Storage
- **Media files:** Vercel Blob (CDN-backed)
- **Metadata:** JSON file in Vercel Blob — array of `{url, type, timestamp, hash, filename}`. No database needed for a flat feed.

### No Auth
- Public site. Anyone with the URL can view.
- Only the import API requires the shared secret.

## Project Structure

```
charmera/
├── app/                    # Swift menu bar app (Xcode project)
├── web/                    # Next.js website
│   ├── src/
│   │   ├── app/
│   │   │   ├── page.tsx        # Contact sheet grid
│   │   │   ├── layout.tsx      # Kodak header + rainbow stripes
│   │   │   └── api/
│   │   │       └── import/
│   │   │           └── route.ts  # Import endpoint
│   │   └── components/
│   │       ├── ContactSheet.tsx  # Grid of thumbnails
│   │       ├── Lightbox.tsx      # Full-size viewer
│   │       └── Header.tsx        # Kodak branding
│   ├── public/
│   │   └── kodak-logo.png        # Converted from AVIF
│   └── package.json
└── docs/
    └── 2026-04-03-charmera-design.md
```

## Tech Stack

- **Menu bar app:** Swift, AppKit (NSStatusItem), Foundation (FileManager, Process for ffmpeg)
- **Website:** Next.js 15, React 19, TypeScript, Tailwind CSS
- **Storage:** Vercel Blob
- **Deployment:** Vercel
- **Video conversion:** ffmpeg (local, on the Mac)
