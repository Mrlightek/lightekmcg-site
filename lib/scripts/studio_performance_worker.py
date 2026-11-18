"""Run a reviewed CPU engine against two staged files and save a single MP4."""
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys

engine, source_name, driver_name = sys.argv[1:]
work = Path("/work")
source, driver = Path(source_name), Path(driver_name)
output = work / "performance.mp4"
engine_home = Path("/opt/engine")
image_extensions = {".jpg", ".png", ".webp"}

# MuseTalk selects CPU when CUDA is unavailable. LivePortrait and FaceFusion
# also select their CPU backend explicitly below.
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["XDG_CACHE_HOME"] = str(work / ".cache")
os.environ["NUMBA_CACHE_DIR"] = str(work / ".cache" / "numba")
sys.dont_write_bytecode = True
os.environ.setdefault("OMP_NUM_THREADS", "2")
os.environ.setdefault("MKL_NUM_THREADS", "2")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "2")
os.environ.setdefault("OPENCV_FOR_THREADS_NUM", "2")
os.environ.setdefault("TORCH_HOME", str(engine_home / ".cache" / "torch"))
if hasattr(os, "sched_getaffinity"):
    # ONNX Runtime also sizes its default thread pools from visible CPUs.
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:2])


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=engine_home, check=True)


def prepare_media(path, name, kind):
    # Normalize phone formats and bound decoded frames for the CPU engines.
    if kind == "audio":
        destination = work / f"{name}.wav"
        options = ["-map", "0:a:0", "-t", "15", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le"]
    elif kind == "image":
        destination = work / f"{name}.png"
        options = ["-map", "0:v:0", "-frames:v", "1",
                   "-vf", "scale=w='min(iw,1280)':h='min(ih,720)':force_original_aspect_ratio=decrease",
                   "-update", "1"]
    else:
        destination = work / f"{name}.mp4"
        options = ["-map", "0:v:0", "-map", "0:a:0?", "-t", "15",
                   "-vf", "scale=w='min(iw,1280)':h='min(ih,720)':force_original_aspect_ratio=decrease:force_divisible_by=2,fps=24",
                   "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p", "-c:a", "aac"]
    run("ffmpeg", "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe",
        "-threads", "2", "-i", path, "-filter_threads", "2", *options, "-threads", "2", destination)
    return destination


def run_musetalk(*args):
    os.chdir(engine_home)
    sys.path.insert(0, str(engine_home))
    import torch
    from accelerate import init_empty_weights
    from musetalk.models import unet

    class CpuUNet:
        def __init__(self, unet_config, model_path, device=None):
            config = json.loads(Path(unet_config).read_text())
            with init_empty_weights():
                self.model = unet.UNet2DConditionModel(**config)
            # Assign memory-mapped weights directly to avoid allocating both
            # the 3.4 GB checkpoint and another full copy of the model.
            state = torch.load(model_path, map_location="cpu", weights_only=True, mmap=True)
            self.model.load_state_dict(state, assign=True)

    unet.UNet = CpuUNet
    sys.argv = ["scripts.inference", *map(str, args)]
    runpy.run_module("scripts.inference", run_name="__main__", alter_sys=True)


def run_facefusion(*args):
    # Cap memory retained by CPU ONNX sessions across the detector, analyser
    # and swapper. The pinned FaceFusion version creates them via this module.
    os.chdir(engine_home)
    sys.path.insert(0, str(engine_home))
    from facefusion import inference_manager
    from onnxruntime import GraphOptimizationLevel, InferenceSession, SessionOptions

    def cpu_session(model_path, *, providers):
        options = SessionOptions()
        options.graph_optimization_level = GraphOptimizationLevel.ORT_ENABLE_BASIC
        options.enable_cpu_mem_arena = False
        options.enable_mem_pattern = False
        options.intra_op_num_threads = 1
        return InferenceSession(model_path, sess_options=options, providers=providers)

    inference_manager.InferenceSession = cpu_session
    entrypoint = engine_home / "facefusion.py"
    sys.argv = [str(entrypoint), *map(str, args)]
    runpy.run_path(str(entrypoint), run_name="__main__")


source_is_portrait = source.suffix in image_extensions
# MuseTalk cycles a one-frame video the same way as a photo. Its video path
# also initializes the frame directory it later removes during cleanup.
source_kind = "image" if source_is_portrait and engine != "musetalk" else "video"
source = prepare_media(source, "portrait" if source_is_portrait else "footage", source_kind)
driver = prepare_media(driver, "dialogue" if engine == "musetalk" else "motion",
                       "audio" if engine == "musetalk" else "video")

if engine == "musetalk":
    config = work / "performance.json"
    config.write_text(json.dumps({"take": {
        "video_path": str(source), "audio_path": str(driver), "result_name": output.name
    }}))
    run_musetalk("--version", "v15",
        "--inference_config", config, "--result_dir", work / "results",
        "--unet_model_path", "models/musetalkV15/unet.pth",
        "--unet_config", "models/musetalkV15/musetalk.json", "--batch_size", "1", "--fps", "24")
    shutil.move(work / "results" / "v15" / output.name, output)
elif engine == "liveportrait":
    run(sys.executable, "inference.py", "-s", source, "-d", driver, "-o", work,
        "--flag-force-cpu", "--no-flag-use-half-precision")
    shutil.move(work / f"{source.stem}--{driver.stem}.mp4", output)
elif engine == "facefusion":
    run_facefusion("headless-run", "--source-paths", source,
        "--target-path", driver, "--output-path", output, "--processors", "face_swapper",
        "--face-swapper-model", "ghost_2_256", "--execution-providers", "cpu",
        "--execution-thread-count", "2", "--temp-path", work / "tmp", "--jobs-path", work / "jobs")
else:
    raise ValueError("Unknown performance engine")
