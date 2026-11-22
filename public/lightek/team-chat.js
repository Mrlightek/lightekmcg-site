(() => {
  const panel = document.querySelector("[data-team-timeline-url]")
  if (!panel) return

  let wakeup
  let refreshing = false

  function scheduleRefresh() {
    window.clearTimeout(wakeup)
    if (panel.isConnected && !document.hidden) wakeup = window.setTimeout(refresh, 8_000)
  }

  async function refresh() {
    if (!panel.isConnected || document.hidden || refreshing) return
    refreshing = true

    try {
      const response = await fetch(panel.dataset.teamTimelineUrl, { cache: "no-store" })
      if (response.redirected || [401, 403, 404].includes(response.status)) {
        window.location.reload()
        return
      }
      if (!response.ok) return

      const html = new DOMParser().parseFromString(await response.text(), "text/html")
      const next = html.getElementById("team-timeline")
      const current = panel.querySelector("#team-timeline")
      if (next && current && next.dataset.messageIds !== current.dataset.messageIds && !current.contains(document.activeElement)) {
        current.replaceWith(next)
      }
    } catch {
      // Keep the last loaded timeline visible while the connection recovers.
    } finally {
      refreshing = false
      scheduleRefresh()
    }
  }

  document.addEventListener("visibilitychange", scheduleRefresh)
  scheduleRefresh()
})()
