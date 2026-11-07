# Studio native authoring workstation

Goal: complete import → author → animate → render → publish/live production in Lightek. This change exposes native Blender through an authenticated desktop inside Studio, alongside the existing guided authoring controls. No Tripo credential is required.

## Delivery and operation

The provisioning and native update adapters install the media tools, build `lightek/studio-workstation:20261107`, copy trusted noVNC files to host storage, install a per-application gateway and expiry timer, and configure the matching Apache virtual host. Run migrations and restart the Studio queue workers during the normal application release. `setup_studio_workstation.sh` runs as the application account; `install_studio_workstation.py` runs as root. Docker and Apache proxy modules must already be available through the platform installation.

Open a production, then choose **Open full Blender workstation**. The session starts from the production's pinned source. Task buttons select native editors. **Save version to Studio** packs resources, saves a separate Library asset and creates an editable production. The original production is retained. Use movie export and delivery for publishing; use a GLB stage in Live Studio for program composition.

Sessions last four hours and allow one active workstation per user. Default limits: four GiB RAM, up to two CPUs (clamped to Docker daemon capacity), 512 processes, 512 MiB shared memory. The desktop uses software OpenGL; GPU acceleration and frame-rate/latency targets are not verified by this change. Cache and resource files must remain under `/work` to be retained. Close native modal dialogs before switching or saving.

Each session has no network, no published ports, and no access to the app, credentials, Docker socket or host home. Its only writable persistent mount is its own working directory. The authenticated host gateway serves immutable noVNC code and bridges a private Unix socket. Owner/site checks, CSRF, signed session access, same-origin WebSockets, expiry and revocation protect entry. Automatic file scripts are disabled; explicitly installed native add-ons are not provided.

## Acceptance matrix

| Workflow/tool | Implementation | Evidence and remaining acceptance |
| --- | --- | --- |
| Native import and dependencies | Existing `.blend` and resource ZIP importer; immutable source pinned per production | Existing native import regression; workstation save test reimports a real bundled source |
| Mesh / sculpt / UV / texture painting | Full native Blender editors; guided Studio tools remain available | Native mesh/sculpt regression; UV and packed texture save/reopen test; every interactive brush/tool has not been individually exercised |
| Rig / constraints / animation | Pose, armature, constraints, Graph Editor, Dope Sheet and NLA in native desktop | Existing rig tests; constraint, interpolation and NLA data survive save/reopen; interactive rig authoring acceptance still required |
| Shader / geometry / compositor nodes | Native Blender graph editors and groups | Existing graph tests; shader links and compositor nodes survive save/reopen; arbitrary imported node libraries need project-specific checks |
| Physics / simulation | Native Blender settings and bake tools | Cloth settings and cache files survive package/save; actual complex simulation bakes need acceptance |
| Sequencing | Native video sequence editor | Sequence strip survives save/reopen; complete editorial conform workflow unverified |
| Save → Library → new production | Native F8 bridge, receipt hashes, packaged resources, immutable blob reimport | Real Blender standalone end-to-end test |
| Render → community publication | Existing Blender movie renderer and delivery dispatch | Workstation standalone test renders MP4 and publishes a video Post |
| Live composition | Existing GLB stage plus video/chroma depth plane and program capture | Existing stage/browser acceptance; full native Blender compositor streamed into a live program is not implemented here |
| Browser desktop | Isolated Xvfb/Blender/x11vnc, Unix WebSocket transport, trusted host noVNC | Mandatory container CI test checks actual desktop pixels, workspace selection and save; not runnable in the current socket-restricted workspace |
| Maya workflows and files | Blender-supported interchange only | Native `.ma`/`.mb`, Maya plug-ins, Arnold, Bifrost, XGen and feature-by-feature Maya equivalence are not implemented or claimed |

## Test commands

`BUNDLE_GEMFILE=test/standalone/Gemfile LIGHTEK_TEST_BLENDER=1 bundle exec ruby test/standalone/studio_workstation_checks.rb --name /test_workstation/`

`BLENDER_BIN=blender python3 -m unittest test/operations/studio_workstation_gateway_test.py test/operations/studio_workstation_bridge_test.py`

`NODE_PATH=/path/to/browser/node_modules node test/javascript/studio_workstation_test.cjs`

`docker build -t lightek/studio-workstation:20261107 docker/studio-workstation`

`LIGHTEK_TEST_WORKSTATION=1 NODE_PATH=/path/to/browser/node_modules python3 -m unittest test/operations/studio_workstation_container_test.py`

The desktop test must execute (not skip) on CI. It produces `tmp/workstation-desktop.png`. Green data round-trip tests alone do not establish interactive parity. Complete Blender/Maya parity remains an open acceptance goal; native Blender availability is broader tool access, not proof of all requested production workflows.

CPU budgets for media probes, imports, rendering, workstations and spatial containers use the daemon capacity reported by `docker info`. `STUDIO_WORKER_CPUS` sets the requested budget (default 2); `SPATIAL_WORKER_CPUS` can override it for spatial workers. A one-CPU server receives a one-CPU limit automatically; fractional budgets are preserved.
