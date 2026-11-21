(() => {
  function connectPlayer() {
    const player = document.querySelector("video[data-tv-playback]");
    if (!player || player.dataset.connected) return;

    player.dataset.connected = "true";
    const status = document.querySelector("[data-tv-status]");
    const unavailable = () => { status.textContent = "This channel is temporarily unavailable."; };
    player.addEventListener("error", unavailable);

    let hls;
    if (player.dataset.tvFormat !== "hls" || player.canPlayType("application/vnd.apple.mpegurl")) {
      player.src = player.dataset.tvPlayback;
    } else if (window.Hls?.isSupported()) {
      hls = new window.Hls();
      hls.on(window.Hls.Events.ERROR, (_event, problem) => { if (problem.fatal) unavailable(); });
      hls.loadSource(player.dataset.tvPlayback);
      hls.attachMedia(player);
    } else {
      status.textContent = "This browser does not support live TV playback.";
    }
    const detach = window.LightekNielsenPlayback?.(player, () => {
      if (hls?.playingDate) return hls.playingDate.getTime() / 1000;
      const origin = player.getStartDate?.()?.getTime();
      return origin / 1000 + player.currentTime;
    });
    document.addEventListener("turbo:before-cache", () => {
      detach?.();
      hls?.destroy();
      delete player.dataset.connected;
    }, { once: true });

  }

  document.addEventListener("turbo:load", connectPlayer);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", connectPlayer, { once: true });
  else connectPlayer();
})();
