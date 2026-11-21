(() => {
  function sdk(appId, debug) {
    const instanceName = "LightekLive";
    const namespace = window.NOLBUNDLE ||= {};
    if (namespace[instanceName]) return namespace[instanceName];

    if (typeof namespace.nlsQ === "function") {
      return namespace.nlsQ(appId, instanceName, debug ? { nol_sdkDebug: "debug" } : {});
    }

    const instance = {
      g: debug ? { nol_sdkDebug: "debug" } : {},
      trackEvent(event) {
        (this.te ||= []).push(event);
        if (this.te.length > 60) this.te.shift();
      },
      ggPM(...args) { (this.q ||= []).push(args); }
    };
    namespace[instanceName] = instance;
    const script = document.createElement("script");
    script.async = true;
    script.src = `https://cdn-gl.imrworldwide.com/conf/${appId}.js#name=${instanceName}&ns=NOLBUNDLE`;
    document.head.append(script);
    return instance;
  }

  window.LightekNielsenPlayback = function (player, clock) {
    const consent = document.querySelector("[data-nielsen-app]");
    if (!consent) return () => {};
    let meter, timer, timeline = [], pending, last, lastTimeline = 0, waiting = false;
    let preference = false;
    try { preference = localStorage.getItem("lightek-nielsen-consent") === "yes"; } catch (_) {}
    consent.checked = preference && navigator.globalPrivacyControl !== true;

    function event(name, frame = last) {
      if (!meter || !frame) return;
      const metadata = { content: frame.content };
      if (frame.ad) metadata.ad = frame.ad;
      meter.trackEvent({ event: name, type: frame.ad ? "ad" : "content", metadata, playheadPosition: String(frame.position) });
    }

    function refresh() {
      if (pending) return;
      lastTimeline = Date.now();
      pending = fetch(consent.dataset.nielsenTimeline, { cache: "no-store", credentials: "same-origin" })
        .then(response => response.ok ? response.json() : null)
        .then(result => { timeline = Array.isArray(result?.timeline) ? result.timeline : []; })
        .catch(() => { timeline = []; })
        .finally(() => { pending = null; });
    }

    function tick() {
      if (!consent.checked || player.paused || player.ended || waiting || player.seeking || player.readyState < 2) return;
      if (Date.now() - lastTimeline > 3000) refresh();
      const current = clock();
      if (!Number.isFinite(current)) return;
      const entry = timeline.findLast(item => current >= item.from && current < item.to);
      if (!entry) return;

      const position = Math.floor(current);
      if (last?.content.assetid !== entry.content.assetid) {
        event("complete");
        last = null;
      } else if (last?.ad && last.ad.assetid !== entry.ad?.assetid) {
        event("adStop");
        last = null;
      }
      if (last?.position === position && last?.ad?.assetid === entry.ad?.assetid) return;
      meter ||= sdk(consent.dataset.nielsenApp, consent.dataset.nielsenDebug === "true");
      last = { ...entry, position };
      event("playhead");
    }

    function start() {
      waiting = false;
      if (!timer && consent.checked) timer = setInterval(tick, 250);
      tick();
    }

    function pause() {
      waiting = true;
      event("pause");
    }

    function end() {
      clearInterval(timer);
      timer = null;
      event("complete");
      last = null;
    }

    function change() {
      if (navigator.globalPrivacyControl === true) consent.checked = false;
      try { localStorage.setItem("lightek-nielsen-consent", consent.checked ? "yes" : "no"); } catch (_) {}
      if (consent.checked) start();
      else { last = null; end(); }
    }

    consent.addEventListener("change", change);
    player.addEventListener("playing", start);
    player.addEventListener("pause", pause);
    player.addEventListener("waiting", pause);
    player.addEventListener("seeking", pause);
    player.addEventListener("seeked", start);
    player.addEventListener("ended", end);
    window.addEventListener("pagehide", end);
    return () => {
      end();
      consent.removeEventListener("change", change);
      player.removeEventListener("playing", start);
      player.removeEventListener("pause", pause);
      player.removeEventListener("waiting", pause);
      player.removeEventListener("seeking", pause);
      player.removeEventListener("seeked", start);
      player.removeEventListener("ended", end);
      window.removeEventListener("pagehide", end);
    };
  };
})();
