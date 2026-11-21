(() => {
  function connectPlayer() {
    const player = document.querySelector("video[data-tv-playback]");
    if (!player || player.dataset.connected) return;

    player.dataset.connected = "true";
    const status = document.querySelector("[data-tv-status]");
    const unavailable = () => { status.textContent = "This channel is temporarily unavailable."; };
    player.addEventListener("error", unavailable);

    if (player.dataset.tvFormat !== "hls" || player.canPlayType("application/vnd.apple.mpegurl")) {
      player.src = player.dataset.tvPlayback;
    } else if (window.Hls?.isSupported()) {
      const hls = new window.Hls();
      hls.on(window.Hls.Events.ERROR, (_event, problem) => { if (problem.fatal) unavailable(); });
      hls.loadSource(player.dataset.tvPlayback);
      hls.attachMedia(player);
      document.addEventListener("turbo:before-cache", () => {
        hls.destroy();
        delete player.dataset.connected;
      }, { once: true });
    } else {
      status.textContent = "This browser does not support live TV playback.";
    }
  }

  document.addEventListener("turbo:load", connectPlayer);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", connectPlayer, { once: true });
  else connectPlayer();
})();
