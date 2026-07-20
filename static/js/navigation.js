
(() => {
  const css = document.createElement("style");
  css.textContent = `
    #nav-tools{position:absolute;top:16px;right:12px;z-index:1003;background:#1e2327;padding:8px;border-radius:12px;display:flex;gap:6px}
    #nav-tools input{width:230px;padding:10px;border:0;border-radius:8px}
    #nav-tools button{padding:10px;border:0;border-radius:8px;background:#e8482c;color:white;font-weight:700}
    #route-info{position:absolute;top:76px;right:12px;z-index:1002;background:#1e2327;color:white;padding:10px;border-radius:10px;max-width:280px}
  `;
  document.head.appendChild(css);

  document.body.insertAdjacentHTML("beforeend",
    '<div id="nav-tools"><input id="destination" placeholder="Adres of plaats"><button id="route-btn">Route</button></div><div id="route-info" hidden></div>'
  );

  const input = document.getElementById("destination");
  const button = document.getElementById("route-btn");
  const info = document.getElementById("route-info");

  async function route() {
    const query = input.value.trim();
    if (!query) return;
    button.disabled = true;
    button.textContent = "Zoeken...";
    try {
      const places = await fetch(
        "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=nl&q=" +
        encodeURIComponent(query),
        {headers: {"Accept-Language": "nl"}}
      ).then(r => r.json());

      if (!places.length) throw Error("Adres niet gevonden");

      const pos = await new Promise((resolve, reject) =>
        navigator.geolocation.getCurrentPosition(resolve, reject)
      );

      const start = pos.coords.longitude + "," + pos.coords.latitude;
      const end = places[0].lon + "," + places[0].lat;
      const data = await fetch(
        "https://router.project-osrm.org/route/v1/driving/" +
        start + ";" + end + "?overview=false"
      ).then(r => r.json());

      const r = data.routes && data.routes[0];
      if (!r) throw Error("Route niet gevonden");

      info.textContent =
        "Route: " + places[0].display_ " +name + " 
        (r.distance / 1000).toFixed(1) + " km, ongeveer " +
        Math.round(r.duration / 60) + " minuten";
      info.hidden = false;
    } catch (e) {
      alert(e.message || "Route zoeken mislukt");
    } finally {
      button.disabled = false;
      button.textContent = "Route";
    }
  }

  button.onclick = route;
  input.onkeydown = e => { if (e.key === "Enter") route(); };

  async function keepScreenOn() {
    try {
      if ("wakeLock" in navigator)
        await navigator.wakeLock.request("screen");
    } catch (_) {}
  }

  document.addEventListener("visibilitychange", keepScreenOn);
  keepScreenOn();
})();
