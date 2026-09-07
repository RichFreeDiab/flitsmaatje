(() => {
  const G = window.FlitsMaatjeGuidance;
  if (!G) return;

  const arrowEl = document.getElementById("lane-arrow");
  const labelEl = document.getElementById("lane-label");
  const subEl = document.getElementById("lane-sub");
  const lanesEl = document.getElementById("lane-lanes");
  const exitEl = document.getElementById("lane-exit");
  const laneTextEl = document.getElementById("lane-lane-text");
  const hudEl = document.getElementById("lane-hud");
  if (!arrowEl || !labelEl || !subEl || !lanesEl) return;

  // Upward-angled glyphs (Google Maps style) — no sideways ←/→.
  const DIR_ICON = {
    straight: "↑",
    slight_left: "↖",
    slight_right: "↗",
    left: "↖",
    right: "↗",
    sharp_left: "↰",
    sharp_right: "↱",
    uturn: "↩",
  };

  let lastLaneFetch = 0;
  let lastLaneKey = "";
  let lastFetchPos = null;
  let cachedLaneSection = null;
  let emptyLaneStreak = 0;
  let lastLaneDiagAt = 0;

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
    if (mod.includes("left") || type.includes("off ramp") || type.includes("fork")) {
      if (type.includes("off ramp") || type.includes("exit")) return DIR_ICON.slight_right;
      return DIR_ICON.left;
    }
    if (mod.includes("right")) return DIR_ICON.right;
    if (type === "arrive") return "🏁";
    return DIR_ICON.straight;
  }

  function directionIcon(name) {
    const n = String(name || "").toLowerCase();
    if (n.includes("left")) {
      if (n.includes("sharp")) return DIR_ICON.sharp_left;
      if (n.includes("slight")) return DIR_ICON.slight_left;
      return DIR_ICON.left;
    }
    if (n.includes("right")) {
      if (n.includes("sharp")) return DIR_ICON.sharp_right;
      if (n.includes("slight")) return DIR_ICON.slight_right;
      return DIR_ICON.right;
    }
    if (n.includes("uturn") || n.includes("u_turn")) return DIR_ICON.uturn;
    return DIR_ICON.straight;
  }

  function laneDisplayDirections(lane) {
    let dirs = (lane.directions || []).map((d) => String(d).toUpperCase());
    const follow = lane.follow ? String(lane.follow).toUpperCase() : null;
    if (follow && !dirs.includes(follow)) dirs.unshift(follow);
    if (!dirs.length) dirs = ["STRAIGHT"];
    if (dirs.length > 3) {
      if (follow && dirs.includes(follow)) {
        dirs = [follow].concat(dirs.filter((d) => d !== follow).slice(0, 2));
      } else {
        dirs = dirs.slice(0, 3);
      }
    }
    return dirs;
  }

  function setLaneText(text) {
    if (!laneTextEl) return;
    if (text) {
      laneTextEl.hidden = false;
      laneTextEl.textContent = text;
    } else {
      laneTextEl.hidden = true;
      laneTextEl.textContent = "";
    }
  }

  function setExitText(text) {
    if (!exitEl) return;
    if (text) {
      exitEl.hidden = false;
      exitEl.textContent = text;
    } else {
      exitEl.hidden = true;
      exitEl.textContent = "";
    }
  }

  function applyScaleClass(distanceM) {
    if (!hudEl) return;
    const mode = G.laneScaleMode(distanceM);
    hudEl.classList.remove("scale-far", "scale-prominent", "scale-execute");
    hudEl.classList.add(`scale-${mode}`);
  }

  function logLaneDiag(event, extra) {
    const now = Date.now();
    if (now - lastLaneDiagAt < 12000) return;
    lastLaneDiagAt = now;
    const payload = Object.assign(
      {
        event,
        emptyStreak: emptyLaneStreak,
        hasSection: Boolean(cachedLaneSection),
      },
      extra || {}
    );
    try {
      console.info("[FlitsMaatje lane]", payload);
    } catch (_) {
      /* ignore */
    }
  }

  function renderLanes(section, pos) {
    const lanes = (section && section.lanes) || [];
    if (!lanes.length) {
      lanesEl.hidden = true;
      lanesEl.innerHTML = "";
      delete lanesEl.dataset.hint;
      applyScaleClass(null);
      return;
    }
    const distanceM = G.laneSectionDistanceM(section, pos);
    applyScaleClass(distanceM);
    lanesEl.hidden = false;
    const followIdx = lanes.findIndex((l) => l.follow);
    lanesEl.innerHTML = lanes
      .map((lane, i) => {
        const dirs = laneDisplayDirections(lane);
        const follow = lane.follow ? String(lane.follow).toUpperCase() : null;
        const isFollow = Boolean(follow);
        const cls = isFollow ? "lane-chip follow" : "lane-chip";
        const title = isFollow
          ? `Volg baan ${i + 1}/${lanes.length}`
          : `Baan ${i + 1}`;
        const arrows = dirs
          .map((dir) => {
            const highlighted = follow && dir === follow;
            const arrowCls = highlighted || (isFollow && dirs.length === 1)
              ? "lane-arrow-glyph hi"
              : "lane-arrow-glyph";
            return `<span class="${arrowCls}">${directionIcon(dir)}</span>`;
          })
          .join("");
        return `<span class="${cls}" title="${title}"><span class="lane-stack">${arrows}</span><small>${i + 1}</small></span>`;
      })
      .join("");
    if (followIdx >= 0) {
      lanesEl.dataset.hint = G.laneRecommendationText(section);
    } else {
      lanesEl.dataset.hint = `${lanes.length} banen`;
    }
    logLaneDiag("render", {
      lanes: lanes.length,
      distanceM,
      scale: G.laneScaleMode(distanceM),
    });
  }

  function refreshCachedSection() {
    const pos = window.flitsmaatjePos;
    const heading =
      typeof window.flitsmaatjeHeading === "number" ? window.flitsmaatjeHeading : null;
    cachedLaneSection = G.pruneLaneSection(cachedLaneSection, pos, heading);
    const nav = window.flitsmaatjeNav;
    const step = nav && nav.getNextStep ? nav.getNextStep() : null;
    if (
      cachedLaneSection &&
      !G.shouldShowLaneSection(cachedLaneSection, step, pos)
    ) {
      cachedLaneSection = null;
    }
    renderLanes(cachedLaneSection, pos);
  }

  function updateHud() {
    const nav = window.flitsmaatjeNav;
    const pos = window.flitsmaatjePos;
    const heading =
      typeof window.flitsmaatjeHeading === "number"
        ? window.flitsmaatjeHeading
        : null;
    const hasRoute = !!(nav && nav.hasRoute && nav.hasRoute());
    const step = hasRoute && nav.getNextStep ? nav.getNextStep() : null;

    refreshCachedSection();

    if (heading != null && Number.isFinite(heading) && !(hasRoute && step)) {
      arrowEl.style.transform = `rotate(${heading}deg)`;
    }

    if (hasRoute && step) {
      arrowEl.textContent = maneuverIcon(step);
      arrowEl.style.transform = "none";
      const road = step.name ? ` · ${step.name}` : "";
      const km =
        step.distance != null ? `${(step.distance / 1000).toFixed(1)} km` : "";
      labelEl.textContent =
        step.maneuver && step.maneuver.instruction
          ? step.maneuver.instruction
          : `${(step.maneuver && step.maneuver.modifier) || "rechtdoor"}${road}`;

      const exitBanner = G.currentOrUpcomingExitBanner(nav, step);
      setExitText(exitBanner || "");

      const detail = G.guidanceDetailText(nav, step, cachedLaneSection, pos);
      setLaneText(
        detail && detail !== exitBanner
          ? detail
          : lanesEl.dataset.hint || (!lanesEl.hidden ? "Rijbaan" : "")
      );

      subEl.textContent = [
        km,
        heading != null
          ? `koers ${Math.round(heading)}° ${compassLabel(heading)}`
          : null,
      ]
        .filter(Boolean)
        .join(" · ");
      maybeFetchLanes(nav);
      return;
    }

    cachedLaneSection = null;
    setExitText("");
    setLaneText("");
    arrowEl.textContent = "↑";
    arrowEl.removeAttribute("title");
    applyScaleClass(null);
    if (heading != null && Number.isFinite(heading)) {
      labelEl.textContent = `Koers ${compassLabel(heading)}`;
      subEl.textContent = `${Math.round(heading)}° · pijl blijft zichtbaar`;
    } else {
      labelEl.textContent = "Richting…";
      subEl.textContent = "Wacht op GPS-koers";
    }
    lanesEl.hidden = true;
    lanesEl.innerHTML = "";
    delete lanesEl.dataset.hint;
  }

  async function maybeFetchLanes(nav) {
    const dest = nav.getDestination && nav.getDestination();
    const pos = window.flitsmaatjePos;
    if (!dest || !pos) return;
    const now = Date.now();
    const routeCoords = nav.getRouteCoordinates ? nav.getRouteCoordinates() : [];
    const waypoints = G.sampledRouteWaypoints(pos, routeCoords);
    const wpKey = waypoints.map((p) => `${p.lat.toFixed(3)},${p.lng.toFixed(3)}`).join("|");
    const key = `${pos.lat.toFixed(3)},${pos.lng.toFixed(3)}>${dest.lat.toFixed(3)},${dest.lng.toFixed(3)}:${wpKey}`;
    const distToLane = cachedLaneSection
      ? G.laneSectionDistanceM(cachedLaneSection, pos)
      : null;
    const approaching =
      distToLane != null && distToLane <= G.LANE_PROMINENT_M;
    const refreshMs = approaching ? 45000 : G.LANE_REFRESH_MS;
    const moveM = approaching
      ? G.LANE_REFRESH_MOVEMENT_M * 0.6
      : G.LANE_REFRESH_MOVEMENT_M;
    const moved =
      lastFetchPos && G.distanceMeters(lastFetchPos, pos) >= moveM;
    if (key === lastLaneKey && !moved && now - lastLaneFetch < refreshMs) return;
    if (now - lastLaneFetch < 8000) return;
    lastLaneFetch = now;
    lastLaneKey = key;
    lastFetchPos = { ...pos };
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 5000);
      let url =
        `/api/lane-guidance?origin_lat=${pos.lat}&origin_lng=${pos.lng}` +
        `&destination_lat=${dest.lat}&destination_lng=${dest.lng}`;
      if (waypoints.length) {
        url += `&waypoints=${encodeURIComponent(JSON.stringify(waypoints))}`;
      }
      const res = await fetch(url, { signal: ctrl.signal });
      clearTimeout(timer);
      const data = await res.json();
      const sections = data.sections || [];
      if (!sections.length) {
        emptyLaneStreak += 1;
        logLaneDiag("empty-response", { streak: emptyLaneStreak });
      } else {
        emptyLaneStreak = 0;
      }
      cachedLaneSection = G.pickBestLaneSection(sections, pos, routeCoords);
      updateHud();
    } catch (_) {
      logLaneDiag("fetch-error", {});
    }
  }

  window.addEventListener("flitsmaatje:position", updateHud);
  window.addEventListener("flitsmaatje:nav", updateHud);
  setInterval(updateHud, 1000);
  updateHud();
})();
