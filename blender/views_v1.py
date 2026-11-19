"""Rig-bound profile drawings follow actor facing; no physics is hidden or disabled."""
import bpy

def bake(root,profile,angles):
    contract=profile.get('views')
    if not contract or contract.get('version')!=1:raise RuntimeError('Build a performer with registered front/side views')
    objects={obj.get('lightek_source_object'):obj for obj in root.children_recursive}
    for frame,angle in angles:
        bpy.context.scene.frame_set(frame);side=abs(angle)>45
        for view in ('front','side'):
            for name in contract[view]:
                obj=objects.get(name)
                if obj is None:raise RuntimeError('A registered character view is missing')
                visible=side==(view=='side');obj.hide_render=not visible;obj.hide_viewport=not visible if view=='side' else False
                obj.keyframe_insert(data_path='hide_render',frame=frame);obj.keyframe_insert(data_path='hide_viewport',frame=frame)
                source=objects.get(obj.get('lightek_mirror_source'))
                if source and obj.data.shape_keys and source.data.shape_keys:
                    for key in obj.data.shape_keys.key_blocks:
                        if key.name!='Basis' and key.name in source.data.shape_keys.key_blocks:
                            key.value=source.data.shape_keys.key_blocks[key.name].value
                            key.keyframe_insert(data_path='value',frame=frame)
