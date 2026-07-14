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
  const notifBodyEl = document.getElementById("notif-body");
  const alertModalEl = document.getElementById("carplay-alert-modal");
  const alertModalTitleEl = document.getElementById("alert-modal-title");
  const drivingTaskListEl = document.getElementById("driving-task-list");
  const panelNavEl = document.getElementById("panel-nav");
  const panelDrivingEl = document.getElementById("panel-driving-task");
  const speechToggle = document.getElementById("toggle-speech");
  const speedHudEl = document.getElementById("speed-hud");
  const speedHudValueEl = document.getElementById("speed-hud-value");
  const speedHudLimitEl = document.getElementById("speed-hud-limit");

  let lat = 52.3676;
  let lng = 4.9041;
  let pollTimer = null;
  let driveTimer = null;
  let speedDemoTimer = null;
  let alertDismissTimer = null;
  let modalDismissTimer = null;
  let mode = "manual";
  let carPlayApp = "flitsmeister";
  let lastAlertId = null;
  let passedThresholds = new Set();
  let lastSpokenAt = 0;
  let demoSpeedKmh = null;
  let demoSpeedLimit = 100;

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

  function showCarPlayBanner({ icon, title, subtitle, body = "", kind = "flitser" }) {
    notifIconEl.textContent = icon;
    notifTitleEl.textContent = title;
    notifSubEl.textContent = subtitle;
    if (body) {
      notifBodyEl.textContent = body;
      notifBodyEl.classList.remove("hidden");
    } else if (kind !== "speeding") {
      notifBodyEl.textContent = "";
      notifBodyEl.classList.add("hidden");
    }
    notifEl.classList.toggle("speeding", kind === "speeding");
    notifEl.classList.remove("hidden");
    clearTimeout(alertDismissTimer);
    alertDismissTimer = setTimeout(hideCarPlayNotif, kind === "speeding" ? 12000 : 7000);
  }

  function showCarPlayNotif(alert) {
    showCarPlayBanner({
      icon: alert.icon,
      title: alert.label,
      subtitle: `Over ${alert.distance_m} meter`,
      kind: "flitser",
    });
  }

  function showSpeedingBanner(speedKmh, limit, fine) {
    const title = fine.bedrag
      ? `Te hard — indicatief €${fine.bedrag}`
      : `Te hard — ${fine.excess} km/u`;
    const subtitle = `${speedKmh} km/u · limiet ${limit} · ${fine.excess} km/u te hard`;
    notifBodyEl.innerHTML = fine.bedrag
      ? `<span class="fine-amount">${fine.excess} km/u boven de limiet</span><span class="fine-price">Indicatief €${fine.bedrag} incl. adm.kosten</span>`
      : `<span class="fine-price">${fine.excess} km/u te hard</span>`;
    notifBodyEl.classList.remove("hidden");
    showCarPlayBanner({
      icon: "🚨",
      title,
      subtitle,
      kind: "speeding",
    });
  }

  function updateSpeedHud(speedKmh, limit) {
    if (speedKmh == null) {
      speedHudEl.classList.add("hidden");
      return;
    }
    speedHudEl.classList.remove("hidden");
    speedHudValueEl.textContent = String(speedKmh);
    speedHudLimitEl.textContent = `limiet ${limit}`;
  }

  function hideCarPlayNotif() {
    notifEl.classList.add("hidden");
    notifEl.classList.remove("speeding");
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
    if (mode === "speed-demo") return;
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
    stopSpeedDemo();
    document.getElementById("btn-drive")?.classList.remove("active");
    document.getElementById("btn-full-demo")?.classList.remove("active");
    document.getElementById("btn-demo-speed")?.classList.remove("active");
  }

  function stopSpeedDemo() {
    if (speedDemoTimer) clearInterval(speedDemoTimer);
    speedDemoTimer = null;
    demoSpeedKmh = null;
    updateSpeedHud(null);
  }

  function fineFor(speedKmh, limit) {
    const excess = speedKmh - limit;
    if (excess < 4) return null;
    const bedrag = Math.min(990, 120 + excess * 9);
    return { excess, bedrag };
  }

  function demoSpeeding() {
    stopDriving();
    stopPolling();
    mode = "speed-demo";
    setCarPlayApp("flitsmeister");
    const limit = 100;
    let speed = 96;
    demoSpeedKmh = speed;
    document.getElementById("btn-demo-speed")?.classList.add("active");
    setStatus("Demo: te hard rijden — stille banner, geen spraak");

    updateSpeedHud(speed, limit);
    const firstFine = fineFor(speed, limit);
    if (firstFine) showSpeedingBanner(speed, limit, firstFine);

    speedDemoTimer = setInterval(() => {
      speed += 4;
      demoSpeedKmh = speed;
      updateSpeedHud(speed, limit);
      const fine = fineFor(speed, limit);
      if (fine) {
        showSpeedingBanner(speed, limit, fine);
        setStatus(`🚨 ${speed} km/u · indicatief €${fine.bedrag} · ${fine.excess} km/u te hard`);
      }
      if (speed >= 132) {
        stopSpeedDemo();
        mode = "manual";
        document.getElementById("btn-demo-speed")?.classList.remove("active");
        setStatus("Demo te hard klaar — banner bleef live bijwerken zonder spraak");
      }
    }, 1400);
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
    stopPolling();
    mode = "manual";
    resetAlarmState();
    hideCarPlayNotif();
    hideAlertModal();
    renderWidget({ alert: null });
    startPolling();
    setStatus("Demo gereset");
  }

  function fullDemo() {
    setCarPlayApp("flitsmeister");
    setStatus("Stap 1/3: te hard rijden — stille boete-banner…");
    demoSpeeding();

    setTimeout(() => {
      stopSpeedDemo();
      mode = "drive";
      setStatus("Stap 2/3: Flitsmeister navigeert — flitser banner + spraak…");
      simulateDrive("amsterdam", { fullDemo: true, flitsmeisterMode: true });
    }, 9000);

    setTimeout(() => {
      if (mode !== "drive") return;
      setStatus("Stap 3/3: FlitsMaatje open op CarPlay (CPAlert)…");
      setCarPlayApp("flitsmaatje");
    }, 24000);
  }

  const BOOT_STAGES = [
    { id: "process-start", label: "Process gestart (BootLogger)", delay: 100 },
    { id: "didFinishLaunching", label: "AppDelegate didFinishLaunching", delay: 250 },
    { id: "logger-installed", label: "Logger actief + sync upload", delay: 500 },
    { id: "bootstrap-start", label: "UI zichtbaar — bootstrap start", delay: 750 },
    { id: "location-created", label: "Locatieservice aangemaakt", delay: 950 },
    { id: "rootview-ready", label: "RootView klaar — Status-tab zichtbaar", delay: 1150 },
    { id: "location-permission-start", label: "Locatie: permissie aanvragen", delay: 1450 },
    { id: "location-activate", label: "Locatie: actief na scenePhase .active", delay: 1750 },
    { id: "location-tracking-active", label: "GPS-tracking gestart", delay: 2050 },
  ];

  async function simulateBoot() {
    const panel = document.getElementById("boot-sim-panel");
    const list = document.getElementById("boot-sim-stages");
    const resultEl = document.getElementById("boot-sim-result");
    if (!panel || !list || !resultEl) return;

    panel.classList.remove("hidden");
    list.innerHTML = BOOT_STAGES.map(
      (s) => `<li class="pending" data-id="${s.id}">⏳ ${s.label}</li>`
    ).join("");
    resultEl.textContent = "Simuleert iOS-opstart (build 86+)…";
    setStatus("Boot-simulatie…");

    for (const stage of BOOT_STAGES) {
      await new Promise((r) => setTimeout(r, stage.delay));
      const li = list.querySelector(`[data-id="${stage.id}"]`);
      if (li) {
        li.className = "done";
        li.textContent = `✓ ${stage.label}`;
      }
    }

    resultEl.textContent = "Opstart OK — app zou nu het Status-scherm tonen.";
    setStatus("✓ Boot-simulatie geslaagd");
  }

  async function runSelfTest() {
    const panel = document.getElementById("selftest-panel");
    const output = document.getElementById("selftest-output");
    if (!panel || !output) return;

    panel.classList.remove("hidden");
    output.textContent = "Selftest draait…";
    setStatus("Selftest…");

    try {
      const res = await fetch("/api/carplay-selftest");
      const data = await res.json();
      output.textContent = JSON.stringify(data, null, 2);
      if (data.ok) {
        setStatus(`✓ Selftest geslaagd (${data.checks?.length || 0} checks)`);
      } else {
        const failed = (data.checks || []).filter((c) => !c.ok).map((c) => c.name).join(", ");
        setStatus(`✗ Selftest gefaald: ${failed}`);
      }
    } catch (err) {
      output.textContent = String(err);
      setStatus(`Selftest fout: ${err.message}`);
    }
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
  document.getElementById("btn-selftest")?.addEventListener("click", runSelfTest);
  document.getElementById("btn-boot-sim")?.addEventListener("click", simulateBoot);
  document.getElementById("btn-demo-speed")?.addEventListener("click", demoSpeeding);
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
