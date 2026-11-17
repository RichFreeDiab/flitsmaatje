(() => {
  const css = document.createElement("style");
  css.textContent = `
    #nav-tools{position:absolute;top:max(12px,env(safe-area-inset-top));right:12px;z-index:1003;background:#1e2327;padding:6px;border-radius:12px;display:flex;gap:6px}
    #nav-tools input{width:min(180px,48vw);padding:9px;border:0;border-radius:8px}
    #nav-tools button{padding:9px;border:0;border-radius:8px;background:#e8482c;color:white;font-weight:700}
    #route-info{position:absolute;top:64px;right:12px;z-index:1002;background:rgba(30,35,39,.92);color:white;padding:7px 10px;border-radius:10px;max-width:min(220px,70vw);font-size:12px}
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
  let routeSummary = "";
  let destinationQuery = "";
  let routeCoordinates = [];
  let lastRerouteAt = 0;

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

  function distanceMeters(a, b) {
    const rad = Math.PI / 180;
    const dLat = (b.lat - a.lat) * rad;
    const dLng = (b.lng - a.lng) * rad;
    const x = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
    return 6371000 * 2 * Math.asin(Math.sqrt(x));
  }

  function renderStep() {
    info.textContent = steps[nextStep] ? routeSummary : "🏁 Route voltooid";
    info.hidden = false;
  }

  async function route() {
    const query = input.value.trim();
    if (!query) return;
    destinationQuery = query;
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
      window.__fmDest = { lat: parseFloat(places[0].lat), lng: parseFloat(places[0].lon), query };
      const data = await fetch(
        "https://router.project-osrm.org/route/v1/driving/" + start + ";" + end +
        "?overview=full&geometries=geojson&steps=true&language=nl"
      ).then(r => {
        if (!r.ok) throw Error("Route berekenen mislukt");
        return r.json();
      });
      const r = data.routes && data.routes[0];
      if (!r) throw Error("Route niet gevonden");

      if (routeLayer && window.flitsmaatjeMap) window.flitsmaatjeMap.removeLayer(routeLayer);
      routeCoordinates = r.geometry && r.geometry.coordinates ? r.geometry.coordinates.map(c => ({lat:c[1], lng:c[0]})) : [];
      window.flitsmaatjeActiveRoute = (function(coords) {
        if (!coords || coords.length < 2) return null;
        const maxPoints = 80;
        const step = Math.max(1, Math.floor(coords.length / maxPoints));
        const sampled = [];
        for (let i = 0; i < coords.length; i += step) sampled.push(coords[i]);
        const last = coords[coords.length - 1];
        const prev = sampled[sampled.length - 1];
        if (!prev || prev.lat !== last.lat || prev.lng !== last.lng) sampled.push(last);
        return sampled.map(p => p.lat.toFixed(5) + "," + p.lng.toFixed(5)).join(";");
      })(routeCoordinates);
      if (window.flitsmaatjeMap && r.geometry) {
        routeLayer = L.geoJSON(r.geometry, {style:{color:"#e8482c",weight:6,opacity:.85}}).addTo(window.flitsmaatjeMap);
        window.flitsmaatjeMap.fitBounds(routeLayer.getBounds(), {padding:[40,40]});
      }

      steps = (r.legs || []).flatMap(leg => leg.steps || []).filter(step => step.maneuver);
      nextStep = 0;
      routeSummary = `Route · ${(r.distance / 1000).toFixed(1)} km · ca. ${Math.round(r.duration / 60)} min`;
      info.hidden = false;
      renderStep();
      window.dispatchEvent(new CustomEvent("flitsmaatje:nav"));
    } catch (e) {
      info.hidden = false;
      info.textContent = "⚠️ " + (e.message || "Route zoeken mislukt");
    } finally {
      button.disabled = false;
      button.textContent = "Route";
    }
  }

  button.onclick = route;
  input.onkeydown = e => { if (e.key === "Enter") route(); };

  window.addEventListener("flitsmaatje:position", (event) => {
    const p = event.detail;
    const step = steps[nextStep];
    if (!step || !step.maneuver || !step.maneuver.location) return;
    const target = {lat: step.maneuver.location[1], lng: step.maneuver.location[0]};
    if (routeCoordinates.length && Date.now() - lastRerouteAt > 15000) {
      const nearest = Math.min(...routeCoordinates.map(point => distanceMeters(p, point)));
      if (nearest > 120 && destinationQuery) {
        lastRerouteAt = Date.now();
        input.value = destinationQuery;
        route();
        return;
      }
    }
    if (distanceMeters(p, target) <= (window.FlitsMaatjeGuidance?.STEP_ADVANCE_M ?? 50)) {
      nextStep += 1;
      renderStep();
      const spoken = steps[nextStep];
      if (spoken && "speechSynthesis" in window) {
        window.speechSynthesis.cancel();
        const utterance = new SpeechSynthesisUtterance(instruction(spoken));
        utterance.lang = "nl-NL";
        window.speechSynthesis.speak(utterance);
      }
    }
  });


  window.flitsmaatjeNav = {
    hasRoute: () => steps.length > 0 && nextStep < steps.length,
    getNextStep: () => steps[nextStep] || null,
    getDestination: () => window.__fmDest || null,
    getSteps: () => steps.slice(),
    getStepIndex: () => nextStep,
    getRouteCoordinates: () => routeCoordinates.slice(),
  };
  window.dispatchEvent(new CustomEvent("flitsmaatje:nav"));

  async function keepScreenOn() {
    try {
      if ("wakeLock" in navigator) await navigator.wakeLock.request("screen");
    } catch (_) {}
  }
  document.addEventListener("visibilitychange", keepScreenOn);
  keepScreenOn();
})();