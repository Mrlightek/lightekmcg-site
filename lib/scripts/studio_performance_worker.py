"""Run a reviewed engine image against two staged files and save a single MP4."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

engine, source_name, driver_name = sys.argv[1:]
work = Path("/work")
source, driver = Path(source_name), Path(driver_name)
output = work / "performance.mp4"
engine_home = Path("/opt/engine")


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=engine_home, check=True)


if engine == "musetalk":
    config = work / "performance.json"
    config.write_text(json.dumps({"take": {
        "video_path": str(source), "audio_path": str(driver), "result_name": output.name
    }}))
    run(sys.executable, "-m", "scripts.inference", "--version", "v15",
        "--inference_config", config, "--result_dir", work / "results",
        "--unet_model_path", "models/musetalkV15/unet.pth",
        "--unet_config", "models/musetalkV15/musetalk.json")
    shutil.move(work / "results" / "v15" / output.name, output)
elif engine == "liveportrait":
    run(sys.executable, "inference.py", "-s", source, "-d", driver, "-o", work)
    shutil.move(work / f"{source.stem}--{driver.stem}.mp4", output)
elif engine == "facefusion":
    run(sys.executable, "facefusion.py", "headless-run", "--source-paths", source,
        "--target-path", driver, "--output-path", output, "--processors", "face_swapper",
        "--face-swapper-model", "ghost_2_256", "--execution-providers", "cuda", "--temp-path", "/tmp", "--jobs-path", work / "jobs")
else:
    raise ValueError("Unknown performance engine")
