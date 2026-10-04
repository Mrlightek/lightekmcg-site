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

  function currentIdentity() {
    return (
      state.bootstrap?.identity ||
      null
    )
  }

  function currentProfile() {
    return (
      currentIdentity()?.profile ||
      null
    )
  }

  function signInHref(hash) {
    const target =
      (
        hash &&
        hash.startsWith("#/")
      )
        ? hash
        : "#/home"

    const returnTo =
      `/lightek/index.html${target}`

    return (
      "/session/new?return_to=" +
      encodeURIComponent(returnTo)
    )
  }

  function routeRequiresIdentity(route) {
    return (
      route === "create" ||
      route === "studio" ||
      route === "space"
    )
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

        const href =
          (
            item.key === "create" &&
            !currentIdentity()
          )
            ? signInHref("#/create")
            : item.href

        return `
          <a
            class="${classes}"
            href="${escapeHtml(href)}"
            data-r="${escapeHtml(item.surface_id)}"
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

    const identity =
      currentIdentity()

    if (!identity) {
      return `
        <a
          href="${escapeHtml(signInHref("#/space"))}"
          aria-label="Sign in"
          class="hd2 lightek-identity-nav"
        >Sign in</a>
      `
    }

    const profile =
      identity.profile || {}

    const name =
      profile.name ||
      "Lightek Member"

    const initials =
      name
        .trim()
        .split(/\s+/)
        .slice(0, 2)
        .map(part =>
          part.charAt(0)
        )
        .join("")
        .toUpperCase() ||
      "L"

    const avatar =
      profile.avatar_url
        ? `
          <img
            src="${escapeHtml(profile.avatar_url)}"
            alt=""
            style="
              display:block;
              width:32px;
              height:32px;
              border-radius:50%;
              object-fit:cover;
              border:1px solid var(--ln);
            "
          >
        `
        : `
          <span
            style="
              display:grid;
              place-items:center;
              width:32px;
              height:32px;
              border-radius:50%;
              background:var(--s2);
              border:1px solid var(--ln);
              color:var(--gd);
              font-size:11px;
              font-weight:700;
            "
          >${escapeHtml(initials)}</span>
        `

    return `
      <a
        href="${escapeHtml(item.href)}"
        aria-label="${escapeHtml(name)} — My Space"
        data-r="${escapeHtml(item.surface_id)}"
        class="lightek-identity-nav"
        title="${escapeHtml(name)}"
      >${avatar}</a>
    `
  }

  function renderNavigation() {
    if (
      state.navigation.length === 0 &&
      state.surfaces.size === 0
    ) {
      console.warn(
        "[Lightek] storefront configuration is empty; preserving static shell navigation"
      )

      updateActiveNavigation()
      return
    }

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

    if (
      routeRequiresIdentity(route) &&
      !currentIdentity()
    ) {
      window.location.assign(
        signInHref(
          window.location.hash ||
          `#/${route}`
        )
      )

      return
    }

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

      window.LightekIdentity =
        payload.identity || null

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
