# Render a character animation in Studio

Open **Pipeline Hub** from Dashboard Studio or the Lightek Studio PWA. Under **Create a character animation**, set the character morphs and choose a Mixamo animation. Use the animation ID to resolve duplicate titles. The job page refreshes while Studio is working and shows the preview and logs when the attempt finishes.

If the job is waiting for Mixamo login, run this on the Studio worker host as the worker user in a graphical session.

```bash
cd ~/mixamo-mcp && python main.py
```

Complete sign-in, type `quit` in the CLI to release the browser profile, then select **Retry Job After Login**. To change the frame count or resolution after Mixamo supplies an animated FBX, use **Re-run Render Only**. This also works after a Blender or FFmpeg failure if the FBX was already saved.

## Worker setup

The Sidekiq worker that serves the `studio` queue needs Bash, Python 3, Blender with CPU Cycles, FFmpeg with libx264, and the Linux `timeout`, `flock`, and `realpath` utilities. The worker needs access to the Rails Active Storage service used by the web process. With the local service, mount the same storage volume on both.

- Install `makehuman-mcp==0.1.3` in the worker's Python 3 environment and initialize its MakeHuman data as that user. Set `MAKEHUMAN_PYTHON` in the worker environment to the absolute virtualenv interpreter path when it differs from `python3`.
- Install the Mixamo CLI in the worker user's `~/mixamo-mcp`, set up its Python requirements and run `python -m playwright install chromium` with the same interpreter the worker will use. Set `MIXAMO_PYTHON` to that interpreter when it differs from `python` on the worker's PATH.
- The wrapper detects the stock interactive CLI and uses its `browser_profile` through the existing Studio browser driver. `MIXAMO_CLI_MODE=positional` selects the command-line fork that accepts `python main.py status`, `list`, `upload`, `select`, and `download`. `MIXAMO_DIR` can point at an alternate checkout. Keep `~/mixamo-mcp` pointed at the same checkout for the displayed login command.
- Set `BLENDER_BIN` if Blender is installed outside the worker's PATH.

A worker-side check can run the shell pipeline directly. The output directory will contain `animated.fbx`, a generation-specific render directory with PNG frames, and the latest successful `preview.mp4`.

```bash
OUTPUT_DIR=/path/to/job GENDER=0.5 HEIGHT=0.5 MUSCLE=0.6 \
  MIXAMO_ANIMATION=Walking FRAMES=30 bash script/run_pipeline.sh
OUTPUT_DIR=/path/to/job FRAMES=15 RENDER_RESOLUTION=720x720 \
  bash script/run_pipeline.sh --render-only
```
