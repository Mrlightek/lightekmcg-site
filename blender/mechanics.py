"""Action-driver registry. New versions keep older calibrated implementations intact."""
import bpy
from bench_v1 import BenchV1
from bench_v2 import BenchV2
from carry_v1 import CarryV1
from grasp_v1 import GraspV1
from grasp_v2 import GraspV2
from grasp_v3 import GraspV3
from grasp_v4 import GraspV4

DRIVERS={('bench',1):BenchV1,('bench',2):BenchV2,('carry',1):CarryV1,('grasp',1):GraspV1,('grasp',2):GraspV2,('grasp',3):GraspV3,('grasp',4):GraspV4}
def apply(objects,created,settings):
    contacts=[];original=bpy.context.scene.frame_current
    indexed={str(item['id']):item for item in objects}
    for item in objects:
        plan=item.get('definition',{}).get('mechanics_plan')
        if not plan:continue
        driver=DRIVERS.get((plan.get('driver'),plan.get('version')))
        target=created.get(str(plan.get('target_object_id')));target_data=indexed.get(str(plan.get('target_object_id')))
        if not driver or target is None or not target_data or target_data['type']!=getattr(driver,'target_type','cube') or target_data['definition'].get(getattr(driver,'target_tag','mechanics_seat'))!=1 or any(target_data['definition'].get(key) for key in ('animation','story_relation','authoring_commands')):
            raise RuntimeError('The versioned mechanics driver or static seat is unavailable')
        instance=driver(objects,created) if getattr(driver,'requires_world',False) else driver()
        result=instance.bake(item,created[str(item['id'])],target)
        contacts.extend(result if isinstance(result,list) else [result])
    bpy.context.scene.frame_set(original);bpy.context.view_layer.update();return contacts
