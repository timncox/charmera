# Charmera v2 Phase 1: Auth Proxy + Static Website Template

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the auth proxy serverless function and the static HTML gallery template that gets pushed to users' GitHub repos.

**Architecture:** Auth proxy is a single Vercel serverless function that exchanges GitHub OAuth codes for tokens. The website template is a self-contained `index.html` with embedded CSS/JS that reads `data.json` and renders a Kodak-branded contact sheet gallery.

**Tech Stack:** TypeScript (auth proxy on Vercel), vanilla HTML/CSS/JS (website template)

**Spec:** `docs/specs/2026-04-04-charmera-v2-design.md`

---

## File Structure

```
charmera/
├── auth-proxy/                    # Vercel serverless function
│   ├── api/
│   │   └── github.ts             # POST — exchanges OAuth code for token
│   ├── package.json
│   ├── tsconfig.json
│   └── vercel.json
├── template/                      # Static site template (bundled in app)
│   ├── docs/
│   │   ├── index.html            # Self-contained gallery page
│   │   └── data.json             # Empty media array
│   └── README.md                 # Repo README for user's GitHub repo
└── ...
```

---

### Task 1: Register GitHub OAuth App

**Files:** None (browser task)

- [ ] **Step 1: Create GitHub OAuth App**

Go to `https://github.com/settings/developers` → OAuth Apps → New OAuth App:
- Application name: `Charmera`
- Homepage URL: `https://github.com/timncox/charmera`
- Authorization callback URL: `charmera://callback`
- Click Register

- [ ] **Step 2: Record the Client ID and generate a Client Secret**

Save these values — Client ID ships with the app, Client Secret goes in the auth proxy as an env var.

- [ ] **Step 3: Save Client ID to a known location**

```bash
echo "GITHUB_CLIENT_ID=<your-client-id>" > /Users/timcox/tim-os/charmera/.env.github
echo "GITHUB_CLIENT_SECRET=<your-client-secret>" >> /Users/timcox/tim-os/charmera/.env.github
```

This file is gitignored and only used during development.

---

### Task 2: Auth Proxy Serverless Function

**Files:**
- Create: `charmera/auth-proxy/api/github.ts`
- Create: `charmera/auth-proxy/package.json`
- Create: `charmera/auth-proxy/tsconfig.json`
- Create: `charmera/auth-proxy/vercel.json`

- [ ] **Step 1: Create package.json**

Create `auth-proxy/package.json`:

```json
{
  "name": "charmera-auth-proxy",
  "version": "1.0.0",
  "private": true
}
```

- [ ] **Step 2: Create tsconfig.json**

Create `auth-proxy/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ES2020",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "dist"
  }
}
```

- [ ] **Step 3: Create vercel.json**

Create `auth-proxy/vercel.json`:

```json
{
  "headers": [
    {
      "source": "/api/(.*)",
      "headers": [
        { "key": "Access-Control-Allow-Origin", "value": "*" },
        { "key": "Access-Control-Allow-Methods", "value": "POST, OPTIONS" },
        { "key": "Access-Control-Allow-Headers", "value": "Content-Type" }
      ]
    }
  ]
}
```

- [ ] **Step 4: Create the auth exchange function**

Create `auth-proxy/api/github.ts`:

```typescript
export async function POST(request: Request) {
  // Handle CORS preflight
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }

  const { code } = await request.json();
  if (!code) {
    return Response.json({ error: "Missing code" }, { status: 400 });
  }

  const clientId = process.env.GITHUB_CLIENT_ID;
  const clientSecret = process.env.GITHUB_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    return Response.json({ error: "Server misconfigured" }, { status: 500 });
  }

  const tokenResponse = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      code,
    }),
  });

  const data = await tokenResponse.json();

  if (data.error) {
    return Response.json({ error: data.error_description || data.error }, { status: 400 });
  }

  return Response.json({ access_token: data.access_token });
}
```

- [ ] **Step 5: Deploy auth proxy to Vercel**

```bash
cd /Users/timcox/tim-os/charmera/auth-proxy
vercel link  # Link to a new "charmera-auth" project
# Set env vars:
echo "<client-id>" | vercel env add GITHUB_CLIENT_ID production
echo "<client-secret>" | vercel env add GITHUB_CLIENT_SECRET production
vercel deploy --prod
```

- [ ] **Step 6: Test the auth proxy**

The proxy can't be fully tested without an OAuth flow, but verify it deploys and returns the right error for missing code:

```bash
curl -s -X POST https://charmera-auth.vercel.app/api/github \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected: `{"error":"Missing code"}`

- [ ] **Step 7: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add auth-proxy/
git commit -m "feat: auth proxy for GitHub OAuth token exchange"
```

---

### Task 3: Static Website Template — HTML Structure

**Files:**
- Create: `charmera/template/docs/index.html`
- Create: `charmera/template/docs/data.json`
- Create: `charmera/template/README.md`

- [ ] **Step 1: Create empty data.json**

Create `template/docs/data.json`:

```json
[]
```

- [ ] **Step 2: Create README.md**

Create `template/README.md`:

```markdown
# Charmera

Photos and videos from my Kodak Charmera keychain digital camera.

Powered by [Charmera](https://github.com/timncox/charmera) — a macOS menu bar app that imports from the camera and publishes here automatically.
```

- [ ] **Step 3: Create index.html with full gallery implementation**

Create `template/docs/index.html` — this is the full self-contained gallery page. It must include:

1. **HTML structure** — header, grid container, lightbox overlay, empty state
2. **Embedded CSS** — Kodak branding (gold #ffb700, red #e4002b, rainbow stripes), contact sheet grid, lightbox styles, responsive breakpoints, Barlow font from Google Fonts
3. **Embedded JS** — fetch `data.json`, render grid tiles, lightbox with keyboard nav (Escape, Arrow keys), video playback, CSS rotation from `rotation` field

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Charmera — Shot on Kodak</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Barlow:wght@400;500;600;700;800&family=Barlow+Condensed:wght@600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --kodak-gold: #ffb700;
      --kodak-red: #e4002b;
      --kodak-orange: #e85d00;
      --kodak-amber: #f5a623;
      --kodak-green: #7ab648;
      --kodak-blue: #00a3e0;
      --kodak-cream: #faf6f0;
      --grid-bg: #f5f3ef;
      --contact-border: #d6d0c6;
      --frame-text: #8a8070;
    }

    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      font-family: 'Barlow', sans-serif;
      background: var(--kodak-cream);
      color: #1a1a1a;
    }

    /* Header */
    .header {
      background: linear-gradient(180deg, #ffc31a 0%, var(--kodak-gold) 100%);
      padding: 0.5rem 1.2rem;
      display: flex;
      align-items: center;
      gap: 0.6rem;
    }
    .header-logo {
      width: 36px;
      height: 33px;
      background: var(--kodak-red);
      border-radius: 4px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--kodak-gold);
      font-weight: 900;
      font-size: 1.1rem;
      font-family: 'Barlow Condensed', sans-serif;
    }
    .header-brand {
      font-family: 'Barlow Condensed', sans-serif;
      font-weight: 800;
      font-size: 17px;
      color: var(--kodak-red);
      letter-spacing: 0.04em;
    }
    .header-sub {
      font-size: 0.65rem;
      letter-spacing: 0.1em;
      color: rgba(0,0,0,0.4);
      font-style: italic;
    }

    /* Rainbow stripes */
    .rainbow {
      display: flex;
      height: 5px;
    }
    .rainbow div { flex: 1; }

    /* Grid */
    .grid {
      display: grid;
      grid-template-columns: repeat(2, 1fr);
      gap: 3px;
      padding: 0.75rem;
      background: var(--grid-bg);
      box-shadow: inset 0 1px 3px rgba(0,0,0,0.06);
    }
    @media (min-width: 640px) { .grid { grid-template-columns: repeat(3, 1fr); gap: 4px; padding: 1rem; } }
    @media (min-width: 768px) { .grid { grid-template-columns: repeat(4, 1fr); } }
    @media (min-width: 1024px) { .grid { grid-template-columns: repeat(5, 1fr); } }

    /* Tiles */
    .tile {
      position: relative;
      aspect-ratio: 4/3;
      overflow: hidden;
      cursor: pointer;
      border: 1.5px solid var(--contact-border);
      transition: box-shadow 0.15s ease, border-color 0.15s ease;
    }
    .tile:hover {
      box-shadow: 0 0 0 2px var(--kodak-gold);
      border-color: var(--kodak-gold);
    }
    .tile img, .tile video {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
      pointer-events: none;
    }
    .tile .frame {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      padding: 2px 6px;
      font-family: monospace;
      font-size: 9px;
      color: var(--frame-text);
      background: linear-gradient(transparent, rgba(234,230,223,0.92));
    }
    .tile .play-icon {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .tile .play-icon div {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      background: rgba(0,0,0,0.5);
      backdrop-filter: blur(4px);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .tile .play-icon div::after {
      content: '';
      display: block;
      width: 0;
      height: 0;
      border-top: 6px solid transparent;
      border-bottom: 6px solid transparent;
      border-left: 10px solid rgba(255,255,255,0.9);
      margin-left: 2px;
    }

    /* Footer */
    .footer {
      position: relative;
      background: linear-gradient(180deg, var(--kodak-gold) 0%, #e6a600 100%);
      padding: 0.5rem 1.2rem;
      display: flex;
      align-items: center;
      gap: 1rem;
    }
    .footer-rainbow {
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      display: flex;
      height: 2px;
    }
    .footer-rainbow div { flex: 1; }
    .footer-count {
      font-size: 0.7rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #1a1a1a;
    }
    .footer-date {
      font-size: 0.6rem;
      color: rgba(0,0,0,0.35);
    }
    .footer-tagline {
      margin-left: auto;
      font-size: 0.55rem;
      font-style: italic;
      color: rgba(0,0,0,0.3);
    }

    /* Empty state */
    .empty {
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 50vh;
      color: #aaa;
      font-size: 0.9rem;
    }

    /* Lightbox */
    .lightbox {
      display: none;
      position: fixed;
      inset: 0;
      z-index: 50;
      background: rgba(8,6,3,0.96);
      align-items: center;
      justify-content: center;
    }
    .lightbox.open { display: flex; }
    .lightbox img, .lightbox video {
      max-height: 85vh;
      max-width: 90vw;
      object-fit: contain;
      border-radius: 2px;
      box-shadow: 0 4px 40px rgba(0,0,0,0.5);
      transition: transform 0.3s ease;
    }
    .lightbox .close {
      position: absolute;
      top: 16px;
      right: 16px;
      background: none;
      border: none;
      color: rgba(255,255,255,0.5);
      font-size: 24px;
      cursor: pointer;
      width: 32px;
      height: 32px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .lightbox .close:hover { color: white; background: rgba(255,255,255,0.1); }
    .lightbox .nav {
      position: absolute;
      top: 50%;
      transform: translateY(-50%);
      background: none;
      border: none;
      color: rgba(255,255,255,0.3);
      font-size: 32px;
      cursor: pointer;
      width: 40px;
      height: 40px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .lightbox .nav:hover { color: white; background: rgba(255,255,255,0.1); }
    .lightbox .nav.prev { left: 12px; }
    .lightbox .nav.next { right: 12px; }
    .lightbox .info {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      text-align: center;
      padding: 12px;
      font-family: monospace;
      font-size: 11px;
      color: rgba(255,255,255,0.45);
      background: linear-gradient(transparent, rgba(0,0,0,0.6));
    }
    .lightbox .info .filename { color: var(--kodak-gold); opacity: 0.7; }

    @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
    .lightbox.open { animation: fadeIn 0.2s ease-out; }
  </style>
</head>
<body>
  <!-- Header -->
  <header class="header">
    <div class="header-logo">K</div>
    <div>
      <div class="header-brand">KODAK</div>
      <div class="header-sub">Charmera</div>
    </div>
  </header>
  <div class="rainbow">
    <div style="background:var(--kodak-red)"></div>
    <div style="background:var(--kodak-orange)"></div>
    <div style="background:var(--kodak-amber)"></div>
    <div style="background:var(--kodak-gold)"></div>
    <div style="background:var(--kodak-green)"></div>
    <div style="background:var(--kodak-blue)"></div>
  </div>

  <!-- Grid -->
  <div id="grid" class="grid"></div>
  <div id="empty" class="empty" style="display:none">No photos yet. Connect your Charmera and click import.</div>

  <!-- Footer -->
  <footer class="footer">
    <div class="footer-rainbow">
      <div style="background:var(--kodak-red)"></div>
      <div style="background:var(--kodak-orange)"></div>
      <div style="background:var(--kodak-amber)"></div>
      <div style="background:var(--kodak-gold)"></div>
      <div style="background:var(--kodak-green)"></div>
      <div style="background:var(--kodak-blue)"></div>
    </div>
    <span id="footer-count" class="footer-count"></span>
    <span id="footer-date" class="footer-date"></span>
    <span class="footer-tagline">Shot on Charmera</span>
  </footer>

  <!-- Lightbox -->
  <div id="lightbox" class="lightbox">
    <button class="close" onclick="closeLightbox()">&times;</button>
    <button class="nav prev" onclick="navLightbox(-1)">&#8249;</button>
    <button class="nav next" onclick="navLightbox(1)">&#8250;</button>
    <div id="lb-media"></div>
    <div class="info">
      <span id="lb-filename" class="filename"></span>
      &middot; <span id="lb-date"></span>
      &middot; <span id="lb-counter"></span>
    </div>
  </div>

  <script>
    let items = [];
    let currentIndex = -1;

    async function init() {
      try {
        const res = await fetch('data.json');
        items = await res.json();
      } catch { items = []; }

      items.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

      if (items.length === 0) {
        document.getElementById('grid').style.display = 'none';
        document.getElementById('empty').style.display = 'flex';
        document.getElementById('footer-count').textContent = 'No media';
        return;
      }

      const grid = document.getElementById('grid');
      grid.innerHTML = '';

      items.forEach((item, i) => {
        const tile = document.createElement('div');
        tile.className = 'tile';
        tile.onclick = () => openLightbox(i);

        const frameNum = item.filename.replace(/^(PICT|MOVI)/, '').replace(/\.\w+$/, '');

        if (item.type === 'video') {
          const vid = document.createElement('video');
          vid.src = 'media/' + item.filename;
          vid.muted = true;
          vid.playsInline = true;
          vid.preload = 'metadata';
          if (item.rotation) vid.style.transform = 'rotate(' + item.rotation + 'deg)';
          tile.appendChild(vid);

          const playIcon = document.createElement('div');
          playIcon.className = 'play-icon';
          playIcon.innerHTML = '<div></div>';
          tile.appendChild(playIcon);
        } else {
          const img = document.createElement('img');
          img.src = 'media/' + item.filename;
          img.alt = 'Frame ' + frameNum;
          img.loading = 'lazy';
          if (item.rotation) img.style.transform = 'rotate(' + item.rotation + 'deg)';
          tile.appendChild(img);
        }

        const frame = document.createElement('div');
        frame.className = 'frame';
        frame.textContent = frameNum;
        tile.appendChild(frame);

        grid.appendChild(tile);
      });

      // Footer
      const photos = items.filter(i => i.type === 'photo').length;
      const videos = items.filter(i => i.type === 'video').length;
      const parts = [];
      if (photos) parts.push(photos + ' photo' + (photos !== 1 ? 's' : ''));
      if (videos) parts.push(videos + ' video' + (videos !== 1 ? 's' : ''));
      document.getElementById('footer-count').textContent = parts.join(' \u00B7 ');

      const latest = new Date(Math.max(...items.map(i => new Date(i.timestamp))));
      document.getElementById('footer-date').textContent = latest.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    }

    function openLightbox(index) {
      currentIndex = index;
      renderLightbox();
      document.getElementById('lightbox').classList.add('open');
      document.body.style.overflow = 'hidden';
    }

    function closeLightbox() {
      document.getElementById('lightbox').classList.remove('open');
      document.body.style.overflow = '';
      const container = document.getElementById('lb-media');
      container.innerHTML = '';
      currentIndex = -1;
    }

    function navLightbox(dir) {
      const next = currentIndex + dir;
      if (next >= 0 && next < items.length) {
        currentIndex = next;
        renderLightbox();
      }
    }

    function renderLightbox() {
      const item = items[currentIndex];
      const container = document.getElementById('lb-media');
      container.innerHTML = '';

      if (item.type === 'video') {
        const vid = document.createElement('video');
        vid.src = 'media/' + item.filename;
        vid.controls = true;
        vid.autoplay = true;
        vid.muted = true;
        vid.playsInline = true;
        if (item.rotation) vid.style.transform = 'rotate(' + item.rotation + 'deg)';
        container.appendChild(vid);
      } else {
        const img = document.createElement('img');
        img.src = 'media/' + item.filename;
        img.alt = item.filename;
        if (item.rotation) img.style.transform = 'rotate(' + item.rotation + 'deg)';
        container.appendChild(img);
      }

      document.getElementById('lb-filename').textContent = item.filename;
      const d = new Date(item.timestamp);
      document.getElementById('lb-date').textContent = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
      document.getElementById('lb-counter').textContent = (currentIndex + 1) + '/' + items.length;

      // Update nav visibility
      document.querySelector('.nav.prev').style.display = currentIndex > 0 ? '' : 'none';
      document.querySelector('.nav.next').style.display = currentIndex < items.length - 1 ? '' : 'none';
    }

    document.addEventListener('keydown', (e) => {
      if (currentIndex === -1) return;
      if (e.key === 'Escape') closeLightbox();
      if (e.key === 'ArrowRight') navLightbox(1);
      if (e.key === 'ArrowLeft') navLightbox(-1);
    });

    document.getElementById('lightbox').addEventListener('click', (e) => {
      if (e.target === document.getElementById('lightbox')) closeLightbox();
    });

    init();
  </script>
</body>
</html>
```

- [ ] **Step 4: Test locally**

```bash
cd /Users/timcox/tim-os/charmera/template/docs
# Add a test entry to data.json
echo '[{"filename":"test.jpg","type":"photo","timestamp":"2026-04-04T12:00:00Z","rotation":0}]' > data.json
python3 -m http.server 8080
```

Open `http://localhost:8080` — verify the Kodak branded header, rainbow stripes, grid renders (will show broken image for test.jpg, that's fine), lightbox opens on click, keyboard nav works.

Reset data.json:
```bash
echo '[]' > data.json
```

- [ ] **Step 5: Commit**

```bash
cd /Users/timcox/tim-os/charmera
git add template/
git commit -m "feat: static website template — Kodak contact sheet gallery for GitHub Pages"
```

---

### Task 4: Push to GitHub

- [ ] **Step 1: Push everything**

```bash
cd /Users/timcox/tim-os/charmera
git add auth-proxy/ template/
git push origin main
```
