(() => {
  const API = "/api/nearby-alert";
  const POLL_MS = 8000;
  const ALARM_THRESHOLDS = [600, 400, 200, 100];

  const widgetEl = document.getElementById("flits-widget");
  const statusEl = document.getElementById("status-pill");
  const coordsEl = document.getElementById("coords");
  const navHintEl = document.getElementById("nav-hint");
  const notifEl = document.getElementById("carplay-notif");
  const notifIconEl = document.getElementById("notif-icon");
  const notifTitleEl = document.getElementById("notif-title");
  const notifSubEl = document.getElementById("notif-sub");
  const alertModalEl = document.getElementById("carplay-alert-modal");
  const alertModalTitleEl = document.getElementById("alert-modal-title");
  const drivingTaskListEl = document.getElementById("driving-task-list");
  const panelNavEl = document.getElementById("panel-nav");
  const panelDrivingEl = document.getElementById("panel-driving-task");
  const speechToggle = document.getElementById("toggle-speech");

  let lat = 52.3676;
  let lng = 4.9041;
  let pollTimer = null;
  let driveTimer = null;
  let alertDismissTimer = null;
  let modalDismissTimer = null;
  let mode = "manual";
  let carPlayApp = "flitsmeister";
  let lastAlertId = null;
  let passedThresholds = new Set();
  let lastSpokenAt = 0;

  const demoRoutes = {
    amsterdam: {
      label: "Demo-rit: Flitsmeister navigeert, FlitsMaatje waarschuwt",
      demoFlitser: { lat: 52.3688, lng: 4.9060 },
      points: [
        [52.3645, 4.8980],
        [52.3658, 4.9005],
        [52.3665, 4.9018],
        [52.3670, 4.9025],
        [52.3675, 4.9035],
        [52.3680, 4.9045],
        [52.3682, 4.9048],
        [52.3685, 4.9055],
        [52.3688, 4.9060],
        [52.3692, 4.9068],
        [52.3695, 4.9070],
        [52.3705, 4.9085],
        [52.3715, 4.9100],
      ],
    },
  };

  let map;
  let marker;
  let alertMarker;

  function setStatus(text) {
    statusEl.textContent = text;
  }

  function formatCoords() {
    coordsEl.textContent = `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function setCarPlayApp(app) {
    carPlayApp = app;
    document.querySelectorAll(".mode-btn").forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.mode === app);
    });
    document.querySelectorAll(".app-tile[data-app]").forEach((tile) => {
      tile.classList.toggle("active", tile.dataset.app === app);
    });

    const isFlitsMaatje = app === "flitsmaatje";
    panelNavEl.classList.toggle("hidden", isFlitsMaatje);
    panelDrivingEl.classList.toggle("hidden", !isFlitsMaatje);

    if (isFlitsMaatje) {
      hideCarPlayNotif();
      navHintEl.innerHTML = "<strong>FlitsMaatje</strong>Driving Task — lijst + alert";
    } else {
      hideAlertModal();
      navHintEl.innerHTML = "<strong>Flitsmeister</strong>Route actief — FlitsMaatje waarschuwt op de achtergrond";
    }
  }

  function renderDrivingTaskList(alert) {
    if (!alert) {
      drivingTaskListEl.innerHTML = '<p class="driving-task-empty">Geen meldingen in de buurt</p>';
      return;
    }
    drivingTaskListEl.innerHTML = `
      <div class="driving-task-item">
        <strong>${escapeHtml(alert.icon)} ${escapeHtml(alert.label)}</strong>
        <span>Over ${alert.distance_m} m — Dichtstbijzijnde melding</span>
      </div>
    `;
  }

  function showCarPlayNotif(alert) {
    notifIconEl.textContent = alert.icon;
    notifTitleEl.textContent = alert.label;
    notifSubEl.textContent = `Over ${alert.distance_m} meter`;
    notifEl.classList.remove("hidden");
    clearTimeout(alertDismissTimer);
    alertDismissTimer = setTimeout(hideCarPlayNotif, 7000);
  }

  function hideCarPlayNotif() {
    notifEl.classList.add("hidden");
  }

  function showAlertModal(alert) {
    alertModalTitleEl.textContent = `${alert.icon} ${alert.label} — over ${alert.distance_m} m`;
    alertModalEl.classList.remove("hidden");
    clearTimeout(modalDismissTimer);
    modalDismissTimer = setTimeout(hideAlertModal, 7000);
  }

  function hideAlertModal() {
    alertModalEl.classList.add("hidden");
  }

  function speakAlert(alert) {
    if (!speechToggle?.checked) return;
    const now = Date.now();
    if (now - lastSpokenAt < 18000) return;
    lastSpokenAt = now;

    if (!("speechSynthesis" in window)) return;
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(
      `Let op. ${alert.label}. Over ${alert.distance_m} meter.`
    );
    utterance.lang = "nl-NL";
    utterance.rate = 1;
    window.speechSynthesis.speak(utterance);
  }

  function resetAlarmState() {
    lastAlertId = null;
    passedThresholds = new Set();
  }

  function handleAlarms(alert) {
    if (!alert) {
      resetAlarmState();
      hideCarPlayNotif();
      hideAlertModal();
      return;
    }

    let shouldAlarm = false;
    if (lastAlertId !== alert.id) {
      resetAlarmState();
      lastAlertId = alert.id;
      shouldAlarm = true;
    } else {
      for (const threshold of ALARM_THRESHOLDS) {
        if (alert.distance_m <= threshold && !passedThresholds.has(threshold)) {
          passedThresholds.add(threshold);
          shouldAlarm = true;
          break;
        }
      }
    }

    if (!shouldAlarm) return;

    if (carPlayApp === "flitsmeister") {
      showCarPlayNotif(alert);
      speakAlert(alert);
      setStatus(`🔔 Banner + spraak: ${alert.label} over ${alert.distance_m} m`);
    } else {
      showAlertModal(alert);
      speakAlert(alert);
      setStatus(`⚠️ CPAlert: ${alert.label} over ${alert.distance_m} m`);
    }
  }

  function renderWidget(data) {
    const alert = data?.alert;
    if (alert) {
      widgetEl.className = "flits-widget alert";
      widgetEl.innerHTML = `
        <div class="flits-widget-header">
          <span class="flits-widget-icon">${alert.icon}</span>
          <span class="flits-widget-brand">FlitsMaatje</span>
        </div>
        <div class="flits-widget-label">${escapeHtml(alert.label)}</div>
        <div class="flits-widget-distance">${alert.distance_m} m</div>
      `;
      renderDrivingTaskList(alert);
      handleAlarms(alert);
      if (alertMarker) {
        alertMarker.setLatLng([alert.lat, alert.lng]);
        alertMarker.addTo(map);
      }
    } else {
      widgetEl.className = "flits-widget clear";
      widgetEl.innerHTML = `
        <div class="flits-widget-header">
          <span class="flits-widget-icon shield">🛡️</span>
          <span class="flits-widget-brand">FlitsMaatje</span>
        </div>
        <div class="flits-widget-label">Geen meldingen</div>
        <div class="flits-widget-sub">Geen meldingen in de buurt</div>
      `;
      renderDrivingTaskList(null);
      resetAlarmState();
      if (carPlayApp === "flitsmeister") {
        setStatus("✓ Geen meldingen — Flitsmeister navigeert");
      } else {
        setStatus("✓ Geen meldingen in de buurt");
      }
      if (alertMarker) alertMarker.remove();
    }
  }

  async function fetchAlert() {
    try {
      const res = await fetch(`${API}?lat=${lat}&lng=${lng}&radius_km=15`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (data?.alert) data.alert.id = data.alert.id || "live";
      renderWidget(data);
      formatCoords();
      if (marker) marker.setLatLng([lat, lng]);
      if (map && carPlayApp === "flitsmeister") {
        map.panTo([lat, lng], { animate: true, duration: 0.4 });
      }
    } catch (err) {
      setStatus(`Fout bij ophalen: ${err.message}`);
    }
  }

  function startPolling() {
    stopPolling();
    fetchAlert();
    pollTimer = setInterval(fetchAlert, POLL_MS);
  }

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
  }

  function stopDriving() {
    if (driveTimer) clearInterval(driveTimer);
    driveTimer = null;
    document.getElementById("btn-drive")?.classList.remove("active");
    document.getElementById("btn-full-demo")?.classList.remove("active");
  }

  async function ensureDemoReport(route) {
    const { lat: fLat, lng: fLng } = route.demoFlitser;
    try {
      await fetch("/api/reports", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "flitser_vast", lat: fLat, lng: fLng }),
      });
    } catch {
      /* demo werkt ook zonder seed */
    }
  }

  function simulateDrive(routeKey, options = {}) {
    stopDriving();
    mode = "drive";
    const route = demoRoutes[routeKey];
    if (!route) return;

    if (options.flitsmeisterMode !== false) {
      setCarPlayApp("flitsmeister");
    }

    ensureDemoReport(route).then(() => {
      let idx = 0;
      [lat, lng] = route.points[0];
      resetAlarmState();
      lastSpokenAt = 0;
      document.getElementById("btn-drive")?.classList.add("active");
      if (options.fullDemo) {
        document.getElementById("btn-full-demo")?.classList.add("active");
      }
      setStatus(route.label);
      startPolling();

      driveTimer = setInterval(() => {
        idx += 1;
        if (idx >= route.points.length) {
          stopDriving();
          setStatus("Demo klaar — je zou banners + spraak gezien moeten hebben");
          return;
        }
        [lat, lng] = route.points[idx];
        fetchAlert();
      }, 2200);
    });
  }

  function demoAlert() {
    stopDriving();
    const demo = {
      id: "demo",
      icon: "📷",
      label: "Vaste flitser",
      distance_m: 200,
      lat: lat + 0.002,
      lng: lng + 0.002,
    };
    resetAlarmState();
    lastSpokenAt = 0;
    renderWidget({ alert: demo });
    setStatus("Demo: flitser op 200 m");
  }

  function demoClear() {
    stopDriving();
    resetAlarmState();
    hideCarPlayNotif();
    hideAlertModal();
    renderWidget({ alert: null });
    setStatus("Demo gereset");
  }

  function fullDemo() {
    setCarPlayApp("flitsmeister");
    setStatus("Stap 1/2: Flitsmeister navigeert — let op banner + spraak…");
    simulateDrive("amsterdam", { fullDemo: true, flitsmeisterMode: true });

    setTimeout(() => {
      if (mode !== "drive") return;
      setStatus("Stap 2/2: schakel over naar FlitsMaatje (CPAlert)…");
      setCarPlayApp("flitsmaatje");
    }, 14000);
  }

  function initMap() {
    map = L.map("map", { zoomControl: false, attributionControl: false }).setView([lat, lng], 14);
    L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
      maxZoom: 19,
    }).addTo(map);

    marker = L.circleMarker([lat, lng], {
      radius: 8,
      color: "#0a84ff",
      fillColor: "#0a84ff",
      fillOpacity: 1,
      weight: 2,
    }).addTo(map);

    alertMarker = L.circleMarker([0, 0], {
      radius: 10,
      color: "#ff453a",
      fillColor: "#ff453a",
      fillOpacity: 0.85,
      weight: 2,
    });

    map.on("click", (e) => {
      if (mode === "drive") return;
      lat = e.latlng.lat;
      lng = e.latlng.lng;
      mode = "manual";
      resetAlarmState();
      fetchAlert();
    });
  }

  document.getElementById("btn-full-demo")?.addEventListener("click", fullDemo);
  document.getElementById("btn-drive")?.addEventListener("click", () => simulateDrive("amsterdam"));
  document.getElementById("btn-refresh")?.addEventListener("click", () => {
    stopDriving();
    startPolling();
  });
  document.getElementById("btn-demo-alert")?.addEventListener("click", demoAlert);
  document.getElementById("btn-demo-clear")?.addEventListener("click", demoClear);
  document.getElementById("alert-modal-ok")?.addEventListener("click", hideAlertModal);

  document.querySelectorAll(".mode-btn").forEach((btn) => {
    btn.addEventListener("click", () => setCarPlayApp(btn.dataset.mode));
  });

  document.querySelectorAll(".app-tile[data-app]").forEach((tile) => {
    tile.addEventListener("click", () => setCarPlayApp(tile.dataset.app));
  });

  initMap();
  setCarPlayApp("flitsmeister");
  formatCoords();
  startPolling();
})();
