(() => {
  const API_ALERT = "/api/nearby-alert";
  const API_SPEED = "/api/speed-check";
  const POLL_MS = 8000;
  const SPEED_POLL_MS = 5000;
  const ALARM_THRESHOLDS = [600, 400, 200, 100];
  const SPEECH_PREF_KEY = "carplay_speech_enabled";

  const widgetEl = document.getElementById("flits-widget");
  const statusEl = document.getElementById("status-pill");
  const coordsEl = document.getElementById("coords");
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
  const settingsMenuEl = document.getElementById("settings-menu");
  const speedHudEl = document.getElementById("speed-hud");
  const speedHudValueEl = document.getElementById("speed-hud-value");
  const speedHudLimitSignEl = document.getElementById("speed-hud-limit-sign");
  const fineCardEl = document.getElementById("fine-card");
  const fineCardTitleEl = document.getElementById("fine-card-title");
  const fineCardTextEl = document.getElementById("fine-card-text");
  const fineCardPriceEl = document.getElementById("fine-card-price");
  const navCardIconEl = document.getElementById("nav-card-icon");
  const navCardDistanceEl = document.getElementById("nav-card-distance");
  const navCardInstructionEl = document.getElementById("nav-card-instruction");
  const summaryArrivalEl = document.getElementById("summary-arrival");
  const summaryDurationEl = document.getElementById("summary-duration");
  const summaryDistanceEl = document.getElementById("summary-distance");

  let lat = 52.3676;
  let lng = 4.9041;
  let currentHeading = null;
  let currentSpeedKmh = 47;
  let currentLimitKmh = 50;
  let pollTimer = null;
  let speedPollTimer = null;
  let driveTimer = null;
  let speedDemoTimer = null;
  let alertDismissTimer = null;
  let modalDismissTimer = null;
  let mode = "manual";
  let carPlayApp = "flitsmeister";
  let lastAlertId = null;
  let passedThresholds = new Set();
  let lastSpokenAt = 0;
  let lastSpeedingBannerAt = 0;
  let demoSpeedKmh = null;
  let routeStepIndex = 0;

  const maneuverIconMap = {
    right: "R",
    left: "L",
    straight: "S",
    merge: "M",
    arrive: "OK",
  };

  const demoRoutes = {
    amsterdam: {
      label: "Demo-rit: Flitsmeister navigeert, FlitsMaatje waarschuwt",
      demoFlitser: { lat: 52.3688, lng: 4.9060 },
      totalMinutes: 16,
      totalKm: 12,
      maneuvers: [
        { at: 0, icon: "R", distance: "250 m", text: "Ga rechtsaf naar Meesterstraat" },
        { at: 4, icon: "S", distance: "900 m", text: "Rijd rechtdoor richting Centrum" },
        { at: 8, icon: "L", distance: "350 m", text: "Houd links aan richting Ring A10" },
        { at: 11, icon: "OK", distance: "80 m", text: "Bestemming bijna bereikt" },
      ],
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

  function speechEnabled() {
    return Boolean(speechToggle?.checked);
  }

  function applySpeechPreference() {
    const stored = localStorage.getItem(SPEECH_PREF_KEY);
    if (speechToggle) {
      speechToggle.checked = stored !== "0";
    }
  }

  function saveSpeechPreference() {
    localStorage.setItem(SPEECH_PREF_KEY, speechEnabled() ? "1" : "0");
  }

  function toggleSettingsMenu(forceOpen) {
    if (!settingsMenuEl) return;
    const shouldOpen = typeof forceOpen === "boolean" ? forceOpen : settingsMenuEl.classList.contains("hidden");
    settingsMenuEl.classList.toggle("hidden", !shouldOpen);
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
      setStatus("FlitsMaatje open - Driving Task met lijst en alerts");
    } else {
      hideAlertModal();
      setStatus("Flitsmeister actief - routekaart en flitserwaarschuwingen zichtbaar");
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
        <span>Over ${alert.distance_m} m - Dichtstbijzijnde melding</span>
      </div>
    `;
  }

  function showCarPlayBanner({ icon, title, subtitle, body = "", kind = "flitser" }) {
    notifIconEl.textContent = icon;
    notifTitleEl.textContent = title;
    notifSubEl.textContent = subtitle;
    if (body) {
      notifBodyEl.innerHTML = body;
      notifBodyEl.classList.remove("hidden");
    } else {
      notifBodyEl.innerHTML = "";
      notifBodyEl.classList.add("hidden");
    }
    notifEl.classList.toggle("speeding", kind === "speeding");
    notifEl.classList.remove("hidden");
    clearTimeout(alertDismissTimer);
    alertDismissTimer = setTimeout(hideCarPlayNotif, kind === "speeding" ? 12000 : 7000);
  }

  function hideCarPlayNotif() {
    notifEl.classList.add("hidden");
    notifEl.classList.remove("speeding");
  }

  function showAlertModal(alert) {
    alertModalTitleEl.textContent = `${alert.icon} ${alert.label} - over ${alert.distance_m} m`;
    alertModalEl.classList.remove("hidden");
    clearTimeout(modalDismissTimer);
    modalDismissTimer = setTimeout(hideAlertModal, 7000);
  }

  function hideAlertModal() {
    alertModalEl.classList.add("hidden");
  }

  function speak(text) {
    if (!speechEnabled()) return;
    if (!("speechSynthesis" in window)) return;
    const now = Date.now();
    if (now - lastSpokenAt < 4000) return;
    lastSpokenAt = now;
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = "nl-NL";
    utterance.rate = 1;
    window.speechSynthesis.speak(utterance);
  }

  function speakAlert(alert) {
    speak(`Let op. ${alert.label}. Over ${alert.distance_m} meter.`);
  }

  function updateNavCard(icon, distance, instruction) {
    navCardIconEl.textContent = icon;
    navCardDistanceEl.textContent = distance;
    navCardInstructionEl.textContent = instruction;
  }

  function updateRouteSummary(minutes, kmLeft) {
    const arrival = new Date(Date.now() + minutes * 60000);
    summaryArrivalEl.textContent = arrival.toLocaleTimeString("nl-NL", { hour: "2-digit", minute: "2-digit" });
    summaryDurationEl.textContent = String(Math.max(1, Math.round(minutes)));
    summaryDistanceEl.textContent = String(Math.max(1, Math.round(kmLeft)));
  }

  function updateManeuver(route, pointIndex, speakStep = false) {
    const candidates = route.maneuvers.filter((step) => step.at <= pointIndex);
    const step = candidates[candidates.length - 1] || route.maneuvers[0];
    if (!step) return;
    const currentIdx = route.maneuvers.indexOf(step);
    const remainingMinutes = route.totalMinutes * (1 - pointIndex / Math.max(1, route.points.length - 1));
    const remainingKm = route.totalKm * (1 - pointIndex / Math.max(1, route.points.length - 1));

    updateNavCard(step.icon, step.distance, step.text);
    updateRouteSummary(remainingMinutes, remainingKm);

    if (speakStep && currentIdx !== routeStepIndex) {
      routeStepIndex = currentIdx;
      speak(step.text);
    }
  }

  function updateSpeedHud(speedKmh, limit) {
    if (speedKmh == null || limit == null) {
      speedHudEl.classList.add("hidden");
      return;
    }
    speedHudEl.classList.remove("hidden");
    speedHudValueEl.textContent = String(Math.round(speedKmh));
    speedHudLimitSignEl.textContent = String(Math.round(limit));
  }

  function hideFineCard() {
    fineCardEl.classList.add("hidden");
  }

  function showFineCard(alert, speedKmh, limit, fine) {
    const alertText = alert ? `${alert.label} over ${alert.distance_m} m` : "Snelheidscontrole actief";
    fineCardTitleEl.textContent = alertText;
    fineCardTextEl.textContent = `Boete bij ${Math.round(speedKmh)} km/u:`;
    fineCardPriceEl.textContent = fine.om_zaak ? "OM" : `EUR ${fine.bedrag}`;
    fineCardEl.classList.remove("hidden");
  }

  function showSpeedingBanner(speedKmh, limit, fine) {
    const title = fine.om_zaak
      ? `Te hard - ${fine.excess_kmh} km/u`
      : `Te hard - indicatief EUR ${fine.bedrag}`;
    const subtitle = `${Math.round(speedKmh)} km/u - limiet ${limit} - ${fine.excess_kmh} km/u te hard`;
    const body = fine.om_zaak
      ? `<span class="fine-price">Controleer OM-tarief</span>`
      : `<span class="fine-amount">${fine.excess_kmh} km/u boven de limiet</span><span class="fine-price">Indicatief EUR ${fine.bedrag} incl. adm.kosten</span>`;
    showCarPlayBanner({
      icon: "!",
      title,
      subtitle,
      body,
      kind: "speeding",
    });
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
      showCarPlayBanner({
        icon: alert.icon,
        title: alert.label,
        subtitle: `Over ${alert.distance_m} meter`,
      });
      speakAlert(alert);
      setStatus(`Banner plus spraak: ${alert.label} over ${alert.distance_m} m`);
    } else {
      showAlertModal(alert);
      speakAlert(alert);
      setStatus(`CPAlert: ${alert.label} over ${alert.distance_m} m`);
    }
  }

  function renderWidget(data) {
    const alert = data?.alert;
    if (alert) {
      widgetEl.className = "flits-widget alert";
      widgetEl.innerHTML = `
        <div class="flits-widget-header">
          <span class="flits-widget-icon">${escapeHtml(alert.icon)}</span>
          <span class="flits-widget-brand">FlitsMaatje</span>
        </div>
        <div class="flits-widget-label">${escapeHtml(alert.label)}</div>
        <div class="flits-widget-distance">${alert.distance_m} m</div>
        <div class="flits-widget-sub">Achtergrondwaarschuwing actief</div>
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
          <span class="flits-widget-icon shield">FM</span>
          <span class="flits-widget-brand">FlitsMaatje</span>
        </div>
        <div class="flits-widget-label">Geen meldingen</div>
        <div class="flits-widget-sub">Geen meldingen in de buurt</div>
      `;
      renderDrivingTaskList(null);
      resetAlarmState();
      if (alertMarker) alertMarker.remove();
    }
  }

  async function fetchAlert() {
    if (mode === "speed-demo") return null;
    try {
      const headingPart = currentHeading != null ? `&heading=${currentHeading.toFixed(1)}` : "";
      const res = await fetch(`${API_ALERT}?lat=${lat}&lng=${lng}&radius_km=15${headingPart}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (data?.alert) data.alert.id = data.alert.id || "live";
      renderWidget(data);
      formatCoords();
      if (marker) marker.setLatLng([lat, lng]);
      if (map && carPlayApp === "flitsmeister") {
        map.panTo([lat, lng], { animate: true, duration: 0.4 });
      }
      return data?.alert || null;
    } catch (err) {
      setStatus(`Fout bij ophalen: ${err.message}`);
      return null;
    }
  }

  async function fetchSpeedState(alert = null) {
    if (currentSpeedKmh == null) return;
    try {
      const res = await fetch(`${API_SPEED}?lat=${lat}&lng=${lng}&speed_kmh=${Math.round(currentSpeedKmh)}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      const limit = data?.limit?.maxspeed;
      const fine = data?.fine;
      currentLimitKmh = limit ?? currentLimitKmh;
      updateSpeedHud(currentSpeedKmh, currentLimitKmh);

      if (!fine || fine.bedrag === 0) {
        hideFineCard();
        return;
      }

      showFineCard(alert, currentSpeedKmh, currentLimitKmh, fine);
      const now = Date.now();
      if (now - lastSpeedingBannerAt > 18000) {
        showSpeedingBanner(currentSpeedKmh, currentLimitKmh, fine);
        lastSpeedingBannerAt = now;
      }
    } catch (err) {
      setStatus(`Snelheidscheck mislukt: ${err.message}`);
    }
  }

  async function pollLiveState() {
    const alert = await fetchAlert();
    await fetchSpeedState(alert);
  }

  function startPolling() {
    stopPolling();
    pollLiveState();
    pollTimer = setInterval(pollLiveState, POLL_MS);
    speedPollTimer = setInterval(() => fetchSpeedState(), SPEED_POLL_MS);
  }

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    if (speedPollTimer) clearInterval(speedPollTimer);
    pollTimer = null;
    speedPollTimer = null;
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
  }

  function demoFine(speedKmh, limit) {
    const excess = speedKmh - limit;
    if (excess < 4) return null;
    return {
      excess_kmh: excess,
      bedrag: Math.min(990, 120 + excess * 9),
      om_zaak: false,
    };
  }

  function applySpeedState(speedKmh, limit, alert = null, fine = null) {
    currentSpeedKmh = speedKmh;
    currentLimitKmh = limit;
    updateSpeedHud(speedKmh, limit);
    if (fine) {
      showFineCard(alert, speedKmh, limit, fine);
      showSpeedingBanner(speedKmh, limit, fine);
    } else {
      hideFineCard();
    }
  }

  function demoSpeeding() {
    stopDriving();
    stopPolling();
    mode = "speed-demo";
    setCarPlayApp("flitsmeister");
    const limit = 50;
    let speed = 47;
    demoSpeedKmh = speed;
    document.getElementById("btn-demo-speed")?.classList.add("active");
    setStatus("Demo: te hard rijden - stille boeteweergave actief");

    applySpeedState(speed, limit);

    speedDemoTimer = setInterval(() => {
      speed += 5;
      demoSpeedKmh = speed;
      const fine = demoFine(speed, limit);
      applySpeedState(speed, limit, { label: "Flitser", distance_m: 350 }, fine);
      if (fine) {
        setStatus(`${speed} km/u - indicatief EUR ${fine.bedrag} - ${fine.excess_kmh} km/u te hard`);
      }
      if (speed >= 67) {
        stopSpeedDemo();
        mode = "manual";
        document.getElementById("btn-demo-speed")?.classList.remove("active");
        setStatus("Demo te hard klaar - boetekaart bleef zichtbaar");
      }
    }, 1500);
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
      routeStepIndex = 0;
      [lat, lng] = route.points[0];
      currentSpeedKmh = 47;
      currentLimitKmh = 50;
      resetAlarmState();
      lastSpokenAt = 0;
      document.getElementById("btn-drive")?.classList.add("active");
      if (options.fullDemo) {
        document.getElementById("btn-full-demo")?.classList.add("active");
      }
      updateManeuver(route, idx, false);
      setStatus(route.label);
      startPolling();

      driveTimer = setInterval(async () => {
        idx += 1;
        if (idx >= route.points.length) {
          stopDriving();
          setStatus("Demo klaar - routekaart, spraak en boeteblok zijn bijgewerkt");
          return;
        }
        [lat, lng] = route.points[idx];
        currentHeading = 45 + idx * 8;
        currentSpeedKmh = 45 + (idx % 4) * 4;
        updateManeuver(route, idx, true);
        const alert = await fetchAlert();
        await fetchSpeedState(alert);
      }, 2200);
    });
  }

  function demoAlert() {
    stopDriving();
    const demo = {
      id: "demo",
      icon: "!",
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
    hideFineCard();
    renderWidget({ alert: null });
    applySpeedState(47, 50);
    startPolling();
    setStatus("Demo gereset");
  }

  function fullDemo() {
    setCarPlayApp("flitsmeister");
    setStatus("Stap 1/3: te hard rijden - boetekaart...");
    demoSpeeding();

    setTimeout(() => {
      stopSpeedDemo();
      mode = "drive";
      setStatus("Stap 2/3: Flitsmeister navigeert - routekaart plus spraak...");
      simulateDrive("amsterdam", { fullDemo: true, flitsmeisterMode: true });
    }, 9000);

    setTimeout(() => {
      if (mode !== "drive") return;
      setStatus("Stap 3/3: FlitsMaatje open op CarPlay...");
      setCarPlayApp("flitsmaatje");
    }, 24000);
  }

  const BOOT_STAGES = [
    { id: "process-start", label: "Process gestart (BootLogger)", delay: 100 },
    { id: "swiftui-app-init", label: "SwiftUI App init", delay: 200 },
    { id: "didFinishLaunching", label: "AppDelegate didFinishLaunching", delay: 350 },
    { id: "logger-installed", label: "Logger actief", delay: 500 },
    { id: "phone-scene-willConnect", label: "Phone-scene verbonden (iOS 26)", delay: 650 },
    { id: "rootview-onAppear", label: "RootView zichtbaar", delay: 800 },
    { id: "bootstrap-start", label: "Bootstrap start", delay: 950 },
    { id: "location-created", label: "Locatieservice aangemaakt", delay: 1150 },
    { id: "rootview-ready", label: "App klaar", delay: 1300 },
    { id: "location-permission-start", label: "Locatie: permissie", delay: 1600 },
    { id: "location-activate", label: "Locatie actief", delay: 1900 },
    { id: "location-tracking-active", label: "GPS-tracking", delay: 2200 },
  ];

  async function simulateBoot() {
    const panel = document.getElementById("boot-sim-panel");
    const list = document.getElementById("boot-sim-stages");
    const resultEl = document.getElementById("boot-sim-result");
    if (!panel || !list || !resultEl) return;

    panel.classList.remove("hidden");
    list.innerHTML = BOOT_STAGES.map(
      (s) => `<li class="pending" data-id="${s.id}">... ${s.label}</li>`
    ).join("");
    resultEl.textContent = "Simuleert iOS-opstart (build 86+)...";
    setStatus("Boot-simulatie...");

    for (const stage of BOOT_STAGES) {
      await new Promise((r) => setTimeout(r, stage.delay));
      const li = list.querySelector(`[data-id="${stage.id}"]`);
      if (li) {
        li.className = "done";
        li.textContent = `OK ${stage.label}`;
      }
    }

    resultEl.textContent = "Opstart OK - app zou nu het Status-scherm tonen.";
    setStatus("Boot-simulatie geslaagd");
  }

  async function runSelfTest() {
    const panel = document.getElementById("selftest-panel");
    const output = document.getElementById("selftest-output");
    if (!panel || !output) return;

    panel.classList.remove("hidden");
    output.textContent = "Selftest draait...";
    setStatus("Selftest...");

    try {
      const res = await fetch("/api/carplay-selftest");
      const data = await res.json();
      output.textContent = JSON.stringify(data, null, 2);
      if (data.ok) {
        setStatus(`Selftest geslaagd (${data.checks?.length || 0} checks)`);
      } else {
        const failed = (data.checks || []).filter((c) => !c.ok).map((c) => c.name).join(", ");
        setStatus(`Selftest gefaald: ${failed}`);
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
      color: "#ff9f0a",
      fillColor: "#ff9f0a",
      fillOpacity: 0.85,
      weight: 2,
    });

    map.on("click", async (e) => {
      if (mode === "drive") return;
      lat = e.latlng.lat;
      lng = e.latlng.lng;
      mode = "manual";
      resetAlarmState();
      currentSpeedKmh = 47;
      await pollLiveState();
    });
  }

  document.getElementById("btn-full-demo")?.addEventListener("click", fullDemo);
  document.getElementById("btn-selftest")?.addEventListener("click", runSelfTest);
  document.getElementById("btn-boot-sim")?.addEventListener("click", simulateBoot);
  document.getElementById("btn-demo-speed")?.addEventListener("click", demoSpeeding);
  document.getElementById("btn-drive")?.addEventListener("click", () => simulateDrive("amsterdam"));
  document.getElementById("btn-demo-alert")?.addEventListener("click", demoAlert);
  document.getElementById("btn-demo-clear")?.addEventListener("click", demoClear);
  document.getElementById("alert-modal-ok")?.addEventListener("click", hideAlertModal);
  document.getElementById("btn-menu")?.addEventListener("click", () => toggleSettingsMenu());
  document.getElementById("settings-close")?.addEventListener("click", () => toggleSettingsMenu(false));
  speechToggle?.addEventListener("change", saveSpeechPreference);

  document.querySelectorAll(".mode-btn").forEach((btn) => {
    btn.addEventListener("click", () => setCarPlayApp(btn.dataset.mode));
  });

  document.querySelectorAll(".app-tile[data-app]").forEach((tile) => {
    tile.addEventListener("click", () => setCarPlayApp(tile.dataset.app));
  });

  applySpeechPreference();
  initMap();
  updateNavCard("R", "250 m", "Ga rechtsaf naar Meesterstraat");
  updateRouteSummary(16, 12);
  applySpeedState(47, 50);
  setCarPlayApp("flitsmeister");
  formatCoords();
  startPolling();
})();
