# Studio and Blender from Nevaeh

Studio's existing native capabilities remain the authoring API. Ubuntu installation and Studio scene authoring are different stages.

## Check what is connected

```text
/capabilities
/describe studio.workspace.blender.runtime.status
studio.workspace.blender.runtime.status
studio.workspace.assets.list
```

Your account must have access to the application and its Studio surface. When multiple applications are available without a host mapping, supply the authorized site_id. These read operations report runtime/library availability; they do not create or publish a scene.

## Create a project

Administrators can use:

```text
create a Studio project called Opening Night
```

This queues the existing structured worker/ticket pipeline. Inspect the receipt and ticket acceptance evidence. Then open the project in Studio to obtain its scene IDs and author the scene.

## Use scene operations

Open the exact capability reference for Blender authoring, scene objects, assets, timeline, render and publishing. Replace scene/project/asset IDs with your own. Where an input schema is not published, the Guide flags that gap and provides implementation hints plus the installed Studio manuals; it does not invent executable payloads.

Scene saving uses scene_id, the current lock_version, and a workspace object. Re-read a scene after a stale-edit error. Importing an asset, rendering, publishing and going live are separate operations with their own receipts and permissions. Never infer a published stream from an asset-import receipt.

## Workers and watchers

Delegate a configured production worker with `/delegate muse /run WORKER_ID`. A watcher can trigger a reviewed worker when a source changes, using response command and a structured run command. Existing structured workflow sections define dependencies and output references.

See the installed Studio manuals in Software Library for the current Blender/runtime and broadcasting workflows.
