# Studio specialist limits and recovery

Nevaeh checks Studio parameters before Dispatch queues a request. The worker checks the submitted render inputs again. Studio presets control dimensions and memory. A request cannot supply its own ComfyUI graph or override a worker’s memory allocation.

| Worker | Admission and output limits |
| --- | --- |
| Genesis Economy | SD 1.5 uses up to 512 pixels on the long edge. Wan 2.2 uses up to 512×288. CUDA admission requires 8 GiB total and 4 GiB currently free. CPU can run SD 1.5 Economy. |
| Genesis Quality | SD 1.5 uses up to 768 pixels on the long edge. Wan 2.2 uses up to 1280×704. CUDA admission requires 16 GiB total and 10 GiB currently free. |
| Both Genesis profiles | One image or clip per request. Wan permits up to 121 frames. Sampling is limited to 60 steps. Auto selects a profile from worker telemetry. The worker rechecks memory before submitting to ComfyUI. |
| Blender Cycles CPU Economy | 512 pixels on the long edge and up to 8 samples. One thread and a 1 GiB container for production rendering. Up to 2,400 frames per animated shot and up to two hours for a final render. A 90-second renewable lease guards worker ownership. |
| FFmpeg timeline export | 4,096 pixels per side, 64 clips and 10 minutes per edit. Production uses a 2 GiB container and a 15-minute export limit. |
| Rhubarb lip sync | 0.1–30 seconds of source dialogue. One recognition thread, 2 GiB production container and up to three minutes for recognition. |
| MuseTalk, LivePortrait and FaceFusion | Dedicated CPU performance workers use a separate 12 GiB container and a 30-minute execution limit. Audio and video inputs are capped at 15 seconds and 50 MB each. |

The CUDA thresholds are admission rules. If a generation reports insufficient memory, Activity can offer **Retry in Economy**. This queues a smaller job with no more than 20 steps. If Economy also runs out of memory, free GPU memory or choose another configured worker. A failed paid CPU render can resume from its last valid checkpoint and rebuild missing or invalid frames.

Nevaeh reads the relevant local Studio guide when answering common questions and includes the specialist’s limits in dispatch context. Verified generation results can be saved as Task Builder phrases by authorized users. The shortcut retains the effective quality profile, seed and registered worker selection when available.
