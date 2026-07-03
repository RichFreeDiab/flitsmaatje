(() => {
  const API = "/api/nearby-alert";
  const POLL_MS = 8000;

  const widgetEl = document.getElementById("flits-widget");
  const statusEl = document.getElementById("status-pill");
  const coordsEl = document.getElementById("coords");
  const navHintEl = document.getElementById("nav-hint");

  let lat = 52.3676;
  let lng = 4.9041;
  let pollTimer = null;
  let driveTimer = null;
  let mode = "manual";

  const demoRoutes = {
    amsterdam: {
      label: "Rijden richting demo-flitser (Amsterdam)",
      demoFlitser: { lat: 52.3688, lng: 4.9060 },
      points: [
        [52.3645, 4.8980],
        [52.3658, 4.9005],
        [52.3670, 4.9025],
        [52.3682, 4.9048],
        [52.3695, 4.9070],
        [52.3710, 4.9095],
        [52.3725, 4.9120],
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
      navHintEl.innerHTML = `<strong>Navigatie actief</strong>Volg de route — widget toont waarschuwing`;
      setStatus(`⚠️ ${alert.label} over ${alert.distance_m} m`);
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
      navHintEl.innerHTML = `<strong>Kaarten</strong>Geen flitsers binnen bereik`;
      setStatus("✓ Geen meldingen in de buurt");
      if (alertMarker) alertMarker.remove();
    }
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function fetchAlert() {
    try {
      const res = await fetch(`${API}?lat=${lat}&lng=${lng}&radius_km=15`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      renderWidget(data);
      formatCoords();
      if (marker) marker.setLatLng([lat, lng]);
      if (map) map.panTo([lat, lng], { animate: true, duration: 0.4 });
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
  }

  function useGps() {
    stopDriving();
    mode = "gps";
    setStatus("Locatie opvragen…");
    if (!navigator.geolocation) {
      setStatus("Geolocation niet beschikbaar in deze browser");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        lat = pos.coords.latitude;
        lng = pos.coords.longitude;
        startPolling();
      },
      (err) => setStatus(`GPS geweigerd: ${err.message}`),
      { enableHighAccuracy: true, timeout: 15000 }
    );
  }

  async function ensureDemoReport(route) {
    const { lat, lng } = route.demoFlitser;
    try {
      await fetch("/api/reports", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ type: "flitser_vast", lat, lng }),
      });
    } catch {
      /* demo-rit werkt ook zonder seed */
    }
  }

  function simulateDrive(routeKey) {
    stopDriving();
    mode = "drive";
    const route = demoRoutes[routeKey];
    if (!route) return;

    ensureDemoReport(route).then(() => {
    let idx = 0;
    [lat, lng] = route.points[0];
    document.getElementById("btn-drive").classList.add("active");
    setStatus(route.label);
    startPolling();

    driveTimer = setInterval(() => {
      idx += 1;
      if (idx >= route.points.length) {
        stopDriving();
        setStatus("Rit klaar — widget zou flitser moeten tonen als er meldingen zijn");
        return;
      }
      [lat, lng] = route.points[idx];
      fetchAlert();
    }, 2500);
    });
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
      fetchAlert();
    });
  }

  document.getElementById("btn-gps")?.addEventListener("click", useGps);
  document.getElementById("btn-refresh")?.addEventListener("click", () => {
    stopDriving();
    startPolling();
  });
  document.getElementById("btn-drive")?.addEventListener("click", () => simulateDrive("amsterdam"));
  document.getElementById("btn-demo-alert")?.addEventListener("click", () => {
    stopDriving();
    renderWidget({
      alert: {
        icon: "📷",
        label: "Vaste flitser",
        distance_m: 420,
        lat: lat + 0.002,
        lng: lng + 0.002,
      },
    });
    setStatus("Demo: vaste flitser (alleen UI, geen API)");
  });
  document.getElementById("btn-demo-clear")?.addEventListener("click", () => {
    stopDriving();
    renderWidget({ alert: null });
    setStatus("Demo: geen meldingen");
  });

  initMap();
  formatCoords();
  startPolling();
})();
