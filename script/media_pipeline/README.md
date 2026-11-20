# Lightek Studio 3D Pipeline

Open **Pipeline Hub** from Studio in Dashboard or the PWA. Choose the workspace that owns the assets and renders.

| Source | Transfer |
| --- | --- |
| MakeHuman | Drop a model in **Base Mesh**. Select **Prepare for Mixamo** to download the prepared FBX. |
| Mixamo | Upload the prepared FBX in Mixamo. Export the animation as FBX with skin, then return it to the same card. |
| Animatoon | Export GLB or FBX and drop it in **Voxel / Props**. |
| Unity | Export FBX/GLB, or upload a Unity asset package that contains portable model files. Choose the exact model path if the package contains several. Export Unity-native prefabs and serialized meshes to FBX in the Unity Editor first. |

For external glTF buffers and textures, upload the model and sidecar folder with the same relative paths. Use the **3D preview** or **Add to scene** actions once the card is ready. In the composer, choose an animation clip, adjust transforms, orbit to frame the shot, and use **Render video**. The worker uses the viewport camera and marks participating cards **Rendered** after verifying the MP4.

## Watch an export directory

In **Connect export folder**, download `sync_exports.py` and generate a 24-hour upload token. Copy the generated command and enter the token at the terminal prompt. The watcher waits for FBX/GLB files to settle, streams them to `POST /api/v1/assets/ingest`, and records accepted hashes in a local SQLite database. The API deduplicates repeat uploads and limits each request to 150 MB. Logging out ends the token's originating session. Use `--once` for a single pass and `--recursive` for nested directories.

Browser requests use the Rails session and CSRF protection. The watcher token is limited to creating ingest cards in its selected workspace. Production conversion and rendering use the existing `studio` Sidekiq queue, Active Storage, and the networkless Studio worker images. The images must include Blender 4.3+ with FBX, glTF, Cycles and FFmpeg support, plus `ffprobe` in the render image. The `/api/v1/assets/ingest` upload limit also applies at the reverse proxy. Use a request-body limit above 150 MB to allow multipart overhead.

## Standalone shell tools

Run the following from `script/media_pipeline` on the Linux worker. The first invocation reuses compatible tools already on the host. Where needed, it uses APT and installs verified Blender 4.5 LTS binaries on Ubuntu/Debian x86-64.

```
raw_drop/       Complete exports or folders containing one model plus sidecars
archive/        Processed exports and duplicate copies
ready_assets/   Normalized GLBs
renders/        Final MP4s
scripts/        Bash entry points and Blender helpers
character/      Optional MakeHuman and Mixamo automation
```

Copy exports into a temporary location and rename them into `raw_drop/` after the copy finishes. Place a glTF with external files inside a folder with its buffers and textures. Use the same filesystem for intake and archive so directory moves are atomic. The normalizer preserves hierarchy, skinning and morph targets. It uses import unit metadata and accepts `--scale-multiplier` for a source with incorrect units.

```bash
./scripts/bootstrap.sh
./scripts/normalize_glb.sh
asset=$(find ready_assets -maxdepth 1 -name '*.glb' -print -quit)
test -n "$asset"
./scripts/render_shot.sh --asset "$asset" --out renders/preview.mp4 \
  --engine CYCLES --start 1 --end 48 --fps 24 --resolution 640 360
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  --asset "$asset" --out renders/batch-preview.mp4 --end 48 --fps 24 > shots.tsv
./scripts/run_batch.sh shots.tsv
```

A batch row is a tab-delimited argument vector. Spaces in paths are literal. Shots run sequentially and the batch reports any failures with a nonzero exit status. Use `--clip 1=ClipName` to select the clip on the first asset and `--clip 1=-` for a rest pose. Cycles probes for a GPU and falls back to CPU after a recoverable GPU error.

## Optional character automation

Run as a dedicated Studio worker user with a private home directory. The setup script installs the pinned `makehuman-mcp` package, Playwright Chromium, and the Mixamo screen adapters. MakeHuman fetches its data pack on first use, or you can set `MHCORE_DATA` to an installed pack. The operator stores Chromium's persistent profile at `$LIGHTEK_CHARACTER_HOME/profile` if that environment variable is set, or in the service user's XDG data directory by default. To reuse a private Mixamo browser profile, set `MIXAMO_PROFILE` to its absolute path in both the worker and manual-login environments.

```bash
./character/run_pipeline.sh --job-dir renders/walking-job --out renders/walking.mp4 \
  --animation Walking --first 1 --last 48 --fps 24 --resolution 640 360
```

Mixamo searches by title and requires a unique exact match. If the results include several matches, rerun with the `--animation-id` shown in the error. The guard tries the saved Adobe session, then one non-interactive attempt. Optionally supply `MIXAMO_EMAIL` and `MIXAMO_PASSWORD` from your service secret store. Interactive verification always returns 42. The guard prints the exact manual login command for the worker user and profile.

Use a visible graphical session for manual login. With the same service environment and profile, run:

```bash
cd character
python=$(./setup_character.sh)
"$python" browser.py login
```

An unmapped skeleton or a rig that requires marker placement is a separate failure. For marker placement the operator prints a command to open the rig workflow visibly and download the animated FBX with skin. Resume the original job with `--animated-fbx`.

### Rails exit handling

```ruby
require "open3"

runner = Rails.root.join("script/media_pipeline/character/run_pipeline.sh").to_s
job_dir = Rails.root.join("storage/studio-tmp/character-#{SecureRandom.uuid}").to_s
movie = File.join(job_dir, "walking.mp4")

_stdout, stderr, status = Open3.capture3(
  runner, "--job-dir", job_dir, "--out", movie, "--animation", "Walking",
  "--first", "1", "--last", "48", "--fps", "24", "--resolution", "640", "360"
)

result = case status.exitstatus
when 42
  {state: :waiting_for_mixamo_login, instructions: stderr}
when 0
  {state: :completed, path: movie}
else
  Rails.logger.error("Character pipeline failed (#{status.exitstatus || status.termsig}): #{stderr.last(2000)}")
  {state: :failed, exit_code: status.exitstatus, signal: status.termsig}
end
```
