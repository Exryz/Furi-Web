// ==========================================================================
// Spotify Connect & Web API Integration for Frieren Startpage (PKCE Flow)
// ==========================================================================

const SCOPES = [
  'user-read-playback-state',
  'user-modify-playback-state',
  'user-read-currently-playing'
].join(' ');

let currentPlayback = null;
let progressTimer = null;
let currentProgressMs = 0;
let currentDurationMs = 1;
let isCurrentlyPlaying = false;

// 1. Storage Helpers
function getClientId() {
  return localStorage.getItem('spotify_client_id') || '';
}

function setClientId(id) {
  localStorage.setItem('spotify_client_id', id.trim());
}

function getAccessToken() {
  const token = localStorage.getItem('spotify_access_token');
  const expiry = parseInt(localStorage.getItem('spotify_token_expiry') || '0', 10);
  if (token && Date.now() < expiry) {
    return token;
  }
  return null;
}

function setAccessToken(token, expiresInSec) {
  localStorage.setItem('spotify_access_token', token);
  localStorage.setItem('spotify_token_expiry', (Date.now() + (expiresInSec - 60) * 1000).toString());
}

function clearAuth() {
  localStorage.removeItem('spotify_access_token');
  localStorage.removeItem('spotify_token_expiry');
  localStorage.removeItem('spotify_refresh_token');
  localStorage.removeItem('spotify_code_verifier');
}

// 2. Format Milliseconds to MM:SS
function formatTime(ms) {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}:${sec < 10 ? '0' : ''}${sec}`;
}

// 3. Cryptographic PKCE Helpers (Proof Key for Code Exchange)
function getRedirectUri() {
  if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getURL) {
    return chrome.runtime.getURL('index.html');
  }
  if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.getURL) {
    return browser.runtime.getURL('index.html');
  }
  return window.location.origin + window.location.pathname;
}

function generateRandomString(length) {
  const possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  const values = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(values).map(x => possible[x % possible.length]).join('');
}

async function generateCodeChallenge(codeVerifier) {
  const encoder = new TextEncoder();
  const data = encoder.encode(codeVerifier);
  const digest = await window.crypto.subtle.digest('SHA-256', data);
  return btoa(String.fromCharCode.apply(null, [...new Uint8Array(digest)]))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

// 4. PKCE Authorization Flow (response_type=code)
async function startAuthFlow() {
  const clientId = getClientId();
  if (!clientId) {
    openSettingsModal();
    return;
  }

  const verifier = generateRandomString(64);
  localStorage.setItem('spotify_code_verifier', verifier);
  const challenge = await generateCodeChallenge(verifier);

  const redirectUri = getRedirectUri();

  const params = new URLSearchParams({
    client_id: clientId,
    response_type: 'code',
    redirect_uri: redirectUri,
    code_challenge_method: 'S256',
    code_challenge: challenge,
    scope: SCOPES
  });

  window.location.href = `https://accounts.spotify.com/authorize?${params.toString()}`;
}

// 5. Exchange Authorization Code for Access & Refresh Tokens
async function exchangeCodeForToken(code) {
  const clientId = getClientId();
  let verifier = localStorage.getItem('spotify_code_verifier');
  const redirectUri = getRedirectUri();

  // If verifier wasn't created yet (e.g. manual entry without startAuthFlow), create dummy or check
  if (!clientId) {
    alert('Please enter and save your Client ID first!');
    return false;
  }
  if (!verifier) {
    verifier = generateRandomString(64);
    localStorage.setItem('spotify_code_verifier', verifier);
  }

  const body = new URLSearchParams({
    client_id: clientId,
    grant_type: 'authorization_code',
    code: code,
    redirect_uri: redirectUri,
    code_verifier: verifier
  });

  try {
    const res = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    });

    const data = await res.json();
    if (data.access_token) {
      setAccessToken(data.access_token, data.expires_in);
      if (data.refresh_token) {
        localStorage.setItem('spotify_refresh_token', data.refresh_token);
      }
      return true;
    } else {
      console.error('Failed to exchange code:', data);
      return false;
    }
  } catch (err) {
    console.error('Token Exchange Error:', err);
    return false;
  }
}

// 6. Refresh Token (Silently refreshes forever without user re-login)
async function refreshAccessToken() {
  const clientId = getClientId();
  const refreshToken = localStorage.getItem('spotify_refresh_token');

  if (!refreshToken || !clientId) {
    clearAuth();
    renderPlayerState();
    return null;
  }

  const body = new URLSearchParams({
    client_id: clientId,
    grant_type: 'refresh_token',
    refresh_token: refreshToken
  });

  try {
    const res = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    });

    const data = await res.json();
    if (data.access_token) {
      setAccessToken(data.access_token, data.expires_in);
      if (data.refresh_token) {
        localStorage.setItem('spotify_refresh_token', data.refresh_token);
      }
      return data.access_token;
    } else {
      clearAuth();
      renderPlayerState();
      return null;
    }
  } catch (err) {
    console.error('Token Refresh Error:', err);
    return null;
  }
}

// 7. General API Request Handler with Auto-Retry on Expire
async function spotifyApi(method, endpoint, body = null, isRetry = false) {
  let token = getAccessToken();
  if (!token) {
    token = await refreshAccessToken();
    if (!token) return null;
  }

  try {
    const res = await fetch(`https://api.spotify.com/v1${endpoint}`, {
      method: method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: body ? JSON.stringify(body) : null
    });

    if (res.status === 401 && !isRetry) {
      const newToken = await refreshAccessToken();
      if (newToken) {
        return spotifyApi(method, endpoint, body, true);
      }
      return null;
    }
    if (res.status === 204 || res.status === 202) {
      return true;
    }
    if (res.ok) {
      return await res.json();
    }
    return null;
  } catch (err) {
    console.error('Spotify API Error:', err);
    return null;
  }
}

// 8. Fetch Current Playback from Spotify Desktop
const ICONS = {
  play: `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" style="transform:translateX(1px);display:block;"><polygon points="6 4 20 12 6 20"></polygon></svg>`,
  pause: `<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" style="display:block;"><rect x="5" y="4" width="4" height="16" rx="1.5"></rect><rect x="15" y="4" width="4" height="16" rx="1.5"></rect></svg>`,
  prev: `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor" style="display:block;"><polygon points="19 20 9 12 19 4 19 20"></polygon><rect x="5" y="4" width="2.5" height="16" rx="1"></rect></svg>`,
  next: `<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor" style="display:block;"><polygon points="5 4 15 12 5 20 5 4"></polygon><rect x="16.5" y="4" width="2.5" height="16" rx="1"></rect></svg>`,
  shuffle: `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" style="display:block;"><path d="M16 3h5v5M4 20l17-17M21 16v5h-5M15 15l6 6M4 4l5 5"/></svg>`,
  gear: `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:block;"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"></path></svg>`
};

async function fetchPlayback() {
  const data = await spotifyApi('GET', '/me/player');
  if (data && data.item) {
    currentPlayback = data;
    renderPlayerActive(data);
  } else {
    currentPlayback = null;
    renderPlayerIdle();
  }
}

// 9. UI Render Functions
function renderPlayerState() {
  const clientId = getClientId();
  const token = getAccessToken();
  const refreshToken = localStorage.getItem('spotify_refresh_token');

  if (!clientId) {
    renderNoClientId();
  } else if (!token && !refreshToken) {
    renderNeedAuth();
  } else {
    fetchPlayback();
  }
}

function renderNoClientId() {
  const container = document.getElementById('spotify-player');
  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;width:100%;">
      <span style="font-size:0.85rem;color:var(--bd);">✦ Spotify Player (Setup Client ID)</span>
      <button class="sp-auth-btn" id="btn-config-client">⚙ Setup Client ID</button>
    </div>
  `;
  document.getElementById('btn-config-client').onclick = openSettingsModal;
}

function renderNeedAuth() {
  const container = document.getElementById('spotify-player');
  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;width:100%;">
      <span style="font-size:0.85rem;color:var(--bd);">✦ Spotify Music Player</span>
      <div style="display:flex;align-items:center;gap:0.75rem;">
        <span class="sp-settings-icon" id="btn-open-settings" title="Change Client ID">${ICONS.gear}</span>
        <button class="sp-auth-btn" id="btn-connect-spotify">✦ Connect Spotify</button>
      </div>
    </div>
  `;
  document.getElementById('btn-connect-spotify').onclick = startAuthFlow;
  document.getElementById('btn-open-settings').onclick = openSettingsModal;
}

function renderPlayerIdle() {
  const container = document.getElementById('spotify-player');
  container.innerHTML = `
    <div style="display:flex;align-items:center;justify-content:space-between;width:100%;font-size:0.84rem;">
      <span style="color:var(--bp);opacity:0.9;">🎧 Spotify Desktop is Idle</span>
      <div style="display:flex;align-items:center;gap:0.8rem;">
        <span style="font-size:0.75rem;color:var(--bd);opacity:0.75;">Play music on PC to sync</span>
        <span class="sp-settings-icon" id="btn-open-settings" title="Settings">${ICONS.gear}</span>
      </div>
    </div>
  `;
  document.getElementById('btn-open-settings').onclick = openSettingsModal;
}

function renderPlayerActive(data) {
  const container = document.getElementById('spotify-player');
  const item = data.item;
  isCurrentlyPlaying = data.is_playing;
  currentProgressMs = data.progress_ms || 0;
  currentDurationMs = item.duration_ms || 1;

  const artUrl = item.album.images[0]?.url || '';
  const title = item.name;
  const artist = item.artists.map((a) => a.name).join(', ');
  const pct = Math.min(100, (currentProgressMs / currentDurationMs) * 100);

  container.innerHTML = `
    <div class="sp-body">
      <img class="sp-art" src="${artUrl}" alt="art" />
      <div class="sp-info">
        <div class="sp-title" title="${title}">${title}</div>
        <div class="sp-artist" title="${artist}">${artist}</div>
      </div>
      <div class="sp-controls">
        <button class="sp-btn" id="sp-shuffle" title="Toggle Shuffle">${ICONS.shuffle}</button>
        <button class="sp-btn" id="sp-prev" title="Previous">${ICONS.prev}</button>
        <button class="sp-btn play-btn" id="sp-toggle" title="${isCurrentlyPlaying ? 'Pause' : 'Play'}">
          ${isCurrentlyPlaying ? ICONS.pause : ICONS.play}
        </button>
        <button class="sp-btn" id="sp-next" title="Next">${ICONS.next}</button>
        <span class="sp-settings-icon" id="btn-open-settings" style="margin-left:0.2rem;" title="Settings">${ICONS.gear}</span>
      </div>
    </div>
    <div class="sp-progress-container">
      <span class="sp-time" id="sp-curr-time">${formatTime(currentProgressMs)}</span>
      <div class="sp-bar-bg" id="sp-seek-bar">
        <div class="sp-bar-fill" id="sp-fill" style="width: ${pct}%;"></div>
      </div>
      <span class="sp-time">${formatTime(currentDurationMs)}</span>
    </div>
  `;

  if (data.shuffle_state) {
    const shuf = document.getElementById('sp-shuffle');
    if (shuf) {
      shuf.style.color = '#ffffff';
      shuf.style.filter = 'drop-shadow(0 0 8px #7fc3fd)';
    }
  }

  // Button actions
  document.getElementById('sp-toggle').onclick = async () => {
    await spotifyApi('PUT', isCurrentlyPlaying ? '/me/player/pause' : '/me/player/play');
    setTimeout(fetchPlayback, 300);
  };
  document.getElementById('sp-prev').onclick = async () => {
    await spotifyApi('POST', '/me/player/previous');
    setTimeout(fetchPlayback, 300);
  };
  document.getElementById('sp-next').onclick = async () => {
    await spotifyApi('POST', '/me/player/next');
    setTimeout(fetchPlayback, 300);
  };
  document.getElementById('sp-shuffle').onclick = async () => {
    await spotifyApi('PUT', `/me/player/shuffle?state=${!data.shuffle_state}`);
    setTimeout(fetchPlayback, 300);
  };
  document.getElementById('btn-open-settings').onclick = openSettingsModal;

  // Click-to-seek
  document.getElementById('sp-seek-bar').onclick = async (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const clickX = e.clientX - rect.left;
    const ratio = Math.max(0, Math.min(1, clickX / rect.width));
    const targetMs = Math.floor(ratio * currentDurationMs);
    await spotifyApi('PUT', `/me/player/seek?position_ms=${targetMs}`);
    currentProgressMs = targetMs;
    setTimeout(fetchPlayback, 300);
  };

  // Smooth live ticker
  clearInterval(progressTimer);
  if (isCurrentlyPlaying) {
    progressTimer = setInterval(() => {
      currentProgressMs += 1000;
      if (currentProgressMs <= currentDurationMs) {
        const fillEl = document.getElementById('sp-fill');
        const timeEl = document.getElementById('sp-curr-time');
        if (fillEl) fillEl.style.width = `${(currentProgressMs / currentDurationMs) * 100}%`;
        if (timeEl) timeEl.textContent = formatTime(currentProgressMs);
      }
    }, 1000);
  }
}

// 10. Settings Modal (Client ID & Redirect URI Display)
function openSettingsModal() {
  const modal = document.getElementById('settings-modal');
  const input = document.getElementById('client-id-input');
  const redirectDisplay = document.getElementById('redirect-uri-display');

  input.value = getClientId();
  const currentRedirectUri = getRedirectUri();
  if (redirectDisplay) {
    redirectDisplay.value = currentRedirectUri;
  }

  modal.style.display = 'flex';
}

function closeSettingsModal() {
  const modal = document.getElementById('settings-modal');
  modal.style.display = 'none';
}

function saveSettings() {
  const input = document.getElementById('client-id-input');
  const val = input.value.trim();
  if (val) {
    setClientId(val);
    closeSettingsModal();
    startAuthFlow();
  }
}

async function handleManualCode() {
  const input = document.getElementById('manual-code-input');
  if (!input) return;
  let val = input.value.trim();
  if (!val) return;
  if (val.includes('code=')) {
    const match = val.match(/code=([^&]+)/);
    if (match) val = decodeURIComponent(match[1]);
  }
  const ok = await exchangeCodeForToken(val);
  if (ok) {
    closeSettingsModal();
    renderPlayerState();
  } else {
    alert('Failed to authorize with this code. Please make sure your Client ID is saved first.');
  }
}

// 11. Initialization & Callback Handling
document.addEventListener('DOMContentLoaded', async () => {
  // Check if Spotify redirected back with ?code=...
  const urlParams = new URLSearchParams(window.location.search);
  const code = urlParams.get('code');

  if (code) {
    const ok = await exchangeCodeForToken(code);
    // Clean query params from URL
    window.history.replaceState(null, '', window.location.pathname);
  }

  renderPlayerState();

  // Periodic polling every 3.5 seconds
  setInterval(() => {
    if (getAccessToken() || localStorage.getItem('spotify_refresh_token')) {
      fetchPlayback();
    }
  }, 3500);

  // Modal actions
  document.getElementById('modal-cancel').onclick = closeSettingsModal;
  document.getElementById('modal-save').onclick = saveSettings;
  const submitCodeBtn = document.getElementById('btn-submit-code');
  if (submitCodeBtn) {
    submitCodeBtn.onclick = handleManualCode;
  }
  document.getElementById('settings-modal').onclick = (e) => {
    if (e.target.id === 'settings-modal') closeSettingsModal();
  };

  const copyBtn = document.getElementById('btn-copy-uri');
  if (copyBtn) {
    copyBtn.onclick = () => {
      const redirectDisplay = document.getElementById('redirect-uri-display');
      redirectDisplay.select();
      navigator.clipboard.writeText(redirectDisplay.value).then(() => {
        copyBtn.textContent = 'Copied!';
        setTimeout(() => { copyBtn.textContent = 'Copy'; }, 2000);
      });
    };
  }
});
