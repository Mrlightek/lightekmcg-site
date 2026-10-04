namespace = "lightek.pwa.v1"
version = 1

surfaces = [
  {
    key: "home",
    type: "home",
    label: "Home",
    position: 10,
    modules: [
      ["hero-live", "hero", 10],
      ["following", "media_grid", 20],
      ["live-now", "live_grid", 30],
      ["communities", "community_grid", 40],
      ["trending-clips", "clip_strip", 50],
      ["continue-watching", "continue_watching", 60],
      ["creator-discovery", "creator_grid", 70]
    ]
  },

  {
    key: "watch",
    type: "watch",
    label: "Watch",
    position: 20,
    modules: [
      ["featured-broadcast", "hero", 10],
      ["guide", "schedule", 20],
      ["live-channels", "media_grid", 30],
      ["originals", "media_grid", 40],
      ["documentaries", "media_grid", 50],
      ["continue-watching", "continue_watching", 60]
    ]
  },

  {
    key: "clips",
    type: "clips",
    label: "Clips",
    position: 30,
    modules: [
      ["clip-stage", "clip_player", 10],
      ["clip-conversation", "conversation", 20],
      ["clip-related", "related_media", 30]
    ]
  },

  {
    key: "explore",
    type: "explore",
    label: "Explore",
    position: 40,
    modules: [
      ["search", "search", 10],
      ["topics", "topics", 20],
      ["worlds", "world_grid", 30],
      ["people", "creator_grid", 40],
      ["communities", "community_grid", 50],
      ["programs", "media_grid", 60],
      ["live", "live_grid", 70],
      ["clips", "clip_strip", 80]
    ]
  },

  {
    key: "communities",
    type: "communities",
    label: "Communities",
    position: 50,
    modules: [
      ["featured-community", "hero", 10],
      ["your-communities", "community_grid", 20],
      ["discover-communities", "community_grid", 30]
    ]
  },

  {
    key: "messages",
    type: "messages",
    label: "Messages",
    position: 60,
    modules: [
      ["threads", "message_threads", 10],
      ["conversation", "message_conversation", 20]
    ]
  },

  {
    key: "create",
    type: "create",
    label: "Create",
    position: 70,
    modules: [
      ["creation-types", "creation_catalog", 10],
      ["creation-editor", "creation_editor", 20],
      ["publish", "publish", 30]
    ]
  },

  {
    key: "space",
    type: "space",
    label: "My Space",
    position: 80,
    modules: [
      ["identity-hero", "identity_hero", 10],
      ["featured", "media_grid", 20],
      ["series", "media_grid", 30],
      ["clips", "clip_strip", 40],
      ["playlists", "media_grid", 50],
      ["posts", "post_grid", 60],
      ["about", "about", 70],
      ["communities", "community_grid", 80]
    ]
  }
]

surfaces.each do |surface_data|
  surface =
    LightekPwa::Surface.find_or_initialize_by(
      key: surface_data[:key]
    )

  surface.assign_attributes(
    surface_type: surface_data[:type],
    label: surface_data[:label],
    position: surface_data[:position],
    enabled: true,
    configuration: {},
    seed_namespace: namespace,
    seed_version: version
  )

  surface.save!

  surface_data[:modules].each do |key, type, position|
    mod =
      surface.modules.find_or_initialize_by(
        key: key
      )

    mod.assign_attributes(
      module_type: type,
      label: key.tr("-", " ").titleize,
      position: position,
      enabled: true,
      data_source: key,
      configuration: {},
      seed_namespace: namespace,
      seed_version: version
    )

    mod.save!
  end
end

# LIGHTEK MONEY SURFACE
money =
  LightekPwa::Surface.find_or_initialize_by(
    key: "money"
  )

money.assign_attributes(
  surface_type: "money",
  label: "Money",
  position: 60,
  enabled: true,
  configuration: {
    title: "Dymond",
    description:
      "Payments, invoices, Susu and money movement."
  },
  seed_namespace: namespace,
  seed_version: version
)

money.save!

[
  [
    "money-overview",
    "money_overview",
    "Overview",
    10
  ],
  [
    "payment-quote",
    "payment_quote",
    "Payment Quote",
    20
  ],
  [
    "susu",
    "susu",
    "Susu",
    30
  ],
  [
    "invoices",
    "invoices",
    "Invoices",
    40
  ],
  [
    "transactions",
    "transactions",
    "Transactions",
    50
  ]
].each do |key, type, label, position|
  mod =
    money.modules.find_or_initialize_by(
      key: key
    )

  mod.assign_attributes(
    module_type: type,
    label: label,
    position: position,
    enabled: true,
    data_source: key,
    configuration: {},
    seed_namespace: namespace,
    seed_version: version
  )

  mod.save!
end

# LIGHTEK STUDIO SURFACE
studio =
  LightekPwa::Surface.find_or_initialize_by(
    key: "studio"
  )

studio.assign_attributes(
  surface_type: "studio",
  label: "Studio",
  position: 70,
  enabled: true,
  configuration: {
    title: "Lightek Studio",
    description:
      "The creation operating system for Lightek."
  },
  seed_namespace: namespace,
  seed_version: version
)

studio.save!


navigation = [
  ["home", "Home", "home", "#/home", "primary", 10],
  ["watch", "Watch", "watch", "#/watch", "primary", 20],
  ["clips", "Clips", "clips", "#/clips", "primary", 30],
  ["explore", "Explore", "explore", "#/explore", "primary", 40],
  ["communities", "Communities", "communities", "#/communities", "primary", 50],
  ["money", "Money", "money", "#/money", "primary", 55],
  ["studio", "Studio", "studio", "#/studio", "primary", 57, "studio.pwa.bootstrap"],
  ["messages", "Messages", "messages", "#/messages", "tools", 60],
  ["create", "+ Create", "create", "#/create", "tools", 70],
  ["space", "My Space", "space", "#/space", "identity", 80]
]

navigation.each do |key, label, surface_key, href, placement, position, requires_capability|
  item =
    LightekPwa::NavigationItem.find_or_initialize_by(
      key: key
    )

  item.assign_attributes(
    label: label,
    surface_key: surface_key,
    href: href,
    placement: placement,
    position: position,
    enabled: true,
    requires_capability: requires_capability,
  configuration: {},
    seed_namespace: namespace,
    seed_version: version
  )

  item.save!
end

puts(
  "Lightek PWA seeded: " \
  "#{LightekPwa::Surface.count} surfaces, " \
  "#{LightekPwa::SurfaceModule.count} modules, " \
  "#{LightekPwa::NavigationItem.count} navigation items"
)
