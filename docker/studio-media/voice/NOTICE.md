# Local natural speech runtime

- Kokoro-82M v1.0 model and voice styles: https://huggingface.co/hexgrad/Kokoro-82M — Apache-2.0.
- ONNX quantization and packaged voices: https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1.
- kokoro-onnx Python runtime: https://github.com/thewh1teagle/kokoro-onnx — MIT. Installed package license notices remain in its distribution metadata.
- ONNX Runtime: https://github.com/microsoft/onnxruntime — MIT.
- eSpeak NG phonemization: https://github.com/espeak-ng/espeak-ng — GPL-3.0-or-later. Existing image includes the distribution package and notices.

Model SHA-256: `ae315a79b623f244700e4afb9246c46a26066782e049ba174bf3ba433970ee9c`.
Voice archive SHA-256: `bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d`.

Nevaeh Natural uses a fixed 70% af_heart / 30% af_bella style blend. Nevaeh Warm uses af_bella. These are synthetic stock styles; no reference photograph supplies or clones a voice. Speed is a model pace multiplier (`170` means `1.0`), not an exact word-rate guarantee. Inference is CPU-only and offline; network access is used to assemble the image, never to send reply text to an external TTS service.
