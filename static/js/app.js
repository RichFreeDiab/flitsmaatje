// FlitsMaatje frontend logic

const TYPE_LABELS = {
  flitser_vast: "Vaste flitser",
  flitser_mobiel: "Mobiele flitser",
  trajectcontrole: "Trajectcontrole",
  politie: "Politiecontrole",
  ongeval: "Ongeval",
  file: "File",
  gevaar: "Gevaar op de weg",
  wegwerkzaamheden: "Wegwerkzaamheden",
};

const TYPE_ICONS = {
  flitser_vast: "📷",
  flitser_mobiel: "🚐",
  trajectcontrole: "📡",
  politie: "👮",
  ongeval: "💥",
  file: "🚗",
  gevaar: "⚠️",
  wegwerkzaamheden: "🚧",
};

// Binnen welke afstand (meters) we waarschuwen, per type
const WARN_DISTANCE_M = {
  flitser_vast: 800,
  flitser_mobiel: 800,
  trajectcontrole: 1500,
  politie: 800,
  ongeval: 600,
  file: 1000,
  gevaar: 500,
  wegwerkzaamheden: 500,
};

let map = null;
let userMarker = null;
let userPos = null;       // {lat, lng}
let lastPos = null;       // voor afstand/snelheid berekening als speed niet beschikbaar is
let lastPosTime = null;
let markers = {};         // id -> leaflet marker
let warnedIds = new Set();
let pollTimer = null;

const speedValueEl = document.getElementById("speed-value");
const speedPanelEl = document.getElementById("speed-panel");
const limitRowEl = document.getElementById("limit-row");
const limitBadgeEl = document.getElementById("limit-badge");
const fineBanner = document.getElementById("fine-banner");
const fineText = document.getElementById("fine-text");
const alertBanner = document.getElementById("alert-banner");
const alertLabel = document.getElementById("alert-label");
const alertDistance = document.getElementById("alert-distance");
const reportFab = document.getElementById("report-fab");
const reportMenu = document.getElementById("report-menu");
const reportCancel = document.getElementById("report-cancel");

let currentSpeedKmh = null;\nlet currentHeading = null;
let lastSpeedCheckPos = null;     // laatste positie waarvoor we /api/speed-check hebben aangeroepen
let speedCheckTimer = null;
const SPEED_CHECK_MIN_DISTANCE_M = 30;  // alleen opnieuw checken na zoveel meter verplaatsing
const SPEED_CHECK_MIN_INTERVAL_MS = 4000;
let lastSpeedCheckTime = 0;

function initMap(lat, lng) {
  map = L.map("map", { zoomControl: true }).setView([lat, lng], 15);\n  window.flitsmaatjeMap = map;
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution: "&copy; OpenStreetMap contributors",
    maxZoom: 19,
  }).addTo(map);

  const userIcon = L.divIcon({
    className: "",
    html: '<div style="background:#4285F4;width:16px;height:16px;border-radius:50%;border:3px solid white;box-shadow:0 0 6px rgba(0,0,0,0.4)"></div>',
    iconSize: [22, 22],
    iconAnchor: [11, 11],
  });
  userMarker = L.marker([lat, lng], { icon: userIcon, zIndexOffset: 1000 }).addTo(map);
}

function bearingDegrees(lat1, lng1, lat2, lng2) {\n  const p1 = lat1 * Math.PI / 180;\n  const p2 = lat2 * Math.PI / 180;\n  const dl = (lng2 - lng1) * Math.PI / 180;\n  return (Math.atan2(Math.sin(dl) * Math.cos(p2), Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl)) * 180 / Math.PI + 360) % 360;\n}\n\nfunction haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const p1 = (lat1 * Math.PI) / 180;
  const p2 = (lat2 * Math.PI) / 180;
  const dphi = ((lat2 - lat1) * Math.PI) / 180;
  const dlambda = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dphi / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dlambda / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

function updateSpeed(position) {
  let kmh = null;

  if (position.coords.speed !== null && position.coords.speed >= 0) {
    kmh = position.coords.speed * 3.6;
  } else if (lastPos && lastPosTime) {
    const dist = haversineMeters(lastPos.lat, lastPos.lng, position.coords.latitude, position.coords.longitude);
    const dt = (position.timestamp - lastPosTime) / 1000;
    if (dt > 0) kmh = (dist / dt) * 3.6;
  }

  if (kmh !== null && !isNaN(kmh)) {
    currentSpeedKmh = kmh;
    speedValueEl.textContent = Math.round(kmh);
  }

  lastPos = { lat: position.coords.latitude, lng: position.coords.longitude };
  lastPosTime = position.timestamp;
}

function onPosition(position) {
  const lat = position.coords.latitude;
  const lng = position.coords.longitude;
  userPos = { lat, lng };\n  if (position.coords.heading !== null && Number.isFinite(position.coords.heading)) currentHeading = position.coords.heading;

  if (!map) {
    initMap(lat, lng);
    startPolling();
  } else {
    userMarker.setLatLng([lat, lng]);
    map.panTo([lat, lng], { animate: true });
  }

  updateSpeed(position);
  checkProximityWarnings();
  maybeCheckSpeedLimit();
}

function onPositionError(err) {
  console.error("GPS fout:", err);
  if (!map) {
    // Val terug op een standaardlocatie (Almere) zodat de app toch werkt zonder GPS
    initMap(52.3508, 5.2647);
    startPolling();
  }
}

function startGPS() {
  if (!navigator.geolocation) {
    alert("Geolocatie wordt niet ondersteund door deze browser.");
    return;
  }
  navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true,
    maximumAge: 1000,
    timeout: 10000,
  });
  requestWakeLock();
}

function startPolling() {
  fetchReports();
  pollTimer = setInterval(fetchReports, 15000);
}

async function fetchReports() {
  if (!userPos) return;
  try {
    const res = await fetch(`/api/reports?lat=${userPos.lat}&lng=${userPos.lng}&radius_km=15`);
    const data = await res.json();
    renderReports(data.reports || []);
  } catch (e) {
    console.error("Kon meldingen niet ophalen:", e);
  }
}

function renderReports(reports) {
  const seenIds = new Set();

  reports.forEach((r) => {
    seenIds.add(r.id);
    if (markers[r.id]) {
      return; // marker bestaat al, niets te doen
    }
    const icon = L.divIcon({
      className: "",
      html: `<div style="font-size:24px;line-height:24px;filter:drop-shadow(0 1px 2px rgba(0,0,0,0.5))">${TYPE_ICONS[r.type] || "❓"}</div>`,
      iconSize: [28, 28],
      iconAnchor: [14, 14],
    });
    const marker = L.marker([r.lat, r.lng], { icon }).addTo(map);\n    marker.report = r;
    marker.bindPopup(buildPopupHtml(r));
    marker.on("popupopen", (e) => attachVoteHandlers(e.popup, r.id));
    markers[r.id] = marker;
  });

  // Verwijder markers die niet meer in de actieve lijst staan (verlopen of verwijderd)
  Object.keys(markers).forEach((id) => {
    if (!seenIds.has(id)) {
      map.removeLayer(markers[id]);
      delete markers[id];
      warnedIds.delete(id);
    }
  });
}

function buildPopupHtml(r) {
  const label = TYPE_LABELS[r.type] || r.type;
  return `
    <div>
      <strong>${TYPE_ICONS[r.type] || ""} ${label}</strong><br>
      <small>${r.distance_km} km verderop</small><br>
      <small>👍 ${r.confirms} &nbsp; 👎 ${r.denies}</small><br>
      <button class="vote-confirm" data-id="${r.id}" data-vote="confirm">Nog aanwezig</button>
      <button class="vote-deny" data-id="${r.id}" data-vote="deny">Niet meer aanwezig</button>
    </div>
  `;
}

function attachVoteHandlers(popup, reportId) {
  const el = popup.getElement();
  if (!el) return;
  el.querySelectorAll("button[data-vote]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const vote = btn.getAttribute("data-vote");
      await fetch(`/api/reports/${reportId}/vote`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ vote }),
      });
      popup.close();
      fetchReports();
    });
  });
}

function checkProximityWarnings() {
  if (!userPos) return;
  let closest = null;
  let closestDist = Infinity;

  Object.entries(markers).forEach(([id, marker]) => {
    const pos = marker.getLatLng();
    const dist = haversineMeters(userPos.lat, userPos.lng, pos.lat, pos.lng);
    if (dist < closestDist) {
      closestDist = dist;
      closest = { id, pos };
    }
  });

  if (!closest) {
    hideAlert();
    return;
  }

  // Bepaal type via marker -> we slaan het type niet direct op marker, dus zoek het opnieuw op via popup
  // Eenvoudiger: gebruik vaste waarschuwingsafstand van 800m voor alle types als fallback
  const reportType = findTypeForMarkerId(closest.id);
  const threshold = WARN_DISTANCE_M[reportType] || 800;

  if (closestDist <= threshold) {
    showAlert(reportType, Math.round(closestDist));
  } else {
    hideAlert();
  }
}

let typeCache = {};
function findTypeForMarkerId(id) {
  return typeCache[id] || null;
}

function showAlert(type, distanceM) {
  const label = TYPE_LABELS[type] || "Melding";
  const icon = TYPE_ICONS[type] || "⚠️";
  document.getElementById("alert-icon").textContent = icon;
  alertLabel.textContent = label;
  alertDistance.textContent = `${distanceM} m`;
  alertBanner.classList.remove("hidden");
  document.body.classList.add("alert-active");
  playAlertSound(type);
  vibrateAlert();
}

function hideAlert() {
  alertBanner.classList.add("hidden");
  document.body.classList.remove("alert-active");
}

let audioCtx = null;
let audioUnlocked = false;

function unlockAudio() {
  if (audioUnlocked) return;
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === "suspended") audioCtx.resume();
    audioUnlocked = true;
  } catch (e) {
    // geen audio
  }
}

function beep(freq, duration, volume, type = "sine") {
  if (!audioCtx) return;
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  osc.connect(gain);
  gain.connect(audioCtx.destination);
  gain.gain.setValueAtTime(volume, audioCtx.currentTime);
  osc.start();
  osc.stop(audioCtx.currentTime + duration);
}

function playAlertSound(type) {
  const key = type + "_beeped";
  if (sessionStorage.getItem(key) === "recent") return;
  unlockAudio();
  try {
    beep(880, 0.15, 0.35);
    setTimeout(() => beep(1100, 0.15, 0.35), 180);
  } catch (e) {
    // audio niet beschikbaar
  }
  sessionStorage.setItem(key, "recent");
  setTimeout(() => sessionStorage.removeItem(key), 25000);
}

function vibrateAlert() {
  if (navigator.vibrate) navigator.vibrate([200, 100, 200, 100, 200]);
}

// Houd typeCache bij wanneer renderReports draait
const originalRenderReports = renderReports;
renderReports = function (reports) {
  reports.forEach((r) => (typeCache[r.id] = r.type));
  originalRenderReports(reports);
  checkProximityWarnings();
};

// --- Snelheidslimiet + boete-indicatie (Overpass/OSM via backend) ---

function maybeCheckSpeedLimit() {
  if (!userPos) return;

  const now = Date.now();
  const movedEnough = !lastSpeedCheckPos ||
    haversineMeters(lastSpeedCheckPos.lat, lastSpeedCheckPos.lng, userPos.lat, userPos.lng) >= SPEED_CHECK_MIN_DISTANCE_M;

  if (!movedEnough && (now - lastSpeedCheckTime) < SPEED_CHECK_MIN_INTERVAL_MS) return;
  if ((now - lastSpeedCheckTime) < 1500) return; // hard minimum tegen spam

  lastSpeedCheckPos = { ...userPos };
  lastSpeedCheckTime = now;
  fetchSpeedCheck();
}

async function fetchSpeedCheck() {
  if (!userPos) return;
  const speedParam = currentSpeedKmh !== null ? `&speed_kmh=${currentSpeedKmh.toFixed(1)}` : "";
  try {
    const res = await fetch(`/api/speed-check?lat=${userPos.lat}&lng=${userPos.lng}${speedParam}`);
    const data = await res.json();
    renderSpeedLimit(data.limit, data.fine);
  } catch (e) {
    console.error("Kon snelheidslimiet niet ophalen:", e);
  }
}

function renderSpeedLimit(limit, fine) {
  if (!limit || limit.maxspeed === null || limit.maxspeed === undefined) {
    limitRowEl.classList.add("hidden");
    speedPanelEl.classList.remove("speeding");
    fineBanner.classList.add("hidden");
    return;
  }

  limitBadgeEl.textContent = limit.maxspeed;
  limitRowEl.classList.remove("hidden");

  if (!fine || fine.bedrag === 0) {
    speedPanelEl.classList.remove("speeding");
    fineBanner.classList.add("hidden");
    return;
  }

  speedPanelEl.classList.add("speeding");

  if (fine.om_zaak) {
    fineText.textContent = `${fine.excess_kmh} km/u te hard — geen vaste boete, dagvaarding OM (mogelijk rijontzegging)`;
  } else {
    fineText.textContent = `${fine.excess_kmh} km/u te hard — indicatief €${fine.bedrag} (incl. €${ADMIN_COST_DISPLAY} adm.kosten)`;
  }
  fineBanner.classList.remove("hidden");
  playFineBeep();
}

const ADMIN_COST_DISPLAY = 9;

let lastFineBeepTime = 0;
function playFineBeep() {
  const now = Date.now();
  if (now - lastFineBeepTime < 20000) return; // niet vaker dan elke 20s zeuren
  lastFineBeepTime = now;
  unlockAudio();
  try {
    beep(440, 0.3, 0.3, "square");
  } catch (e) {
    // geen geluid beschikbaar
  }
}

// --- Melding maken via FAB knop ---
reportFab.addEventListener("click", () => {
  reportMenu.classList.toggle("hidden");
});
reportCancel.addEventListener("click", () => {
  reportMenu.classList.add("hidden");
});

document.querySelectorAll(".report-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    if (!userPos) {
      alert("Je locatie is nog niet bekend.");
      return;
    }
    const type = btn.getAttribute("data-type");
    reportMenu.classList.add("hidden");
    try {
      await fetch("/api/reports", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type, lat: userPos.lat, lng: userPos.lng, heading: currentHeading }),
      });
      fetchReports();
    } catch (e) {
      console.error("Melding plaatsen mislukt:", e);
    }
  });
});

startGPS();

// --- PWA: service worker, install-tip, audio ontgrendelen ---

let wakeLock = null;
async function requestWakeLock() {
  try {
    if ("wakeLock" in navigator) {
      wakeLock = await navigator.wakeLock.request("screen");
      wakeLock.addEventListener("release", () => { wakeLock = null; });
    }
  } catch (e) {
    // niet ondersteund of geweigerd
  }
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && userPos) requestWakeLock();
});

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}

const installHint = document.getElementById("install-hint");
const installHintClose = document.getElementById("install-hint-close");
const isStandalone = window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone;

if (!isStandalone && !localStorage.getItem("install_hint_dismissed")) {
  installHint.classList.remove("hidden");
}
installHintClose.addEventListener("click", () => {
  installHint.classList.add("hidden");
  localStorage.setItem("install_hint_dismissed", "1");
});

["click", "touchstart"].forEach((ev) => {
  document.addEventListener(ev, unlockAudio, { once: true, passive: true });
});
