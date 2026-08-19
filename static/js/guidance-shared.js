(() => {
  const LANE_HORIZON_M = 3500;
  const LANE_REFRESH_MS = 90000;
  const LANE_REFRESH_MOVEMENT_M = 500;
  const LANE_ROUTE_ALIGNMENT_M = 250;
  const STEP_ADVANCE_M = 50;

  function distanceMeters(a, b) {
    const rad = Math.PI / 180;
    const dLat = (b.lat - a.lat) * rad;
    const dLng = (b.lng - a.lng) * rad;
    const x =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
    return 6371000 * 2 * Math.asin(Math.sqrt(x));
  }

  function cleanedExitName(value) {
    const cleaned = String(value || "")
      .replace(/^(richting|naar|towards)\s+/i, "")
      .replace(/[,;:.]+$/, "")
      .replace(/\s+/g, " ")
      .trim();
    if (!cleaned) return null;
    const lowered = cleaned.toLowerCase();
    if (lowered === "en" || lowered === "de" || lowered === "het") return null;
    return cleaned;
  }

  function firstRoadToken(text) {
    const match = String(text || "").match(/\b([ANSE]\d{1,3}[A-Za-z]?)\b/i);
    return match ? match[1].toUpperCase() : null;
  }

  /** Afrit nummer + naam — parity met iOS NavigationService.parseExit */
  function parseExit(step) {
    if (!step) return null;
    const type = String((step.maneuver && step.maneuver.type) || "").toLowerCase();
    const instruction = String(
      (step.maneuver && step.maneuver.instruction) || step.name || ""
    );
    const text = instruction.trim();
    if (!text) return null;

    const patterns = [
      /(?:neem|volg|rij)\s+(?:de\s+)?afrit\s+(\d+[A-Za-z]?)(?:\s*[:\-–,]\s*|\s+)(.+)?/i,
      /(?:neem|volg|rij)\s+(?:de\s+)?afslag\s+(\d+[A-Za-z]?)(?:\s*[:\-–,]\s*|\s+)(.+)?/i,
      /afrit\s+(\d+[A-Za-z]?)(?:\s*[:\-–,]\s*|\s+)(.+)?/i,
      /afslag\s+(\d+[A-Za-z]?)(?:\s*[:\-–,]\s*|\s+)(.+)?/i,
      /exit\s+(\d+[A-Za-z]?)(?:\s*[:\-–,]\s*|\s+)(.+)?/i,
      /off[\s\-]?ramp\s+(\d+[A-Za-z]?)(?:\s*[:\-–,]\s*|\s+)(.+)?/i,
    ];
    for (const re of patterns) {
      const m = text.match(re);
      if (m) {
        const number = m[1];
        let name = cleanedExitName(m[2] || "");
        if (!name) name = step.name || null;
        return { number, name: name || null };
      }
    }
    for (const token of ["afrit", "afslag"]) {
      const re = new RegExp(`\\b${token}\\s+(\\d+[A-Za-z]?)\\b`, "i");
      const m = text.match(re);
      if (m) return { number: m[1], name: step.name || null };
    }
    const lower = text.toLowerCase();
    if (
      lower.includes("afrit") ||
      lower.includes("afslag") ||
      lower.includes("off ramp") ||
      lower.includes("exit")
    ) {
      const road = firstRoadToken(text);
      if (road) return { number: "", name: road };
      const cleaned = cleanedExitName(
        text.replace(/\b(neem|volg|rij)\s+(de\s+)?(afrit|afslag|exit|off[\s\-]?ramp)\b/gi, "")
      );
      if (cleaned) return { number: "", name: cleaned };
      return { number: "", name: null };
    }
    return null;
  }

  function formatExitBanner(exit, distanceM) {
    if (!exit) return "";
    const dist =
      distanceM != null && distanceM > 0
        ? ` · ${(distanceM / 1000).toFixed(1)} km`
        : "";
    if (exit.number && exit.name) return `Afrit ${exit.number} · ${exit.name}${dist}`;
    if (exit.number) return `Afrit ${exit.number}${dist}`;
    if (exit.name) return `Afrit · ${exit.name}${dist}`;
    return `Afrit${dist}`;
  }

  function laneRecommendationText(section) {
    const lanes = (section && section.lanes) || [];
    if (!lanes.length) return "";
    const idx = lanes.findIndex((l) => l.follow);
    if (idx < 0) return "Houd je rijstrook aan";
    const follow = String(lanes[idx].follow || "").toUpperCase();
    const total = lanes.length;
    const fromLeft = idx + 1;
    const fromRight = total - idx;
    let directionHint = "voor rechtdoor";
    if (["LEFT", "SLIGHT_LEFT", "SHARP_LEFT"].includes(follow)) {
      directionHint = "voor linksaf";
    } else if (["RIGHT", "SLIGHT_RIGHT", "SHARP_RIGHT"].includes(follow)) {
      directionHint = "voor rechtsaf";
    } else if (["LEFT_U_TURN", "RIGHT_U_TURN", "U_TURN"].includes(follow)) {
      directionHint = "voor keren";
    }
    if (total === 1) return `Blijf op deze rijstrook (${directionHint})`;
    if (fromRight === 1) return `Neem de meest rechter rijstrook (${directionHint})`;
    if (fromLeft === 1) return `Neem de meest linker rijstrook (${directionHint})`;
    return `Neem rijstrook ${fromLeft} van links (${fromRight} van rechts, ${directionHint})`;
  }

  function stepDistanceAhead(nav, index) {
    const steps = nav.getSteps ? nav.getSteps() : [];
    const start = nav.getStepIndex ? nav.getStepIndex() : 0;
    if (index < start || index >= steps.length) return Infinity;
    let distance = 0;
    if (index === start) {
      distance = steps[index].distance || 0;
    } else {
      for (let i = start; i <= index; i++) {
        distance += steps[i].distance || 0;
      }
    }
    return distance;
  }

  function bestUpcomingExit(nav) {
    const steps = nav.getSteps ? nav.getSteps() : [];
    const start = nav.getStepIndex ? nav.getStepIndex() : 0;
    const horizon = Math.min(steps.length, start + 8);
    let best = null;
    for (let i = start; i < horizon; i++) {
      const distanceAhead = stepDistanceAhead(nav, i);
      if (distanceAhead > LANE_HORIZON_M) break;
      const exit = parseExit(steps[i]);
      if (!exit || !formatExitBanner(exit)) continue;
      const hasNumber = Boolean(exit.number);
      const hasName = Boolean(exit.name);
      const score = (hasNumber ? 2 : 0) + (hasName ? 1 : 0);
      if (best && score <= best.score) continue;
      best = { score, exit, step: steps[i], index: i, distanceAhead };
      if (score === 3) break;
    }
    return best;
  }

  function currentOrUpcomingExitBanner(nav, step) {
    const current = parseExit(step);
    if (current && formatExitBanner(current)) {
      return formatExitBanner(current, step && step.distance);
    }
    const upcoming = bestUpcomingExit(nav);
    if (!upcoming) return "";
    return formatExitBanner(upcoming.exit, upcoming.distanceAhead);
  }

  function shouldShowLaneSection(section, step, pos) {
    const lanes = (section && section.lanes) || [];
    if (!lanes.length || section.start_lat == null || section.start_lng == null) {
      return false;
    }
    if (pos) {
      const dist = distanceMeters(pos, { lat: section.start_lat, lng: section.start_lng });
      if (dist <= LANE_HORIZON_M) return true;
    }
    return step && step.distance != null && step.distance <= LANE_HORIZON_M;
  }

  function guidanceDetailText(nav, step, section, pos) {
    const parts = [];
    const exit = currentOrUpcomingExitBanner(nav, step);
    if (exit) parts.push(exit);
    if (section && shouldShowLaneSection(section, step, pos)) {
      const lane = laneRecommendationText(section);
      if (lane) parts.push(lane);
    }
    return parts.join(" · ");
  }

  function isBehindVehicle(coordinate, pos, heading) {
    if (heading == null || !Number.isFinite(heading)) return false;
    const rad = Math.PI / 180;
    const lat1 = pos.lat * rad;
    const lat2 = coordinate.lat * rad;
    const dLng = (coordinate.lng - pos.lng) * rad;
    const y = Math.sin(dLng) * Math.cos(lat2);
    const x =
      Math.cos(lat1) * Math.sin(lat2) -
      Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
    const bearing = ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
    const delta = Math.abs(((bearing - heading + 540) % 360) - 180);
    return delta > 105;
  }

  function pruneLaneSection(section, pos, heading) {
    if (!section || section.end_lat == null || section.end_lng == null || !pos) {
      return section;
    }
    const endDist = distanceMeters(pos, { lat: section.end_lat, lng: section.end_lng });
    if (endDist <= 90 && isBehindVehicle({ lat: section.end_lat, lng: section.end_lng }, pos, heading)) {
      return null;
    }
    return section;
  }

  function distanceFromRoutePolyline(point, routeCoordinates) {
    if (!routeCoordinates || routeCoordinates.length < 2) return Infinity;
    let minimum = Infinity;
    for (let i = 0; i < routeCoordinates.length - 1; i++) {
      const start = routeCoordinates[i];
      const end = routeCoordinates[i + 1];
      const dist = distanceMeters(point, start);
      minimum = Math.min(minimum, dist, distanceMeters(point, end));
    }
    return minimum;
  }

  function pickBestLaneSection(sections, pos, routeCoordinates) {
    let best = null;
    let bestDist = Infinity;
    for (const section of sections || []) {
      if (section.start_lat == null || section.start_lng == null) continue;
      const start = { lat: section.start_lat, lng: section.start_lng };
      const distToStart = distanceMeters(pos, start);
      if (distToStart > LANE_HORIZON_M) continue;
      if (routeCoordinates && routeCoordinates.length > 1) {
        const routeDist = distanceFromRoutePolyline(start, routeCoordinates);
        if (routeDist > LANE_ROUTE_ALIGNMENT_M) continue;
      }
      if (distToStart < bestDist) {
        bestDist = distToStart;
        best = section;
      }
    }
    return best;
  }

  function sampledRouteWaypoints(pos, routeCoordinates, maxPoints = 8) {
    if (!pos || !routeCoordinates || routeCoordinates.length < 2) return [];
    let nearestIndex = 0;
    let nearestDist = Infinity;
    routeCoordinates.forEach((point, index) => {
      const dist = distanceMeters(pos, point);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestIndex = index;
      }
    });
    const samples = [];
    let accumulated = 0;
    for (let i = nearestIndex + 1; i < routeCoordinates.length; i++) {
      accumulated += distanceMeters(routeCoordinates[i - 1], routeCoordinates[i]);
      if (accumulated >= 500) {
        samples.push(routeCoordinates[i]);
        accumulated = 0;
      }
      if (samples.length >= maxPoints) break;
    }
    return samples;
  }

  window.FlitsMaatjeGuidance = {
    LANE_HORIZON_M,
    LANE_REFRESH_MS,
    LANE_REFRESH_MOVEMENT_M,
    STEP_ADVANCE_M,
    distanceMeters,
    parseExit,
    formatExitBanner,
    laneRecommendationText,
    bestUpcomingExit,
    currentOrUpcomingExitBanner,
    shouldShowLaneSection,
    guidanceDetailText,
    pruneLaneSection,
    pickBestLaneSection,
    sampledRouteWaypoints,
  };
})();
