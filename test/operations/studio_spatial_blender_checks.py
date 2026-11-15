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
clean()
import performance
import tempfile
import wave
import struct
face=cube('Face',(0,0,0));face.shape_key_add(name='Basis');jaw=face.shape_key_add(name='Open');jaw.data[0].co.z+=0.2
profile={'bindings':{'jaw_open':{'object':'Face','key':'Open'}},'bones':{}}
with tempfile.TemporaryDirectory() as directory:
    path=str(Path(directory)/'line.wav')
    with wave.open(path,'wb') as file:
        file.setnchannels(1);file.setsampwidth(2);file.setframerate(8000);file.writeframes(struct.pack('<h',1200)*8000)
    takes=[{'take_id':'take_'+str(index),'start':start,'duration':1,'source_in':0,'gain':1,'mouth_frames':[{'time':0,'value':0},{'time':0.2,'value':1},{'time':0.8,'value':0}],'expressions':[],'gestures':[],'audio_path':path} for index,start in enumerate((0,2))]
    bpy.context.scene.render.fps=24;bpy.context.scene.frame_end=72
    performance.apply_sequence(face,{'Face':face},{'character_profile':profile,'performance_takes':takes,'performance_instance':'same_actor'})
    editor=bpy.context.scene.sequence_editor
    strips=editor.strips if hasattr(editor,'strips') else editor.sequences
    assert len(strips)==2,'Both dialogue recordings must remain in the scene'
    bpy.context.scene.frame_set(6);assert face.data.shape_keys.key_blocks['Open'].value>0.8
    bpy.context.scene.frame_set(36);assert face.data.shape_keys.key_blocks['Open'].value<0.01
    bpy.context.scene.frame_set(54);assert face.data.shape_keys.key_blocks['Open'].value>0.8
print('PASS: sequential mouth animation and both audio takes remain on one character')
clean()
a=cube('Amina',(-2,0,1));b=cube('Bilal',(2,0,1));c=cube('Chloe',(-2,4,1))
bpy.context.scene.render.fps=24;bpy.context.scene.frame_end=48
objects=[{'id':1,'name':'Amina','definition':{'story_relation':{'look_at':2,'facing_axis':'-Y'},'director_gaze_cues':[{'start':1,'end':2,'look_at':3}]}},{'id':2,'name':'Bilal','definition':{}},{'id':3,'name':'Chloe','definition':{}}]
relationships.apply(objects,{'1':a,'2':b,'3':c})
bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
first=a.constraints['Lightek story focus'].target.matrix_world.translation.copy()
bpy.context.scene.frame_set(30);bpy.context.view_layer.update()
second=a.constraints['Lightek story focus'].target.matrix_world.translation.copy()
assert (first-b.location).length<0.01 and (second-c.location).length<0.01
print('PASS: timed dialogue attention changes to the actual next character')
print('STUDIO_SPATIAL_CHECKS_PASSED')
