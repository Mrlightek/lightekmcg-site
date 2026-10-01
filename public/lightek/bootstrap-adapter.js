(() => {
  const state = {
    bootstrap: null,
    navigation: [],
    surfaces: new Map(),
    capabilities: new Set(),
    ready: false
  }

  function routeName() {
    const value =
      window.location.hash
        .replace(/^#\//, "")
        .split("/")[0]

    return value || "home"
  }

  function surfaceForRoute(route) {
    if (route === "community") {
      return "communities"
    }

    return route
  }

  function capabilityAllowed(item) {
    if (!item.requires_capability) {
      return true
    }

    return state.capabilities.has(
      item.requires_capability
    )
  }

  function visibleNavigation() {
    return state.navigation.filter(
      capabilityAllowed
    )
  }

  function primaryMarkup(items) {
    return items
      .filter(
        item =>
          item.placement === "primary"
      )
      .map(
        item => `
          <a
            href="${item.href}"
            data-r="${item.surface_id}"
          >${escapeHtml(item.label)}</a>
        `
      )
      .join("")
  }

  function toolMarkup(items) {
    return items
      .filter(
        item =>
          item.placement === "tools"
      )
      .map(item => {
        const classes =
          item.key === "create"
            ? "btn p sm"
            : "hd2"

        return `
          <a
            class="${classes}"
            href="${item.href}"
            data-r="${item.surface_id}"
          >${escapeHtml(item.label)}</a>
        `
      })
      .join("")
  }

  function identityMarkup(items) {
    const item =
      items.find(
        candidate =>
          candidate.placement ===
          "identity"
      )

    if (!item) return ""

    return `
      <a
        href="${item.href}"
        aria-label="${escapeHtml(item.label)}"
        data-r="${item.surface_id}"
        class="lightek-identity-nav"
      >
        <span
          style="
            display:block;
            width:32px;
            height:32px;
            border-radius:50%;
            background:
              radial-gradient(
                120% 90% at 20% 10%,
                hsl(18 60% 38%),
                transparent 60%
              ),
              linear-gradient(
                160deg,
                hsl(48 40% 16%),
                #0a0a0e
              );
          "
        ></span>
      </a>
    `
  }

  function renderNavigation() {
    const items =
      visibleNavigation()

    const primary =
      document.querySelector(
        "#primary-nav"
      )

    const tools =
      document.querySelector(
        "#top .tools"
      )

    if (primary) {
      primary.innerHTML =
        primaryMarkup(items)
    }

    if (tools) {
      tools.innerHTML =
        toolMarkup(items) +
        identityMarkup(items)
    }

    updateActiveNavigation()
  }

  function updateActiveNavigation() {
    const current =
      surfaceForRoute(
        routeName()
      )

    document
      .querySelectorAll(
        "#primary-nav [data-r], #top .tools [data-r]"
      )
      .forEach(link => {
        link.classList.toggle(
          "on",
          link.dataset.r === current
        )
      })
  }

  function guardCurrentRoute() {
    const route =
      routeName()

    const surface =
      surfaceForRoute(route)

    if (
      state.surfaces.has(surface)
    ) {
      return
    }

    if (
      state.surfaces.has("home")
    ) {
      window.location.hash =
        "#/home"
    }
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(
        /[&<>"]/g,
        character => ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;"
        })[character]
      )
  }

  function acceptBootstrap(payload) {
    if (
      !payload ||
      !Array.isArray(
        payload.surfaces
      ) ||
      !Array.isArray(
        payload.navigation
      )
    ) {
      throw new Error(
        "Invalid Lightek bootstrap payload"
      )
    }

    state.bootstrap =
      payload

    state.navigation =
      payload.navigation

    state.surfaces =
      new Map(
        payload.surfaces.map(
          surface => [
            surface.key,
            surface
          ]
        )
      )

    state.capabilities =
      new Set(
        (
          payload.capabilities ||
          []
        ).map(
          capability =>
            capability.slug
        )
      )

    state.ready = true

    renderNavigation()
    guardCurrentRoute()

    document.documentElement
      .setAttribute(
        "data-lightek-bootstrap",
        "ready"
      )

    window.dispatchEvent(
      new CustomEvent(
        "lightek.bootstrap.ready",
        {
          detail: payload
        }
      )
    )
  }

  async function boot() {
    if (
      !window.nevaeh ||
      typeof window.nevaeh.bootstrap !==
        "function"
    ) {
      throw new Error(
        "Nevaeh client unavailable"
      )
    }

    const payload =
      await window.nevaeh
        .bootstrap()

    acceptBootstrap(payload)

    return payload
  }

  window.addEventListener(
    "hashchange",
    () => {
      if (!state.ready) return

      guardCurrentRoute()
      updateActiveNavigation()
    }
  )

  window.LightekStorefront = {
    state,

    boot,

    surface(key) {
      return state.surfaces.get(
        key
      )
    },

    modules(key) {
      return (
        state.surfaces.get(key)
          ?.modules || []
      )
    },

    hasCapability(slug) {
      return state.capabilities.has(
        slug
      )
    }
  }

  boot()
    .then(payload => {
      console.info(
        "[Lightek] storefront ready",
        {
          surfaces:
            payload.surfaces.length,

          navigation:
            payload.navigation.length,

          capabilities:
            (
              payload.capabilities ||
              []
            ).length
        }
      )
    })
    .catch(error => {
      console.error(
        "[Lightek] bootstrap failed; using static fallback shell",
        error
      )

      document.documentElement
        .setAttribute(
          "data-lightek-bootstrap",
          "fallback"
        )
    })
})()
