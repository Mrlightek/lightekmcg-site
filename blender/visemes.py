"""Frame-sampled Rhubarb mouth cues; no scene or Blender dependency."""
import math

FALLBACK = {
    'A': (0, 0, 0), 'B': (.15, .4, 0), 'C': (.45, .35, 0),
    'D': (1, .1, 0), 'E': (.35, 0, .6), 'F': (.2, 0, 1),
    'G': (.1, .3, 0), 'H': (.25, .65, 0), 'X': (0, 0, 0),
}


def curves(cues, *, duration, start, fps, bindings):
    controls = [name for name in bindings if name in ('jaw_open', 'mouth_wide', 'mouth_round') or name.startswith('viseme_')]
    result = {name: {max(0, start-1/fps): 0} for name in controls}
    index = 0
    for frame in range(math.ceil(duration*fps)+1):
        time = min(frame/fps, duration)
        while index < len(cues) and time >= cues[index]['end']:
            index += 1
        shape = cues[index]['value'] if index < len(cues) and cues[index]['start'] <= time < cues[index]['end'] and time < duration else 'X'
        exact = 'viseme_' + shape.lower()
        # Exact shapes replace the coarse jaw/wide/round approximation.
        values = dict(zip(('jaw_open', 'mouth_wide', 'mouth_round'), (0, 0, 0) if exact in bindings else FALLBACK[shape]))
        if exact in bindings and time < duration: values[exact] = 1
        for control in controls:
            result[control][start+time] = values.get(control, 0)
    return result
