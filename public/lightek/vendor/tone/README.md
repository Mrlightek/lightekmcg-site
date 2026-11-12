# Vendored music dependencies

- Tone.js **15.1.22**, npm `tone@15.1.22`, upstream https://github.com/Tonejs/Tone.js — MIT. `Tone-15.1.22.js` is its published `build/Tone.js` distribution, with the package license and bundled third-party notices retained.
- @tonejs/midi **2.0.28**, npm `@tonejs/midi@2.0.28`, upstream https://github.com/Tonejs/Midi — MIT. `Midi-2.0.28.js` is its published `build/Midi.js` distribution. The included array-flatten and midi-file dependencies' license notices are retained too.

These files are served by Lightek. The editor does not fetch executable code or instrument banks from a CDN. Built-in instruments are synthesized locally; imported audio samples belong to the user's production library. No AI voice or face model is included.

Reproduce by installing the exact npm versions into a temporary directory and copying the build distributions and license files. Maps are not required at runtime.
