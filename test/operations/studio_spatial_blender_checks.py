"""Run with blender --background --factory-startup --python this_file."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'blender'))
import bpy
from mathutils import Vector
import relationships
import spatial_checks

def clean():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene
    scene.frame_start=1;scene.frame_end=3;scene.frame_set(1)

def cube(name,location,size=(0.25,0.25,0.8)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location)
    obj=bpy.context.object;obj.name=name;obj.scale=size
    return obj

def check_error(callback,expected):
    try:
        callback()
    except RuntimeError as error:
        assert expected.lower() in str(error).lower(),str(error)
    else:
        raise AssertionError('Expected '+expected)

clean()
a=cube('Amina',(-1,0,1));b=cube('Bilal',(1,0,1))
a.keyframe_insert(data_path='location',frame=1);a.location.x=-0.5;a.keyframe_insert(data_path='location',frame=3)
bpy.ops.object.camera_add();camera=bpy.context.object
objects=[{'id':1,'name':'Amina','type':'imported_asset','definition':{'director_speaker':'Amina','story_relation':{'look_at':2,'look_at_offset':[0,0,0],'facing_axis':'-Y'}}}, {'id':2,'name':'Bilal','type':'imported_asset','definition':{'director_speaker':'Bilal','story_relation':{'look_at':1,'look_at_offset':[0,0,0],'facing_axis':'-Y'}}}, {'id':3,'name':'Camera','type':'camera','definition':{'story_relation':{'relative_to':1,'offset':[0,-5,1],'look_at':2,'look_at_offset':[0,0,0.5],'depth_of_field':True,'aperture_fstop':4}}}]
created={'1':a,'2':b,'3':camera}
relationships.apply(objects,created)
assert camera.data.type=='PERSP' and camera.data.dof.use_dof and camera.data.dof.focus_object
for frame in (1,2,3):
    bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
    for obj,target in ((a,b),(b,a)):
        facing=obj.matrix_world.to_quaternion() @ Vector((0,-1,0))
        direction=(target.matrix_world.translation-obj.matrix_world.translation).normalized()
        assert facing.dot(direction)>0.99,(frame,obj.name,facing,direction)
    expected=a.matrix_world @ Vector((0,-5,1))
    assert (camera.matrix_world.translation-expected).length<0.001
spatial_checks.validate(objects,created,{'spatial_direction':{'personal_space':0.9,'collision_detection':True}})
print('PASS: reciprocal speaker facing, animated relative camera, perspective and focal depth')
clean();a=cube('Amina',(0,0,1));b=cube('Bilal',(0.7,0,1))
objects=[{'id':1,'name':'Amina','type':'imported_asset','definition':{'director_speaker':'Amina'}},{'id':2,'name':'Bilal','type':'imported_asset','definition':{'director_speaker':'Bilal'}}];created={'1':a,'2':b}
check_error(lambda:spatial_checks.validate(objects,created,{'spatial_direction':{'personal_space':0.9}}),'personal-space')
for item in objects:item['definition']['story_relation']={'allow_close_contact':True}
spatial_checks.validate(objects,created,{'spatial_direction':{'personal_space':0.9}})
print('PASS: personal space and explicit close-contact override')
b.location.x=0.1
check_error(lambda:spatial_checks.validate(objects,created,{'spatial_direction':{'personal_space':0}}),'collision')
print('PASS: character collision')
clean();a=cube('Amina',(0,0,1));wall=cube('Wall',(0,0,1),(1,1,2))
objects=[{'id':1,'name':'Amina','type':'imported_asset','definition':{'director_speaker':'Amina'}},{'id':2,'name':'Wall','type':'cube','definition':{}}];created={'1':a,'2':wall}
check_error(lambda:spatial_checks.validate(objects,created,{'spatial_direction':{'personal_space':0,'collision_detection':True}}),'environment collision')
print('PASS: enclosing environment collision')
clean()
root=bpy.data.objects.new('Amina',None);bpy.context.scene.collection.objects.link(root);root.location=(-1,0,0)
body=cube('Body',(0,0,1));body.parent=root
armature=bpy.data.armatures.new('Head rig');rig=bpy.data.objects.new('Rig',armature);bpy.context.scene.collection.objects.link(rig);rig.parent=root;rig['lightek_source_object']='Rig'
bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT');head=armature.edit_bones.new('Head');head.head=(0,0,1.4);head.tail=(0,0,1.7);bpy.ops.object.mode_set(mode='OBJECT')
target=bpy.data.objects.new('Bilal target',None);bpy.context.scene.collection.objects.link(target);target.location=(1,0,0)
objects=[{'id':1,'name':'Amina','type':'imported_asset','definition':{'director_speaker':'Amina','character_profile':{'bones':{'head':{'object':'Rig','bone':'Head'}}},'story_relation':{'look_at':2,'look_at_offset':[0,0,1.4],'facing_axis':'-Y'}}},{'id':2,'name':'Bilal target','type':'empty','definition':{}}]
created={'1':root,'2':target}
relationships.apply(objects,created)
spatial_checks.validate(objects,created,{})
rig.pose.bones['Head'].rotation_mode='XYZ';rig.pose.bones['Head'].rotation_euler.y=1.57079632679
check_error(lambda:spatial_checks.validate(objects,created,{}),'eyeline')
print('PASS: bound head eyeline mismatch stops the shot')
print('STUDIO_SPATIAL_CHECKS_PASSED')
