(() => {
  const css = document.createElement("style");
  css.textContent = `
    #nav-tools{position:absolute;top:16px;right:12px;z-index:1003;background:#1e2327;padding:8px;border-radius:12px;display:flex;gap:6px}
    #nav-tools input{width:230px;padding:10px;border:0;border-radius:8px}
    #nav-tools button{padding:10px;border:0;border-radius:8px;background:#e8482c;color:white;font-weight:700}
    #route-info{position:absolute;top:76px;right:12px;z-index:1002;background:#1e2327;color:white;padding:10px;border-radius:10px;max-width:320px}
    #route-info .instruction{font-size:18px;font-weight:700;margin-top:6px}
    #route-info .muted{opacity:.8;font-size:13px}
  `;
  document.head.appendChild(css);

  document.body.insertAdjacentHTML("beforeend",
    '<div id="nav-tools"><input id="destination" placeholder="Adres of plaats" autocomplete="street-address"><button id="route-btn">Route</button></div><div id="route-info" hidden></div>'
  );

  const input = document.getElementById("destination");
  const button = document.getElementById("route-btn");
  const info = document.getElementById("route-info");
  let routeLayer = null;
  let steps = [];
  let nextStep = 0;

  const icons = { depart: "🚗", arrive: "🏁", left: "↰", right: "↱", straight: "↑", uturn: "↩" };

  function instruction(step) {
    const m = step.maneuver || {};
    const type = m.type;
    const mod = m.modifier || "";
    let icon = icons.straight;
    if (type === "depart") icon = icons.depart;
    else if (type === "arrive") icon = icons.arrive;
    else if (type === "uturn") icon = icons.uturn;
    else if (mod.includes("left")) icon = icons.left;
    else if (mod.includes("right")) icon = icons.right;
    const road = step.name ? " op " + step.name : "";
    if (type === "arrive") return icon + " Bestemming bereikt";
    if (type === "depart") return icon + " Vertrek" + road;
    return icon + " " + (mod ? mod.replaceAll("-", " ") : type) + road;
  }

  function renderStep() {
    const step = steps[nextStep];
    if (!step) {
      info.innerHTML = '<div class="instruction">🏁 Route voltooid</div>';
      return;
    }
    const km = ((step.distance || 0) / 1000).toFixed(1);
    info.innerHTML = '<div class="muted">Volgende instructie · ' + km + ' km</div><div class="instruction">' + instruction(step) + '</div>';
  }

  async function route() {
    const query = input.value.trim();
    if (!query) return;
    button.disabled = true;
    button.textContent = "Zoeken...";
    info.hidden = true;
    try {
      const places = await fetch(
        "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=nl&q=" +
        encodeURIComponent(query),
        {headers: {"Accept-Language": "nl"}}
      ).then(r => {
        if (!r.ok) throw Error("Adres zoeken mislukt");
        return r.json();
      });
      if (!places.length) throw Error("Adres niet gevonden");

      const pos = await new Promise((resolve, reject) =>
        navigator.geolocation.getCurrentPosition(resolve, reject, {enableHighAccuracy:true, timeout:10000})
      );
      const start = pos.coords.longitude + "," + pos.coords.latitude;
      const end = places[0].lon + "," + places[0].lat;
      const data = await fetch(
        "https://router.project-osrm.org/route/v1/driving/" + start + ";" + end +
        "?overview=full&geometries=geojson&steps=true&language=nl"
      ).then(r => {
        if (!r.ok) throw Error("Route berekenen mislukt");
        return r.json();
      });
      const r = data.routes && data.routes[0];
      if (!r) throw Error("Route niet gevonden");

      if (routeLayer && window.map) window.map.removeLayer(routeLayer);
      if (window.map && r.geometry) {
        routeLayer = L.geoJSON(r.geometry, {style:{color:"#e8482c",weight:6,opacity:.85}}).addTo(window.map);
        window.map.fitBounds(routeLayer.getBounds(), {padding:[40,40]});
      }

      steps = (r.legs || []).flatMap(leg => leg.steps || []).filter(step => step.maneuver);
      nextStep = 0;
      info.hidden = false;
      renderStep();
      const summary = document.createElement("div");
      summary.className = "muted";
      summary.textContent = "Totaal " + (r.distance / 1000).toFixed(1) + " km · ongeveer " + Math.round(r.duration / 60) + " min";
      info.appendChild(summary);
    } catch (e) {
      info.hidden = false;
      info.innerHTML = '<div class="instruction">⚠️ ' + (e.message || "Route zoeken mislukt") + '</div>';
    } finally {
      button.disabled = false;
      button.textContent = "Route";
    }
  }

  button.onclick = route;
  input.onkeydown = e => { if (e.key === "Enter") route(); };

  async function keepScreenOn() {
    try {
      if ("wakeLock" in navigator) await navigator.wakeLock.request("screen");
    } catch (_) {}
  }
  document.addEventListener("visibilitychange", keepScreenOn);
  keepScreenOn();
})();