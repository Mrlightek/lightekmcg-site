# Lightek Studio architecture v2

Studio is no longer modeled as a Rails wrapper around Blender. Rails remains the control plane, but Studio now owns four product planes and delegates execution to specialized providers.

## Product planes

### Creative

- `StudioProject` — durable creative workspace.
- `Production` — film, series, episode, social, commercial, live, or event unit.
- `StudioScene` — editable scene state.
- `SceneObject` — scene graph objects and definitions.

### Execution

- `StudioOperation` is the universal executable unit.
- `operation_type` says what Studio is doing.
- `provider` says which engine performs it.
- `capability` is the Gatekeeper authorization boundary.
- `intent` records what the human/Nevaeh asked for.
- `manifest` records the immutable execution contract.
- `cost_quote` reserves the Dymond Bank metering/quote contract.

The first provider remains Blender and uses the existing manifest contract. `CreationJob` remains temporarily for compatibility but is no longer the forward architecture.

### Artifact

Artifacts are reusable outputs of Studio operations: `.blend`, GLB, preview, video, audio, poster, thumbnail, subtitle, or packaged delivery assets. A single artifact can be distributed to multiple destinations.

### Distribution + live

`StudioPublication` models scheduled or immediate delivery to:

- TikTok
- Instagram
- Facebook
- Lightek Social
- Lightek Streaming

`StudioLiveOperation` models a live broadcast session, including response policy, moderation policy, metrics, credential reference, and Gatekeeper operation linkage.

## Nevaeh and Gatekeeper

Nevaeh is the creative/operational intelligence layer. Studio stores structured intent; Nevaeh plans against the KB and applicable procedures. Gatekeeper is the execution authorization boundary.

The intended path is:

```text
Human intent
  -> Nevaeh
  -> KB / policy / procedure
  -> Gatekeeper capability authorization
  -> StudioOperation / StudioPublication / StudioLiveOperation
  -> provider adapter
  -> artifact / platform result
```

Unknown or unhandled conditions should remain in the existing ticket/knowledge loop rather than being silently improvised.

## Vault

External platform adapters never own raw credentials. They request a Vault checkout scoped to a consumer and purpose. Production intentionally fails closed when Lightek Vault is unavailable.

Expected records include:

```text
tiktok-studio-production
instagram-studio-production
facebook-studio-production
lightek-social-production
lightek-streaming-production
```

## Compute and monetization

The execution layer is intentionally provider-agnostic so Gatekeeper can later route work across shared or dedicated Linode workers based on plan entitlements. Dymond Bank can meter compute, storage, delivery, priority, and other operation costs through the `cost_quote` contract without exposing infrastructure details to customers.
