const CACHE = "lightek-shell-v119-character-focus"

const SHELL = [
  "/lightek/index.html",
  "/lightek/manifest.webmanifest",
  "/lightek/nevaeh-client.js?v=66",
  "/lightek/bootstrap-adapter.js?v=93",
  "/lightek/application-settings.js?v=93",
  "/lightek/community-app.js",
  "/lightek/membership.js",
  "/lightek/creator-support.js",
  "/lightek/youtube-publishing.js",
  "/lightek/remote-content.js",
  "/lightek/studio-app.js",
  "/lightek/nevaeh-reply-stream.js?v=1",
  "/lightek/studio-unified.js?v=19",
  "/lightek/studio-unified.css?v=6",
  "/lightek/studio-media.js",
  "/lightek/studio-community-hub.js",
  "/lightek/studio-native.js",
  "/lightek/studio-workflows.js",
  "/lightek/studio-spatial.js",
  "/lightek/spatial/projection.js",
  "/lightek/spatial/video-sources.js",
  "/lightek/spatial/compositor.js",
  "/lightek/spatial/tracker.js",
  "/lightek/spatial/vision-worker.js",
  "/lightek/spatial/experience.js",
  "/lightek/spatial/scene-content.js",
  "/lightek/spatial/output.js",
  "/lightek/spatial/remote-panel.js",
  "/lightek/spatial/generation-panel.js",
  "/lightek/spatial/server-depth.js",
  "/lightek/spatial/feed-stage.js",
  "/lightek/spatial/community-feed.js",
  "/lightek/spatial/rtc/SpatialSocket.js",
  "/lightek/spatial/rtc/BlenderStream.js",
  "/lightek/studio-create.js",
  "/lightek/studio-authoring.js",
  "/lightek/studio-performance.js",
  "/lightek/studio-motion.js",
  "/lightek/studio-performance.css?v=70",
  "/lightek/studio-visual.js",
  "/lightek/studio-visual.css",
  "/lightek/studio-music-core.js",
  "/lightek/studio-music-audio.js",
  "/lightek/studio-music-recording.js",
  "/lightek/studio-music-recorder-worklet.js?v=83",
  "/lightek/studio-music.js",
  "/lightek/studio-music.css",
  "/lightek/vendor/tone/Tone-15.1.22.js",
  "/lightek/vendor/tone/Midi-2.0.28.js",

  "/lightek/studio-authoring.css",
  "/lightek/asset-preview.js",
  "/lightek/vendor/hls/hls.light.min.js",
  "/lightek/vendor/three/addons/loaders/GLTFLoader.js",
  "/lightek/vendor/three/addons/utils/BufferGeometryUtils.js",
  "/lightek/vendor/three/addons/utils/SkeletonUtils.js",
  "/lightek/community-app.css",
  "/lightek/studio-viewport.js",
  "/lightek/studio-mesh-commands.js",
  "/lightek/studio-shots.js",
  "/lightek/studio-shots.css",
  "/lightek/vendor/gsap/gsap.min.js",
  "/lightek/vendor/three/three.core.js",
  "/lightek/vendor/three/three.module.js",
  "/lightek/vendor/three/addons/controls/OrbitControls.js",
  "/lightek/vendor/three/addons/controls/TransformControls.js",
  "/lightek/icons/icon.svg",
  "/lightek/icons/icon-180.png",
  "/lightek/icons/icon-192.png",
  "/lightek/icons/icon-512.png"
]

self.addEventListener("install", event => {
  event.waitUntil(
    caches
      .open(CACHE)
      // A new CacheStorage name must not copy old bytes from the HTTP cache.
      .then(cache => cache.addAll(SHELL.map(path => new Request(path, { cache: "reload" }))))
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
          if (!response.ok) return response
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
            if (!response.ok) return response
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
