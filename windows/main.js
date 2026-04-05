const { app, Tray, Menu, BrowserWindow, shell, nativeImage, dialog } = require("electron");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const https = require("https");

const CONFIG = {
  clientID: "Ov23liHp3TaFjD42UIUc",
  authProxyURL: "https://charmera-auth.vercel.app/api/github",
  callbackScheme: "charmera",
  repoName: "charmera-gallery",
  cameraMarkers: ["DCIM", "SPIDCIM"],
  appName: "Charmera",
};

let tray = null;
let setupWindow = null;
let reviewWindow = null;
let token = null;
let username = null;
let isImporting = false;

// ─── Credential Storage ───

const credPath = path.join(app.getPath("userData"), "credentials.json");

function loadCredentials() {
  try {
    const data = JSON.parse(fs.readFileSync(credPath, "utf8"));
    token = data.token;
    username = data.username;
  } catch {}
}

function saveCredentials() {
  fs.writeFileSync(credPath, JSON.stringify({ token, username }));
}

// ─── Camera Detection ───

function findCamera() {
  const isWin = process.platform === "win32";
  if (isWin) {
    // Check drive letters D-Z
    for (let code = 68; code <= 90; code++) {
      const drive = String.fromCharCode(code) + ":\\\\";
      try {
        if (!fs.existsSync(drive)) continue;
        const hasAll = CONFIG.cameraMarkers.every((m) =>
          fs.existsSync(path.join(drive, m))
        );
        if (hasAll) return path.join(drive, "DCIM");
      } catch {}
    }
  } else {
    // macOS/Linux
    try {
      const volumes = fs.readdirSync("/Volumes");
      for (const vol of volumes) {
        const volPath = path.join("/Volumes", vol);
        const hasAll = CONFIG.cameraMarkers.every((m) =>
          fs.existsSync(path.join(volPath, m))
        );
        if (hasAll) return path.join(volPath, "DCIM");
      }
    } catch {}
  }
  return null;
}

// ─── GitHub API ───

function githubRequest(method, apiPath, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: "api.github.com",
      path: apiPath,
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        "User-Agent": "Charmera",
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
      },
    };

    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });

    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function getUsername() {
  const res = await githubRequest("GET", "/user");
  return res.data.login;
}

async function createRepo() {
  await githubRequest("POST", "/user/repos", {
    name: CONFIG.repoName,
    auto_init: true,
    private: false,
  });
}

async function getFileSHA(repoPath) {
  const res = await githubRequest(
    "GET",
    `/repos/${username}/${CONFIG.repoName}/contents/${repoPath}`
  );
  return res.status === 200 ? res.data.sha : null;
}

async function uploadFile(repoPath, content, message, sha) {
  const body = {
    message,
    content: content.toString("base64"),
  };
  if (sha) body.sha = sha;
  return githubRequest(
    "PUT",
    `/repos/${username}/${CONFIG.repoName}/contents/${repoPath}`,
    body
  );
}

async function enablePages() {
  await githubRequest(
    "POST",
    `/repos/${username}/${CONFIG.repoName}/pages`,
    { source: { branch: "main", path: "/docs" } }
  );
}

// ─── Import Pipeline ───

function discoverFiles(dcimPath) {
  const files = [];
  function walk(dir) {
    try {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
          walk(path.join(dir, entry.name));
        } else {
          const upper = entry.name.toUpperCase();
          if (
            (upper.startsWith("PICT") && upper.endsWith(".JPG")) ||
            (upper.startsWith("MOVI") && upper.endsWith(".AVI"))
          ) {
            files.push(path.join(dir, entry.name));
          }
        }
      }
    } catch {}
  }
  walk(dcimPath);
  return files.sort();
}

function hashFile(filePath) {
  const data = fs.readFileSync(filePath);
  return crypto.createHash("sha256").update(data).digest("hex");
}

function getBackupDir() {
  const base = path.join(app.getPath("pictures"), "Charmera");
  const date = new Date().toISOString().split("T")[0];
  const dir = path.join(base, date);
  fs.mkdirSync(dir, { recursive: true });
  return { dir, date };
}

function loadHashes() {
  const hashFile = path.join(
    app.getPath("pictures"),
    "Charmera",
    ".imported-hashes"
  );
  try {
    return new Set(
      fs.readFileSync(hashFile, "utf8").split("\n").filter(Boolean)
    );
  } catch {
    return new Set();
  }
}

function saveHashes(hashes) {
  const hashFile = path.join(
    app.getPath("pictures"),
    "Charmera",
    ".imported-hashes"
  );
  fs.mkdirSync(path.dirname(hashFile), { recursive: true });
  fs.writeFileSync(hashFile, [...hashes].sort().join("\n") + "\n");
}

async function runImport() {
  if (isImporting || !token) return;

  const dcimPath = findCamera();
  if (!dcimPath) {
    dialog.showMessageBox({
      type: "info",
      title: "Charmera",
      message: "No camera detected.",
    });
    return;
  }

  isImporting = true;
  updateTray();

  try {
    const allFiles = discoverFiles(dcimPath);
    const importedHashes = loadHashes();
    const newFiles = [];

    for (const filePath of allFiles) {
      const hash = hashFile(filePath);
      if (!importedHashes.has(hash)) {
        newFiles.push({ path: filePath, hash });
      }
    }

    if (newFiles.length === 0) {
      dialog.showMessageBox({
        type: "info",
        title: "Charmera",
        message: "No new photos or videos found on camera.",
      });
      isImporting = false;
      updateTray();
      return;
    }

    // Copy to local backup
    const { dir: backupDir } = getBackupDir();
    const localFiles = [];

    for (const item of newFiles) {
      const filename = path.basename(item.path);
      const dest = path.join(backupDir, filename);
      if (!fs.existsSync(dest)) {
        fs.copyFileSync(item.path, dest);
      }

      const ext = path.extname(filename).toLowerCase();
      if (ext === ".jpg" || ext === ".jpeg") {
        // Auto-rotate using sharp
        try {
          const sharp = require("sharp");
          const rotated = await sharp(dest).rotate().toBuffer();
          fs.writeFileSync(dest, rotated);
        } catch {}
      }

      localFiles.push({
        path: dest,
        filename,
        hash: item.hash,
        type: ext === ".jpg" || ext === ".jpeg" ? "photo" : "video",
      });
    }

    // Upload to GitHub
    let uploadCount = 0;
    const newEntries = [];

    for (const item of localFiles) {
      if (item.type === "video" && item.filename.toLowerCase().endsWith(".avi"))
        continue;

      const fileData = fs.readFileSync(item.path);
      const repoPath = `docs/media/${item.filename}`;
      const sha = await getFileSHA(repoPath);

      try {
        await uploadFile(repoPath, fileData, `Add ${item.filename}`, sha);
        uploadCount++;
        newEntries.push({
          type: item.type,
          filename: item.filename,
          url: `media/${item.filename}`,
          timestamp: new Date().toISOString(),
        });
      } catch (err) {
        console.error(`Failed to upload ${item.filename}:`, err);
      }
    }

    // Update data.json
    if (newEntries.length > 0) {
      const dataPath = "docs/data.json";
      const dataSHA = await getFileSHA(dataPath);
      let existing = [];
      try {
        const res = await githubRequest(
          "GET",
          `/repos/${username}/${CONFIG.repoName}/contents/${dataPath}`
        );
        if (res.status === 200) {
          existing = JSON.parse(
            Buffer.from(res.data.content, "base64").toString()
          );
        }
      } catch {}

      const existingURLs = new Set(existing.map((e) => e.url));
      const uniqueNew = newEntries.filter((e) => !existingURLs.has(e.url));
      const allEntries = [...existing, ...uniqueNew];
      const jsonData = Buffer.from(JSON.stringify(allEntries, null, 2));
      await uploadFile(dataPath, jsonData, "Update gallery data", dataSHA);
    }

    // Save hashes and optionally delete from camera
    if (uploadCount === localFiles.filter((f) => !f.filename.toLowerCase().endsWith(".avi")).length) {
      const allHashes = new Set([...importedHashes, ...newFiles.map((f) => f.hash)]);
      saveHashes(allHashes);

      for (const item of newFiles) {
        try {
          fs.unlinkSync(item.path);
        } catch {}
      }
    }

    const galleryURL = `https://${username}.github.io/${CONFIG.repoName}/`;
    const result = await dialog.showMessageBox({
      type: "info",
      title: "Charmera Import Complete",
      message: `${uploadCount} file(s) imported.`,
      buttons: ["Open Gallery", "OK"],
    });
    if (result.response === 0) {
      shell.openExternal(galleryURL);
    }
  } catch (err) {
    dialog.showErrorBox("Import Failed", err.message || String(err));
  }

  isImporting = false;
  updateTray();
}

// ─── OAuth Setup ───

function showSetup() {
  if (setupWindow) {
    setupWindow.focus();
    return;
  }

  setupWindow = new BrowserWindow({
    width: 420,
    height: 400,
    resizable: false,
    webPreferences: { nodeIntegration: true, contextIsolation: false },
    title: "Charmera Setup",
  });

  setupWindow.loadFile("setup.html");
  setupWindow.on("closed", () => (setupWindow = null));
}

// ─── Tray ───

function updateTray() {
  if (!tray) return;
  const cameraConnected = !!findCamera();

  const contextMenu = Menu.buildFromTemplate([
    {
      label: "Import",
      click: runImport,
      enabled: !isImporting && cameraConnected,
    },
    ...(username
      ? [
          {
            label: "Open Gallery",
            click: () =>
              shell.openExternal(
                `https://${username}.github.io/${CONFIG.repoName}/`
              ),
          },
        ]
      : []),
    { type: "separator" },
    { label: "Preferences...", click: showSetup },
    { type: "separator" },
    { label: "Quit", click: () => app.quit() },
  ]);

  tray.setContextMenu(contextMenu);

  const color = isImporting ? "blue" : cameraConnected ? "gold" : "gray";
  tray.setToolTip(
    isImporting
      ? "Importing..."
      : cameraConnected
        ? "Camera connected"
        : "Charmera"
  );
}

// ─── App Lifecycle ───

app.whenReady().then(() => {
  // Register URL scheme handler
  app.setAsDefaultProtocolClient(CONFIG.callbackScheme);

  loadCredentials();

  // Create tray with K icon
  const iconPath = path.join(__dirname, "tray-icon.png");
  let trayImage;
  if (fs.existsSync(iconPath)) {
    trayImage = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });
  } else {
    // Fallback: create a simple icon
    trayImage = nativeImage.createEmpty();
  }
  tray = new Tray(trayImage);
  tray.setToolTip("Charmera");

  updateTray();

  // Poll for camera
  setInterval(updateTray, 5000);

  if (!token) {
    showSetup();
  }
});

// Handle OAuth callback URL
app.on("open-url", (event, url) => {
  event.preventDefault();
  handleOAuthCallback(url);
});

// Windows: handle protocol via second-instance
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on("second-instance", (event, argv) => {
    const url = argv.find((a) => a.startsWith(`${CONFIG.callbackScheme}://`));
    if (url) handleOAuthCallback(url);
  });
}

async function handleOAuthCallback(url) {
  const parsed = new URL(url);
  const code = parsed.searchParams.get("code");
  if (!code) return;

  try {
    // Exchange code for token
    const res = await fetch(CONFIG.authProxyURL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
    });
    const data = await res.json();
    if (data.access_token) {
      token = data.access_token;
      username = await getUsername();
      saveCredentials();
      await createRepo();
      await enablePages();

      // Push template
      const templateDir = path.join(__dirname, "template", "docs");
      if (fs.existsSync(templateDir)) {
        for (const file of fs.readdirSync(templateDir)) {
          const filePath = path.join(templateDir, file);
          if (fs.statSync(filePath).isFile()) {
            const content = fs.readFileSync(filePath);
            const repoPath = `docs/${file}`;
            const sha = await getFileSHA(repoPath);
            await uploadFile(repoPath, content, `Add ${file}`, sha);
          }
        }
      }

      updateTray();
      if (setupWindow) {
        setupWindow.loadFile("setup-done.html");
      }
    }
  } catch (err) {
    dialog.showErrorBox("Setup Failed", err.message || String(err));
  }
}

app.on("window-all-closed", (e) => {
  e.preventDefault(); // Keep running in tray
});
