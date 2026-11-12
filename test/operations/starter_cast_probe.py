"""Inspect the saved native file after temporary character sources are gone."""
import bpy
import json
rigs = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE' and o.name.startswith('RIG-')]
result = {'rigs': len(rigs), 'drivers': [], 'moving_heads': [], 'keys': []}
for rig in rigs:
    result['drivers'].append(len(rig.animation_data.drivers) if rig.animation_data else 0)
    result['keys'].append(bool(rig.animation_data and rig.animation_data.action))
    bone = rig.pose.bones['FK-Head']
    bpy.context.scene.frame_set(1)
    first = bone.matrix.copy()
    bpy.context.scene.frame_set(12)
    second = bone.matrix.copy()
    result['moving_heads'].append(sum(abs(first[i][j] - second[i][j]) for i in range(4) for j in range(4)) > .001)
print('STARTER_CAST_PROOF=' + json.dumps(result))
