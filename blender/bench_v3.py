"""Twenty-second bench performance for script previews."""
import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Vector

import views_v1
from bench_v1 import smooth, source
from bench_v2 import BenchV2
from biped_v2 import Biped, FootTracks, rotation


class BenchV3:
    phases = {
        "walk": [0, 4], "turn": [4, 5], "sit": [5, 6.5],
        "seated": [6.5, 16.8], "stand": [16.8, 18.5], "rest": [18.5, 20],
    }
    files = ('bench_v3.py', *BenchV2.files)

    @classmethod
    def fingerprint(cls):
        directory = Path(__file__).parent
        return hashlib.sha256(b''.join((directory / name).read_bytes() for name in cls.files)).hexdigest()

    def bake(self, item, root, target):
        scene = bpy.context.scene
        definition = item['definition']
        plan = definition['mechanics_plan']
        profile = definition['character_profile']
        if (plan.get('driver_fingerprint') != self.fingerprint()
                or plan.get('source_blob_id') != profile.get('source_blob_id')
                or plan.get('phases') != self.phases):
            raise RuntimeError('The pinned mechanics implementation changed; prepare a reviewed new performance')
        if (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base) != (1, 240, 12, 1):
            raise RuntimeError('Bench v3 needs twenty seconds at 12 fps')
        if ((target.location - Vector((0, .27, .40))).length > .00001
                or (target.scale - Vector((.8, .19, .04))).length > .00001
                or any(abs(value) > .00001 for value in target.rotation_euler)):
            raise RuntimeError('Use the calibrated static bench')

        actor = Biped(root, profile['mechanics'])
        support = source(root, profile['mechanics']['support'])
        tracks = FootTracks(-.8, -.24, 90)
        tracks.walk(0, 2, -.8, .8, -.24)
        tracks.turn(2, 2.5, 0, -.24, 0)
        samples = []
        angles = []
        for frame in range(1, 241):
            scene.frame_set(frame)
            seconds = (frame - 1) / 12
            # Sample the calibrated movement at half speed and lengthen its seated hold.
            time = (seconds - min(4, max(0, seconds - 12.8))) / 2
            seated = smooth((time - 2.5) / .75) * (1 - smooth((time - 6.4) / .85))
            drop = (-.05 * (1 - seated) - .2568 * seated) * (1 - smooth((time - 7.25) / .75))
            yaw = 90 * (1 - smooth((time - 2) / .5))
            position = Vector((-.8 + .8 * smooth(time / 2), -.24 + .46 * seated, 0))
            feet = {side: tracks.at(side, time) for side in ('L', 'R')}
            facing = rotation(yaw)
            hands = {}
            for side, sign in (('L', -1), ('R', 1)):
                rest = position + facing @ Vector((sign * .43, -.01, .72 + drop))
                hands[side] = (rest.lerp(Vector((sign * .30, -.10, .68)), seated), facing)
            actor.pose(frame, position, yaw, drop, feet, hands)
            samples.append((frame, feet, 3.25 <= time <= 6.4))
            angles.append((frame, yaw))

        views_v1.bake(root, profile, angles)
        limb_errors, ground_errors, seat_errors = [], [], []
        seated_frames = []
        for frame, feet, seated in samples:
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            limbs, ground = actor.errors(feet)
            limb_errors.extend(limbs)
            ground_errors.extend(ground)
            if seated:
                seat_top = target.matrix_world @ Vector((0, 0, 1))
                pelvis_bottom = support.matrix_world @ Vector((0, .004, -.0832))
                seat_errors.append(abs(pelvis_bottom.z - seat_top.z))
                seated_frames.append(frame)
        if max(limb_errors + ground_errors + seat_errors) > .002:
            raise RuntimeError('Direction-aware biped support failed its tolerance')
        root['lightek_mechanics_report'] = json.dumps({
            'driver': 'bench', 'version': 3, 'frames': 240,
            'max_limb_error': max(limb_errors), 'max_seat_error': max(seat_errors),
            'max_ground_error': max(ground_errors), 'support_frames': len(seated_frames),
            'walk_yaw': 90, 'seat_yaw': 0,
        })
        return {
            'actor_id': str(item['id']), 'target_id': str(plan['target_object_id']),
            'contact_mesh': support, 'first': seated_frames[0], 'last': seated_frames[-1],
            'point': Vector((0, 0, 1)), 'normal': Vector((0, 0, 1)),
        }
