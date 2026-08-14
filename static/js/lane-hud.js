(() => {
  const arrowEl = document.getElementById("lane-arrow");
  const labelEl = document.getElementById("lane-label");
  const subEl = document.getElementById("lane-sub");
  const lanesEl = document.getElementById("lane-lanes");
  if (!arrowEl || !labelEl || !subEl || !lanesEl) return;

  const DIR_ICON = {
    straight: "↑",
    slight_left: "↖",
    slight_right: "↗",
    left: "←",
    right: "→",
    sharp_left: "↙",
    sharp_right: "↘",
    uturn: "↩",
  };

  let lastLaneFetch = 0;
  let lastLaneKey = "";

  function compassLabel(deg) {
    if (deg == null || !Number.isFinite(deg)) return "—";
    const names = ["N", "NO", "O", "ZO", "Z", "ZW", "W", "NW"];
    const idx = Math.round((((deg % 360) + 360) % 360) / 45) % 8;
    return names[idx];
  }

  function maneuverIcon(step) {
    if (!step || !step.maneuver) return "↑";
    const mod = (step.maneuver.modifier || "").toLowerCase();
    const type = (step.maneuver.type || "").toLowerCase();
    if (type.includes("uturn") || mod.includes("uturn")) return DIR_ICON.uturn;
    if (mod.includes("sharp left")) return DIR_ICON.sharp_left;
    if (mod.includes("sharp right")) return DIR_ICON.sharp_right;
    if (mod.includes("slight left")) return DIR_ICON.slight_left;
    if (mod.includes("slight right")) return DIR_ICON.slight_right;
    if (mod.includes("left")) return DIR_ICON.left;
    if (mod.includes("right")) return DIR_ICON.right;
    if (type === "arrive") return "🏁";
    return DIR_ICON.straight;
  }

  function directionIcon(name) {
    const n = String(name || "").toLowerCase();
    if (n.includes("LEFT") || n.includes("left")) {
      if (n.includes("SHARP") || n.includes("sharp")) return "↙";
      if (n.includes("SLIGHT") || n.includes("slight")) return "↖";
      return "←";
    }
    if (n.includes("RIGHT") || n.includes("right")) {
      if (n.includes("SHARP") || n.includes("sharp")) return "↘";
      if (n.includes("SLIGHT") || n.includes("slight")) return "↗";
      return "→";
    }
    if (n.includes("UTURN") || n.includes("u_turn") || n.includes("uturn")) return "↩";
    return "↑";
  }

  function renderLanes(section) {
    const lanes = (section && section.lanes) || [];
    if (!lanes.length) {
      lanesEl.hidden = true;
      lanesEl.innerHTML = "";
      return;
    }
    lanesEl.hidden = false;
    lanesEl.innerHTML = lanes.map((lane) => {
      const dirs = lane.directions || [];
      const icon = directionIcon(dirs[0] || "STRAIGHT");
      const cls = lane.follow ? "lane-chip follow" : "lane-chip";
      return `<span class="${cls}">${icon}</span>`;
    }).join("");
  }

  function updateHud() {
    const nav = window.flitsmaatjeNav;
    const heading = (typeof window.flitsmaatjeHeading === "number")
      ? window.flitsmaatjeHeading
      : null;
    const hasRoute = !!(nav && nav.hasRoute && nav.hasRoute());
    const step = hasRoute && nav.getNextStep ? nav.getNextStep() : null;

    if (heading != null && Number.isFinite(heading)) {
      arrowEl.style.transform = `rotate(${heading}deg)`;
    }

    if (hasRoute && step) {
      arrowEl.textContent = maneuverIcon(step);
      if (!(heading != null && Number.isFinite(heading))) {
        arrowEl.style.transform = "none";
      } else {
        // bij navigatie: toon maneuver-icoon rechtop, heading apart in sub
        arrowEl.style.transform = "none";
      }
      const road = step.name ? ` · ${step.name}` : "";
      const km = step.distance != null ? `${(step.distance / 1000).toFixed(1)} km` : "";
      labelEl.textContent = (step.maneuver && step.maneuver.instruction)
        ? step.maneuver.instruction
        : `${(step.maneuver && step.maneuver.modifier) || "rechtdoor"}${road}`;
      // Toon afritinformatie 2 km voor de afrit
      let afritInfo = "";
      if (step.distance != null && step.distance <= 2000 && step.distance > 0) {
        const afritNaam = step.name || "afrit";
        afritInfo = `Afrit ${afritNaam} over ${(step.distance / 1000).toFixed(1)} km`;
      }
      subEl.textContent = [
        km,
        heading != null ? `koers ${Math.round(heading)}° ${compassLabel(heading)}` : null,
        afritInfo || "rijbaan volgt",
      ].filter(Boolean).join(" · ");
      maybeFetchLanes(nav);
      return;
    }

    // Geen route: permanente koerspijl
    arrowEl.textContent = "↑";
    if (heading != null && Number.isFinite(heading)) {
      labelEl.textContent = `Koers ${compassLabel(heading)}`;
      subEl.textContent = `${Math.round(heading)}° · pijl blijft zichtbaar`;
    } else {
      labelEl.textContent = "Richting…";
      subEl.textContent = "Wacht op GPS-koers";
    }
    lanesEl.hidden = true;
    lanesEl.innerHTML = "";
  }

  async function maybeFetchLanes(nav) {
    const dest = nav.getDestination && nav.getDestination();
    const pos = window.flitsmaatjePos;
    if (!dest || !pos) return;
    const now = Date.now();
    const key = `${pos.lat.toFixed(3)},${pos.lng.toFixed(3)}>${dest.lat.toFixed(3)},${dest.lng.toFixed(3)}`;
    if (key === lastLaneKey && now - lastLaneFetch < 20000) return;
    if (now - lastLaneFetch < 8000) return;
    lastLaneFetch = now;
    lastLaneKey = key;
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 5000);
      const res = await fetch(
        `/api/lane-guidance?origin_lat=${pos.lat}&origin_lng=${pos.lng}` +
        `&destination_lat=${dest.lat}&destination_lng=${dest.lng}`,
        { signal: ctrl.signal }
      );
      clearTimeout(timer);
      const data = await res.json();
      const sections = data.sections || [];
      // nearest upcoming section
      let best = null;
      let bestDist = Infinity;
      for (const s of sections) {
        if (s.start_lat == null) continue;
        const dlat = (s.start_lat - pos.lat);
        const dlng = (s.start_lng - pos.lng);
        const dist = dlat * dlat + dlng * dlng;
        if (dist < bestDist) {
          bestDist = dist;
          best = s;
        }
      }
      renderLanes(best);
    } catch (_) {
      /* lane guidance is enhancement */
    }
  }

  window.addEventListener("flitsmaatje:position", updateHud);
  window.addEventListener("flitsmaatje:nav", updateHud);
  setInterval(updateHud, 1000);
  updateHud();
})();
