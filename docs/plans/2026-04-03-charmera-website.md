# Charmera Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a retro Kodak-branded contact sheet gallery website at charmera.vercel.app that displays photos and videos uploaded from the Kodak Charmera camera.

**Architecture:** Next.js App Router site on Vercel. Media stored in Vercel Blob (public access). Metadata stored as a JSON file in Vercel Blob. Single API route for import. Contact sheet grid with lightbox viewer.

**Tech Stack:** Next.js 15, React 19, TypeScript, Tailwind CSS, @vercel/blob, Barlow font (Google Fonts)

**Design Reference:** See `docs/2026-04-03-charmera-design.md` and mockups in `.superpowers/brainstorm/86252-1775242686/content/contact-sheet-v3.html`

**Kodak Logo Source:** `/Users/timcox/Downloads/KODAK_LOGO_170502_bfb4d4a7-1ff0-4a3c-8a12-b7f992a932f9.avif` — convert to PNG for web use.

---

## File Structure

```
charmera/web/
├── src/
│   ├── app/
│   │   ├── layout.tsx          # Root layout: Barlow font, metadata, global styles
│   │   ├── page.tsx            # Server component: fetches media list, renders grid
│   │   ├── globals.css         # Tailwind directives + custom properties for Kodak colors
│   │   └── api/
│   │       └── import/
│   │           └── route.ts    # POST endpoint: receives metadata, updates JSON in Blob
│   ├── components/
│   │   ├── Header.tsx          # Kodak logo + gold bar + rainbow stripes
│   │   ├── ContactSheet.tsx    # Grid of photo/video thumbnails (client component)
│   │   ├── MediaTile.tsx       # Single tile: photo or video with frame number
│   │   ├── Lightbox.tsx        # Full-screen viewer with nav (client component)
│   │   └── Footer.tsx          # Gold bar with count + date
│   └── lib/
│       └── media.ts            # Vercel Blob helpers: fetchMediaList, appendMedia
├── public/
│   └── kodak-logo.png          # Kodak logo converted from AVIF
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
└── package.json
```

---

### Task 1: Scaffold Next.js Project + Deploy to Vercel

**Files:**
- Create: `charmera/web/` (entire scaffold)
- Create: `charmera/web/public/kodak-logo.png`

- [ ] **Step 1: Create Next.js app**

```bash
cd /Users/timcox/tim-os/charmera
npx create-next-app@latest web --typescript --tailwind --app --src-dir --no-eslint --no-turbopack --no-import-alias
```

Accept defaults. This creates the full scaffold with App Router, TypeScript, Tailwind CSS.

- [ ] **Step 2: Convert and copy Kodak logo**

```bash
sips -s format png /Users/timcox/Downloads/KODAK_LOGO_170502_bfb4d4a7-1ff0-4a3c-8a12-b7f992a932f9.avif --out /Users/timcox/tim-os/charmera/web/public/kodak-logo.png
```

- [ ] **Step 3: Install @vercel/blob**

```bash
cd /Users/timcox/tim-os/charmera/web
npm install @vercel/blob
```

- [ ] **Step 4: Verify dev server starts**

```bash
cd /Users/timcox/tim-os/charmera/web
npm run dev
```

Expected: Server starts on localhost:3000 with default Next.js page.

- [ ] **Step 5: Deploy to Vercel and create Blob store**

```bash
cd /Users/timcox/tim-os/charmera/web
vercel link
vercel deploy
```

Then in Vercel Dashboard: go to the project's Storage tab → Create Database → Blob → Public access → name it "charmera-media". Pull the env vars:

```bash
vercel env pull
```

This creates `.env.local` with `BLOB_READ_WRITE_TOKEN`.

- [ ] **Step 6: Add IMPORT_SECRET env var**

Generate a random secret and set it:

```bash
openssl rand -hex 32
```

```bash
vercel env add IMPORT_SECRET
```

Paste the generated secret. Select all environments (Development, Preview, Production). Then pull again:

```bash
vercel env pull
```

- [ ] **Step 7: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git init
git add web/
git commit -m "feat: scaffold Next.js app with Vercel Blob dependency"
```

---

### Task 2: Global Styles + Kodak Color Tokens

**Files:**
- Modify: `charmera/web/src/app/globals.css`
- Modify: `charmera/web/src/app/layout.tsx`

- [ ] **Step 1: Set up globals.css with Kodak design tokens**

Replace the contents of `charmera/web/src/app/globals.css` with:

```css
@import "tailwindcss";

:root {
  --kodak-gold: #ffb700;
  --kodak-red: #e4002b;
  --kodak-orange: #e85d00;
  --kodak-amber: #f5a623;
  --kodak-green: #7ab648;
  --kodak-blue: #00a3e0;
  --grid-bg: #f5f3ef;
}

body {
  font-family: "Barlow", sans-serif;
  background: #ffffff;
  color: #1a1a1a;
  margin: 0;
}
```

- [ ] **Step 2: Update layout.tsx with Barlow font and metadata**

Replace `charmera/web/src/app/layout.tsx` with:

```tsx
import type { Metadata } from "next";
import { Barlow } from "next/font/google";
import "./globals.css";

const barlow = Barlow({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700", "800"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "Charmera — Shot on Kodak",
  description: "Photos and videos from a Kodak Charmera keychain digital camera",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={barlow.className}>{children}</body>
    </html>
  );
}
```

- [ ] **Step 3: Verify dev server renders with Barlow font**

```bash
cd /Users/timcox/tim-os/charmera/web
npm run dev
```

Open localhost:3000, confirm Barlow font loads (check Network tab for Google Fonts request).

- [ ] **Step 4: Commit**

```bash
git add web/src/app/globals.css web/src/app/layout.tsx
git commit -m "feat: add Kodak color tokens and Barlow font"
```

---

### Task 3: Header Component with Kodak Logo + Rainbow Stripes

**Files:**
- Create: `charmera/web/src/components/Header.tsx`

- [ ] **Step 1: Create Header component**

Create `charmera/web/src/components/Header.tsx`:

```tsx
import Image from "next/image";

export function Header() {
  return (
    <header>
      {/* Gold nav bar */}
      <div className="flex items-center gap-3 px-5 py-3" style={{ background: "var(--kodak-gold)" }}>
        <Image
          src="/kodak-logo.png"
          alt="Kodak"
          width={40}
          height={36}
          className="rounded-sm"
        />
        <div>
          <div className="text-sm font-extrabold tracking-wide" style={{ color: "var(--kodak-red)" }}>
            KODAK
          </div>
          <div className="text-xs tracking-widest text-black/50">CHARMERA</div>
        </div>
        <div className="ml-auto text-xs font-medium text-black/40 hidden sm:block">
          KEYCHAIN DIGITAL CAMERA
        </div>
      </div>

      {/* Rainbow stripes */}
      <div className="flex h-1.5">
        <div className="flex-1" style={{ background: "var(--kodak-red)" }} />
        <div className="flex-1" style={{ background: "var(--kodak-orange)" }} />
        <div className="flex-1" style={{ background: "var(--kodak-amber)" }} />
        <div className="flex-1" style={{ background: "var(--kodak-gold)" }} />
        <div className="flex-1" style={{ background: "var(--kodak-green)" }} />
        <div className="flex-1" style={{ background: "var(--kodak-blue)" }} />
      </div>
    </header>
  );
}
```

- [ ] **Step 2: Wire Header into page.tsx temporarily to preview**

Replace `charmera/web/src/app/page.tsx` with:

```tsx
import { Header } from "@/components/Header";

export default function Home() {
  return (
    <main>
      <Header />
      <div className="p-8 text-center text-gray-400">Contact sheet goes here</div>
    </main>
  );
}
```

- [ ] **Step 3: Verify header renders correctly**

```bash
cd /Users/timcox/tim-os/charmera/web
npm run dev
```

Open localhost:3000. Confirm: gold bar with Kodak logo, "KODAK" in red, "CHARMERA" subtitle, rainbow stripe bar below. Check mobile viewport (375px) — "KEYCHAIN DIGITAL CAMERA" should be hidden.

- [ ] **Step 4: Commit**

```bash
git add web/src/components/Header.tsx web/src/app/page.tsx
git commit -m "feat: add Kodak header with logo and rainbow stripes"
```

---

### Task 4: Media Library Helpers (Vercel Blob)

**Files:**
- Create: `charmera/web/src/lib/media.ts`

- [ ] **Step 1: Define the MediaItem type and helpers**

Create `charmera/web/src/lib/media.ts`:

```ts
import { put, list } from "@vercel/blob";

export interface MediaItem {
  url: string;
  type: "photo" | "video";
  timestamp: string; // ISO 8601
  hash: string; // SHA-256
  filename: string; // e.g. PICT0001.jpg or MOVI0020.mp4
}

const METADATA_PATH = "charmera-metadata.json";

export async function fetchMediaList(): Promise<MediaItem[]> {
  const { blobs } = await list({ prefix: METADATA_PATH });
  if (blobs.length === 0) return [];

  const metadataBlob = blobs[0];
  const response = await fetch(metadataBlob.url, { next: { revalidate: 0 } });
  if (!response.ok) return [];

  const items: MediaItem[] = await response.json();
  // Newest first
  return items.sort(
    (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
  );
}

export async function appendMedia(newItems: MediaItem[]): Promise<MediaItem[]> {
  const existing = await fetchMediaList();

  // Deduplicate by hash
  const existingHashes = new Set(existing.map((item) => item.hash));
  const unique = newItems.filter((item) => !existingHashes.has(item.hash));
  if (unique.length === 0) return existing;

  const updated = [...existing, ...unique];

  await put(METADATA_PATH, JSON.stringify(updated, null, 2), {
    access: "public",
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: "application/json",
  });

  return updated;
}
```

- [ ] **Step 2: Commit**

```bash
git add web/src/lib/media.ts
git commit -m "feat: add Vercel Blob media helpers with dedup"
```

---

### Task 5: Import API Route

**Files:**
- Create: `charmera/web/src/app/api/import/route.ts`

- [ ] **Step 1: Create the import endpoint**

Create `charmera/web/src/app/api/import/route.ts`:

```ts
import { NextRequest, NextResponse } from "next/server";
import { appendMedia, type MediaItem } from "@/lib/media";

export async function POST(request: NextRequest) {
  const secret = process.env.IMPORT_SECRET;
  const auth = request.headers.get("authorization");

  if (!secret || auth !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();

  if (!Array.isArray(body.items)) {
    return NextResponse.json(
      { error: "Expected { items: MediaItem[] }" },
      { status: 400 }
    );
  }

  const items: MediaItem[] = body.items;
  const updated = await appendMedia(items);

  return NextResponse.json({
    added: items.length,
    total: updated.length,
  });
}
```

- [ ] **Step 2: Test the endpoint locally with curl**

Start the dev server, then in another terminal:

```bash
curl -X POST http://localhost:3000/api/import \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep IMPORT_SECRET .env.local | cut -d= -f2)" \
  -d '{"items":[{"url":"https://example.com/test.jpg","type":"photo","timestamp":"2026-04-03T13:26:00Z","hash":"abc123","filename":"PICT0001.jpg"}]}'
```

Expected: `{"added":1,"total":1}` (or similar). If BLOB_READ_WRITE_TOKEN is not set locally, this will error — that's OK, it'll work when deployed.

- [ ] **Step 3: Commit**

```bash
git add web/src/app/api/import/route.ts
git commit -m "feat: add import API route with auth"
```

---

### Task 6: MediaTile Component

**Files:**
- Create: `charmera/web/src/components/MediaTile.tsx`

- [ ] **Step 1: Create the MediaTile component**

Create `charmera/web/src/components/MediaTile.tsx`:

```tsx
import type { MediaItem } from "@/lib/media";

interface MediaTileProps {
  item: MediaItem;
  index: number;
  onClick: () => void;
}

export function MediaTile({ item, index, onClick }: MediaTileProps) {
  // Extract frame number from filename: PICT0005.jpg → 0005, MOVI0020.mp4 → 0020
  const frameNumber = item.filename.replace(/^(PICT|MOVI)/, "").replace(/\.\w+$/, "");

  if (item.type === "video") {
    return (
      <button
        onClick={onClick}
        className="relative aspect-[4/3] w-full overflow-hidden rounded-[1px] bg-neutral-900 cursor-pointer border border-black/5"
      >
        {/* Play icon */}
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-white/20">
            <div className="ml-0.5 h-0 w-0 border-y-[6px] border-l-[10px] border-y-transparent border-l-white/70" />
          </div>
        </div>
        {/* Frame number */}
        <span className="absolute bottom-0.5 left-1 font-mono text-[9px] text-white/40">
          {frameNumber}
        </span>
      </button>
    );
  }

  return (
    <button
      onClick={onClick}
      className="relative aspect-[4/3] w-full overflow-hidden rounded-[1px] cursor-pointer border border-black/5"
    >
      <img
        src={item.url}
        alt={`Frame ${frameNumber}`}
        className="h-full w-full object-cover"
        loading="lazy"
      />
      {/* Frame number */}
      <span className="absolute bottom-0.5 left-1 font-mono text-[9px] text-black/30 drop-shadow-[0_0_2px_rgba(255,255,255,0.8)]">
        {frameNumber}
      </span>
    </button>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add web/src/components/MediaTile.tsx
git commit -m "feat: add MediaTile component for photo and video thumbnails"
```

---

### Task 7: Lightbox Component

**Files:**
- Create: `charmera/web/src/components/Lightbox.tsx`

- [ ] **Step 1: Create the Lightbox component**

Create `charmera/web/src/components/Lightbox.tsx`:

```tsx
"use client";

import { useEffect, useCallback } from "react";
import type { MediaItem } from "@/lib/media";

interface LightboxProps {
  items: MediaItem[];
  currentIndex: number;
  onClose: () => void;
  onNavigate: (index: number) => void;
}

export function Lightbox({ items, currentIndex, onClose, onNavigate }: LightboxProps) {
  const item = items[currentIndex];

  const goNext = useCallback(() => {
    if (currentIndex < items.length - 1) onNavigate(currentIndex + 1);
  }, [currentIndex, items.length, onNavigate]);

  const goPrev = useCallback(() => {
    if (currentIndex > 0) onNavigate(currentIndex - 1);
  }, [currentIndex, onNavigate]);

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowRight") goNext();
      if (e.key === "ArrowLeft") goPrev();
    }
    window.addEventListener("keydown", handleKey);
    // Prevent background scroll
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", handleKey);
      document.body.style.overflow = "";
    };
  }, [onClose, goNext, goPrev]);

  const frameNumber = item.filename.replace(/^(PICT|MOVI)/, "").replace(/\.\w+$/, "");
  const date = new Date(item.timestamp);
  const dateStr = date.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
  const timeStr = date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
  });

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/95"
      onClick={onClose}
    >
      {/* Close button */}
      <button
        onClick={onClose}
        className="absolute right-4 top-4 text-2xl text-white/60 hover:text-white z-10"
      >
        &times;
      </button>

      {/* Previous arrow */}
      {currentIndex > 0 && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            goPrev();
          }}
          className="absolute left-4 top-1/2 -translate-y-1/2 text-3xl text-white/40 hover:text-white z-10"
        >
          &lsaquo;
        </button>
      )}

      {/* Next arrow */}
      {currentIndex < items.length - 1 && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            goNext();
          }}
          className="absolute right-4 top-1/2 -translate-y-1/2 text-3xl text-white/40 hover:text-white z-10"
        >
          &rsaquo;
        </button>
      )}

      {/* Media content */}
      <div
        className="max-h-[85vh] max-w-[90vw]"
        onClick={(e) => e.stopPropagation()}
      >
        {item.type === "video" ? (
          <video
            src={item.url}
            controls
            autoPlay
            muted
            playsInline
            className="max-h-[85vh] max-w-[90vw] object-contain"
          />
        ) : (
          <img
            src={item.url}
            alt={`Frame ${frameNumber}`}
            className="max-h-[85vh] max-w-[90vw] object-contain"
          />
        )}
      </div>

      {/* Caption */}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 font-mono text-xs text-white/50">
        {item.filename} &middot; {dateStr} &middot; {timeStr}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add web/src/components/Lightbox.tsx
git commit -m "feat: add lightbox with keyboard nav and video playback"
```

---

### Task 8: ContactSheet Component

**Files:**
- Create: `charmera/web/src/components/ContactSheet.tsx`

- [ ] **Step 1: Create the ContactSheet component**

Create `charmera/web/src/components/ContactSheet.tsx`:

```tsx
"use client";

import { useState } from "react";
import type { MediaItem } from "@/lib/media";
import { MediaTile } from "./MediaTile";
import { Lightbox } from "./Lightbox";

interface ContactSheetProps {
  items: MediaItem[];
}

export function ContactSheet({ items }: ContactSheetProps) {
  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);

  if (items.length === 0) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center text-gray-400">
        No photos yet. Connect your Charmera and click import.
      </div>
    );
  }

  return (
    <>
      <div
        className="grid grid-cols-2 gap-1 p-2 sm:grid-cols-3 md:grid-cols-4"
        style={{ background: "var(--grid-bg)" }}
      >
        {items.map((item, i) => (
          <MediaTile
            key={item.hash}
            item={item}
            index={i}
            onClick={() => setLightboxIndex(i)}
          />
        ))}
      </div>

      {lightboxIndex !== null && (
        <Lightbox
          items={items}
          currentIndex={lightboxIndex}
          onClose={() => setLightboxIndex(null)}
          onNavigate={setLightboxIndex}
        />
      )}
    </>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add web/src/components/ContactSheet.tsx
git commit -m "feat: add ContactSheet grid with lightbox integration"
```

---

### Task 9: Footer Component

**Files:**
- Create: `charmera/web/src/components/Footer.tsx`

- [ ] **Step 1: Create the Footer component**

Create `charmera/web/src/components/Footer.tsx`:

```tsx
import type { MediaItem } from "@/lib/media";

interface FooterProps {
  items: MediaItem[];
}

export function Footer({ items }: FooterProps) {
  const photoCount = items.filter((i) => i.type === "photo").length;
  const videoCount = items.filter((i) => i.type === "video").length;

  const latestDate = items.length > 0
    ? new Date(
        Math.max(...items.map((i) => new Date(i.timestamp).getTime()))
      ).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
    : null;

  const parts: string[] = [];
  if (photoCount > 0) parts.push(`${photoCount} photo${photoCount !== 1 ? "s" : ""}`);
  if (videoCount > 0) parts.push(`${videoCount} video${videoCount !== 1 ? "s" : ""}`);

  return (
    <footer
      className="flex items-center gap-4 px-5 py-2"
      style={{ background: "var(--kodak-gold)" }}
    >
      <span className="text-xs font-semibold text-neutral-900">
        {parts.join(" \u00B7 ") || "No media"}
      </span>
      {latestDate && (
        <span className="text-xs text-black/40">{latestDate}</span>
      )}
    </footer>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add web/src/components/Footer.tsx
git commit -m "feat: add footer with media count and date"
```

---

### Task 10: Wire Up the Page

**Files:**
- Modify: `charmera/web/src/app/page.tsx`

- [ ] **Step 1: Connect all components in page.tsx**

Replace `charmera/web/src/app/page.tsx` with:

```tsx
import { Header } from "@/components/Header";
import { ContactSheet } from "@/components/ContactSheet";
import { Footer } from "@/components/Footer";
import { fetchMediaList } from "@/lib/media";

export const dynamic = "force-dynamic";

export default async function Home() {
  const items = await fetchMediaList();

  return (
    <main className="min-h-screen flex flex-col">
      <Header />
      <div className="flex-1">
        <ContactSheet items={items} />
      </div>
      <Footer items={items} />
    </main>
  );
}
```

- [ ] **Step 2: Verify everything renders locally**

```bash
cd /Users/timcox/tim-os/charmera/web
npm run dev
```

Open localhost:3000. Expected: Kodak header with logo + rainbow stripes, empty state message "No photos yet...", gold footer with "No media". If Blob token is configured, the page should render without errors.

- [ ] **Step 3: Commit**

```bash
git add web/src/app/page.tsx
git commit -m "feat: wire up page with header, contact sheet, and footer"
```

---

### Task 11: Deploy and Test End-to-End

**Files:** None (deployment + manual test)

- [ ] **Step 1: Build locally to catch errors**

```bash
cd /Users/timcox/tim-os/charmera/web
npm run build
```

Expected: Build succeeds with no errors.

- [ ] **Step 2: Deploy to Vercel**

```bash
cd /Users/timcox/tim-os/charmera/web
vercel deploy --prod
```

- [ ] **Step 3: Test the empty state**

Open charmera.vercel.app. Confirm: header, rainbow stripes, empty state, footer all render correctly.

- [ ] **Step 4: Test import API with a real photo**

Upload one of the actual Charmera photos to Vercel Blob via CLI, then POST metadata:

```bash
cd /Users/timcox/tim-os/charmera/web

# Upload a photo to Blob
npx vercel blob upload /Volumes/Charmera/DCIM/PICT0000.jpg charmera/PICT0000.jpg --no-suffix

# Get the URL from the output, then POST metadata
BLOB_URL="<url from above>"
SECRET=$(grep IMPORT_SECRET .env.local | cut -d= -f2)

curl -X POST https://charmera.vercel.app/api/import \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SECRET" \
  -d "{\"items\":[{\"url\":\"$BLOB_URL\",\"type\":\"photo\",\"timestamp\":\"2026-04-03T13:26:00Z\",\"hash\":\"test-hash-001\",\"filename\":\"PICT0000.jpg\"}]}"
```

Expected: `{"added":1,"total":1}`

- [ ] **Step 5: Verify the photo appears on the site**

Reload charmera.vercel.app. The photo should appear in the contact sheet grid with frame number "0000". Click it to open the lightbox. Verify full-size image loads, caption shows filename + date.

- [ ] **Step 6: Commit any final adjustments**

```bash
git add -A
git commit -m "feat: charmera website v1 deployed and tested"
```

---

### Task 12: Use /frontend-design for Visual Polish

**Files:**
- Potentially modify: all component files based on design review

- [ ] **Step 1: Invoke /frontend-design skill**

Use the `/frontend-design` skill to review and polish the visual design of the site. Feed it:
- The Kodak Charmera packaging image (`/Users/timcox/Downloads/B15C479C-086C-4EB3-83E3-C09290EBBAC1.png`)
- The retopro.co product page URL for reference
- The current deployed site at charmera.vercel.app
- Design goals: retro Kodak aesthetic, warm/playful minimalism, contact sheet grid

The skill will generate refined CSS and component adjustments to match the Kodak Charmera brand more closely.

- [ ] **Step 2: Apply design changes and deploy**

Apply the CSS and component changes suggested by the frontend-design skill.

```bash
cd /Users/timcox/tim-os/charmera/web
npm run build
vercel deploy --prod
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: apply Kodak Charmera visual polish via frontend-design"
```
