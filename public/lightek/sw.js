const CACHE = "lightek-shell-v28"

const SHELL = [
  "/lightek/index.html",
  "/lightek/manifest.webmanifest",
  "/lightek/nevaeh-client.js",
  "/lightek/bootstrap-adapter.js",
  "/lightek/studio-viewport.js",
  "/lightek/vendor/gsap/gsap.min.js",
  "/lightek/vendor/three/three.core.js",
  "/lightek/vendor/three/three.module.js",
  "/lightek/vendor/three/addons/controls/OrbitControls.js",
  "/lightek/vendor/three/addons/controls/TransformControls.js",
  "/lightek/icons/icon.svg"
]

self.addEventListener("install", event => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then(cache => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", event => {
  event.waitUntil(
    caches
      .keys()
      .then(keys =>
        Promise.all(
          keys
            .filter(key => key !== CACHE)
            .map(key => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") return

  const url = new URL(event.request.url)

  if (url.origin !== self.location.origin) return

  if (!url.pathname.startsWith("/lightek/")) return

  if (
    event.request.mode === "navigate"
  ) {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          const copy = response.clone()

          caches
            .open(CACHE)
            .then(cache =>
              cache.put(
                "/lightek/index.html",
                copy
              )
            )

          return response
        })
        .catch(() =>
          caches.match(
            "/lightek/index.html"
          )
        )
    )

    return
  }

  event.respondWith(
    caches.match(event.request)
      .then(cached =>
        cached ||
        fetch(event.request)
          .then(response => {
            const copy = response.clone()

            caches
              .open(CACHE)
              .then(cache =>
                cache.put(
                  event.request,
                  copy
                )
              )

            return response
          })
      )
  )
})
