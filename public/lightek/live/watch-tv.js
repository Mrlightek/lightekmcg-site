(() => {
  function connectPlayer(root) {
    const video = root.querySelector("video[data-tv-playback]");
    if (root.dataset.connected || !video) return;
    root.dataset.connected = "true";
    const listeners = new AbortController();
    const query = name => root.querySelector(`[data-player-${name}]`);
    const status = root.querySelector("[data-tv-status]");
    const controls = query("controls");
    const isLive = video.dataset.tvFormat === "hls";
    const play = query("play");
    const mute = query("mute");
    const seek = query("seek");
    const live = query("live");
    const retry = query("retry");
    const fullscreen = query("fullscreen");
    let hls;
    let detach;

    const listen = (target, event, handler) => target.addEventListener(event, handler, { signal: listeners.signal });
    const unavailable = () => {
      status.textContent = "Playback is temporarily unavailable.";
      retry.hidden = false;
    };
    const windowBounds = () => {
      if (isLive && video.seekable.length) return [video.seekable.start(0), video.seekable.end(video.seekable.length - 1)];
      return [0, Number.isFinite(video.duration) ? video.duration : 0];
    };
    const refresh = () => {
      const [start, end] = windowBounds();
      play.textContent = video.paused ? "Play" : "Pause";
      mute.textContent = video.muted ? "Unmute" : "Mute";
      seek.disabled = end <= start;
      if (!seek.disabled) seek.value = Math.max(0, Math.min(1000, (video.currentTime - start) * 1000 / (end - start)));
      live.disabled = seek.disabled;
    };
    const connectSource = () => {
      hls?.destroy();
      hls = undefined;
      detach?.();
      detach = undefined;
      retry.hidden = true;
      status.textContent = "";
      if (!isLive || video.canPlayType("application/vnd.apple.mpegurl")) {
        if (video.getAttribute("src") === video.dataset.tvPlayback) video.load();
        else video.src = video.dataset.tvPlayback;
      } else if (window.Hls?.isSupported()) {
        hls = new window.Hls();
        hls.on(window.Hls.Events.ERROR, (_event, problem) => { if (problem.fatal) unavailable(); });
        hls.loadSource(video.dataset.tvPlayback);
        hls.attachMedia(video);
      } else {
        unavailable();
        status.textContent = "This browser does not support live TV playback.";
      }
      detach = window.LightekNielsenPlayback?.(video, () => {
        if (hls?.playingDate) return hls.playingDate.getTime() / 1000;
        const origin = video.getStartDate?.()?.getTime();
        return origin / 1000 + video.currentTime;
      });
    };
    listen(video, "error", unavailable);
    ["playing", "pause", "timeupdate", "durationchange", "progress", "volumechange"].forEach(event => listen(video, event, refresh));
    listen(play, "click", () => {
      if (video.paused) video.play().catch(() => { status.textContent = "Playback could not start. Please try again."; });
      else video.pause();
    });
    listen(mute, "click", () => { video.muted = !video.muted; });
    listen(seek, "change", () => {
      const [start, end] = windowBounds();
      if (end > start) video.currentTime = start + Number(seek.value) / 1000 * (end - start);
    });
    listen(live, "click", () => {
      const [start, end] = windowBounds();
      if (end > start) video.currentTime = Math.max(start, hls?.liveSyncPosition ?? (end - 2));
    });
    listen(fullscreen, "click", () => {
      if (document.fullscreenElement === root) document.exitFullscreen().catch(() => {});
      else if (root.requestFullscreen) root.requestFullscreen().catch(() => {});
      else video.webkitEnterFullscreen?.();
    });
    listen(retry, "click", connectSource);
    live.hidden = !isLive;
    fullscreen.hidden = !root.requestFullscreen && !video.webkitEnterFullscreen;
    listen(video, "loadedmetadata", () => {
      // Native controls are retained when embedded caption/audio selection is available.
      if (video.textTracks?.length || video.audioTracks?.length > 1) video.controls = true;
    });
    video.controls = false;
    controls.hidden = false;
    refresh();
    connectSource();

    document.addEventListener("turbo:before-cache", () => {
      detach?.();
      hls?.destroy();
      listeners.abort();
      video.controls = true;
      controls.hidden = true;
      delete root.dataset.connected;
    }, { once: true });
  }

  const connect = () => document.querySelectorAll("[data-lightek-player]").forEach(connectPlayer);
  document.addEventListener("turbo:load", connect);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", connect, { once: true });
  else connect();
})();
