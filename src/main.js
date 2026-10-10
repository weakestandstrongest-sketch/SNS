const { app, BrowserWindow, WebContentsView, Menu, ipcMain, session, shell, clipboard } = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const { COLUMNS, AUTH_DOMAINS } = require('./columns');

const ZOOM_MIN = 0.5;
const ZOOM_MAX = 1.5;

// --- 設定の保存（表示する列・ズーム・ウィンドウサイズ） -------------------------

const settingsPath = () => path.join(app.getPath('userData'), 'settings.json');

function loadSettings() {
  const defaults = {
    visible: Object.fromEntries(COLUMNS.map((c) => [c.id, true])),
    zoom: Object.fromEntries(COLUMNS.map((c) => [c.id, 1])),
    window: { width: 1600, height: 950 },
  };
  try {
    const saved = JSON.parse(fs.readFileSync(settingsPath(), 'utf8'));
    return {
      visible: { ...defaults.visible, ...saved.visible },
      zoom: { ...defaults.zoom, ...saved.zoom },
      window: { ...defaults.window, ...saved.window },
    };
  } catch {
    return defaults;
  }
}

function saveSettings() {
  try {
    fs.writeFileSync(settingsPath(), JSON.stringify(settings, null, 2));
  } catch (err) {
    console.error('設定を保存できませんでした:', err);
  }
}

let settings;

// --- ユーザーエージェント --------------------------------------------------------
// Electron の UA のままだと Google などが「安全でないブラウザ」としてログインを拒否するため、
// 通常の Chrome と同じ UA を名乗る。

function chromeUserAgent() {
  const platform = app.userAgentFallback.match(/\(([^)]+)\)/)?.[1] ?? 'Windows NT 10.0; Win64; x64';
  return `Mozilla/5.0 (${platform}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${process.versions.chrome} Safari/537.36`;
}

// --- URL の判定 ------------------------------------------------------------------

function hostMatches(host, domains) {
  return domains.some((d) => host === d || host.endsWith(`.${d}`));
}

function isAllowedInColumn(column, url) {
  try {
    const { protocol, hostname } = new URL(url);
    if (protocol === 'about:') return true;
    if (protocol !== 'https:' && protocol !== 'http:') return false;
    return hostMatches(hostname, column.domains) || hostMatches(hostname, AUTH_DOMAINS);
  } catch {
    return false;
  }
}

function isAuthUrl(url) {
  try {
    return hostMatches(new URL(url).hostname, AUTH_DOMAINS);
  } catch {
    return false;
  }
}

function openExternal(url) {
  if (/^https?:\/\//.test(url)) shell.openExternal(url);
}

// --- ウィンドウと各 SNS の列 ------------------------------------------------------

let win = null;
const views = new Map(); // id -> { column, view, loaded }

function sendState(id, state) {
  if (win && !win.isDestroyed()) win.webContents.send('state', id, state);
}

function createColumnView(column) {
  const ses = session.fromPartition(`persist:${column.id}`);
  ses.setUserAgent(chromeUserAgent());
  // 通知・カメラ・位置情報などは許可しない。全画面とコピーだけ許可する。
  ses.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(['fullscreen', 'clipboard-sanitized-write'].includes(permission));
  });

  const view = new WebContentsView({
    webPreferences: {
      session: ses,
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });
  view.setBackgroundColor('#0f1115');
  view.setVisible(false);
  const wc = view.webContents;

  const pushState = () =>
    sendState(column.id, {
      title: wc.getTitle(),
      url: wc.getURL(),
      loading: wc.isLoading(),
      canGoBack: wc.navigationHistory.canGoBack(),
      canGoForward: wc.navigationHistory.canGoForward(),
      zoom: settings.zoom[column.id],
    });

  wc.on('did-start-loading', pushState);
  wc.on('did-stop-loading', pushState);
  wc.on('page-title-updated', pushState);
  wc.on('did-navigate-in-page', pushState);
  wc.on('did-navigate', () => {
    // 別のドメインへ移動するとズームが戻ることがあるので毎回かけ直す
    wc.setZoomFactor(settings.zoom[column.id]);
    pushState();
  });

  // 列の外のサイトへのリンクは既定のブラウザで開く
  wc.on('will-navigate', (event) => {
    if (!isAllowedInColumn(column, event.url)) {
      event.preventDefault();
      openExternal(event.url);
    }
  });

  wc.setWindowOpenHandler(({ url }) => {
    // 「Google でログイン」などのポップアップは、同じログイン情報を持つ小窓で開く
    if (isAuthUrl(url) || url === 'about:blank') {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: { width: 520, height: 720, autoHideMenuBar: true, parent: win },
      };
    }
    // 同じ SNS 内の「新しいタブで開く」はその列の中で開く
    if (isAllowedInColumn(column, url)) {
      wc.loadURL(url).catch(() => {});
    } else {
      openExternal(url);
    }
    return { action: 'deny' };
  });

  // YouTube の全画面ボタンなど
  wc.on('enter-html-full-screen', () => setFullScreen(column.id, true));
  wc.on('leave-html-full-screen', () => setFullScreen(column.id, false));

  wc.on('context-menu', (_event, params) => showContextMenu(wc, params));

  // オフラインなどで読み込めなかったときは真っ黒のままにせず案内を出す
  wc.on('did-fail-load', (_event, errorCode, errorDescription, url, isMainFrame) => {
    if (!isMainFrame || errorCode === -3) return; // -3 はユーザー操作などによる中断
    wc.loadURL(errorPageUrl(column, url, errorDescription)).catch(() => {});
  });

  return view;
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (ch) => `&#${ch.charCodeAt(0)};`);
}

function errorPageUrl(column, url, description) {
  const html = `<!doctype html><meta charset="utf-8"><title>${escapeHtml(column.name)}</title>
<body style="margin:0;height:100vh;display:grid;place-items:center;background:#0f1115;color:#e6e8ec;font:14px system-ui,sans-serif;text-align:center">
<div><p style="font-size:16px;font-weight:600">${escapeHtml(column.name)} を読み込めませんでした</p>
<p style="color:#8b919c">${escapeHtml(description)}</p>
<p>インターネット接続を確認して、<a style="color:${column.color}" href="${escapeHtml(url || column.home)}">もう一度読み込む</a></p></div>`;
  return `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;
}

function setFullScreen(id, flag) {
  if (!win || win.isDestroyed()) return;
  win.webContents.send('fullscreen', flag ? id : null);
  win.setFullScreen(flag);
}

function showContextMenu(wc, params) {
  const template = [];
  if (params.linkURL) {
    template.push(
      { label: 'リンクをブラウザで開く', click: () => openExternal(params.linkURL) },
      { label: 'リンクのアドレスをコピー', click: () => clipboard.writeText(params.linkURL) },
      { type: 'separator' },
    );
  }
  if (params.isEditable) {
    template.push(
      { label: '切り取り', role: 'cut' },
      { label: 'コピー', role: 'copy' },
      { label: '貼り付け', role: 'paste' },
      { type: 'separator' },
    );
  } else if (params.selectionText) {
    template.push({ label: 'コピー', role: 'copy' }, { type: 'separator' });
  }
  template.push(
    { label: '戻る', enabled: wc.navigationHistory.canGoBack(), click: () => wc.navigationHistory.goBack() },
    { label: '進む', enabled: wc.navigationHistory.canGoForward(), click: () => wc.navigationHistory.goForward() },
    { label: '再読み込み', click: () => wc.reload() },
    { type: 'separator' },
    { label: 'このページをブラウザで開く', click: () => openExternal(wc.getURL()) },
  );
  Menu.buildFromTemplate(template).popup({ window: win });
}

function createWindow() {
  const { width, height, x, y } = settings.window;
  win = new BrowserWindow({
    width,
    height,
    x,
    y,
    minWidth: 800,
    minHeight: 500,
    title: 'SNS Crossover',
    backgroundColor: '#0f1115',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  for (const column of COLUMNS) {
    const view = createColumnView(column);
    win.contentView.addChildView(view);
    views.set(column.id, { column, view, loaded: false });
  }

  win.loadFile(path.join(__dirname, 'index.html'));

  win.on('close', () => {
    if (!win.isFullScreen()) settings.window = win.getNormalBounds();
    saveSettings();
  });
  win.on('closed', () => {
    for (const { view } of views.values()) view.webContents.close();
    views.clear();
    win = null;
  });
}

// --- 画面（renderer）とのやりとり -------------------------------------------------

ipcMain.handle('init', () => ({
  columns: COLUMNS.map(({ id, name, color }) => ({ id, name, color })),
  visible: settings.visible,
  zoom: settings.zoom,
}));

// 画面側で計算した各列の表示位置を受け取って、SNS の画面をそこに重ねる
ipcMain.on('layout', (_event, list) => {
  for (const { id, bounds } of list) {
    const entry = views.get(id);
    if (!entry) continue;
    if (!bounds) {
      entry.view.setVisible(false);
      continue;
    }
    entry.view.setBounds(bounds);
    entry.view.setVisible(true);
    // 隠れている列は、初めて表示されたときに読み込む
    if (!entry.loaded) {
      entry.loaded = true;
      entry.view.webContents.setZoomFactor(settings.zoom[id]);
      entry.view.webContents.loadURL(entry.column.home).catch(() => {});
    }
  }
});

ipcMain.on('visible', (_event, visible) => {
  settings.visible = { ...settings.visible, ...visible };
  saveSettings();
});

ipcMain.on('action', (_event, id, action) => {
  const targets = id === '*' ? [...views.values()] : [views.get(id)].filter(Boolean);
  for (const { column, view, loaded } of targets) {
    const wc = view.webContents;
    switch (action) {
      case 'back':
        if (wc.navigationHistory.canGoBack()) wc.navigationHistory.goBack();
        break;
      case 'forward':
        if (wc.navigationHistory.canGoForward()) wc.navigationHistory.goForward();
        break;
      case 'reload':
        if (loaded) wc.reload();
        break;
      case 'home':
        wc.loadURL(column.home).catch(() => {});
        break;
      case 'zoomIn':
      case 'zoomOut': {
        const step = action === 'zoomIn' ? 0.1 : -0.1;
        const zoom = Math.round(Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, settings.zoom[column.id] + step)) * 10) / 10;
        settings.zoom[column.id] = zoom;
        wc.setZoomFactor(zoom);
        sendState(column.id, { zoom });
        saveSettings();
        break;
      }
      case 'external':
        openExternal(wc.getURL());
        break;
    }
  }
});

// --- 起動 ------------------------------------------------------------------------

app.whenReady().then(() => {
  settings = loadSettings();
  app.userAgentFallback = chromeUserAgent();

  // macOS ではコピー＆ペーストにメニューが必要
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      ...(process.platform === 'darwin' ? [{ role: 'appMenu' }] : []),
      { role: 'editMenu' },
      { role: 'windowMenu' },
    ]),
  );

  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
