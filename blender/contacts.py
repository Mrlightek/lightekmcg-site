"""Bounded, baked two-bone arm contact with measured palm and wrist residuals."""
import json
import math
import bpy
from mathutils import Vector, Matrix

TOLERANCE=0.002

def smooth(value):
    value=max(0.0,min(1.0,value));return value*value*(3-2*value)

def phase(cue):
    start=cue['start'];hit=start+cue['reach'];leave=hit+cue['hold'];end=leave+cue['release']
    return start,hit,leave,end

def locate(root,name):
    result=next((obj for obj in root.children_recursive if obj.get('lightek_source_object')==name),None)
    if result is None:raise RuntimeError('The bound contact source object is unavailable: '+name)
    return result

def apply(objects,created,settings):
    rows=[item for item in objects if item.get('definition',{}).get('prop_contact')]
    if not rows:return []
    scene=bpy.context.scene;fps=scene.render.fps/scene.render.fps_base
    first,last=scene.frame_start,scene.frame_end;original=scene.frame_current
    if last-first+1>96:raise RuntimeError('Prop contact supports at most 96 frames per scene')
    indexed={str(item['id']):item for item in objects};prepared=[]
    # Group nonoverlapping contacts so repeated presses share one response track.
    responses={}
    for item in rows:
        cue=item['definition']['prop_contact'];key=str(cue['target_object_id'])
        target=created.get(key);target_data=indexed.get(key)
        if target is None or not target_data or target_data['type']!='cube':raise RuntimeError('Choose a static cube contact target')
        if any(target_data.get('definition',{}).get(name) for name in ('animation','story_relation','authoring_commands')):raise RuntimeError('Animated or authored contact props are not supported yet')
        if cue['face']=='front' and target_data['definition'].get('contact_response')=='button_press':
            responses.setdefault(key,[]).append(cue)
    for key,cues in responses.items():
        target=created[key];base=target.location.copy()
        intervals=sorted((phase(cue)[1],phase(cue)[2]) for cue in cues)
        if any(a[1]>b[0] for a,b in zip(intervals,intervals[1:])):raise RuntimeError('Overlapping activation-button holds are not supported')
        normal=(target.rotation_euler.to_quaternion() @ Vector((0,-1,0))).normalized()
        for frame in range(first,last+1):
            t=(frame-1)/fps
            amount=sum(math.sin(math.pi*(t-hit)/(leave-hit))**2*.015 for hit,leave in intervals if hit<=t<=leave)
            target.location=base-normal*amount
            target.keyframe_insert(data_path='location',frame=frame,group='Lightek button press')
    prepared=[];reports=[]
    for item in rows:
        root=created[str(item['id'])];definition=item['definition'];cue=definition['prop_contact']
        binding=definition['character_profile'].get('reach_bindings',{}).get(cue['hand'])
        if not binding:raise RuntimeError('This character has no registered contact hand')
        rig=locate(root,binding['rig']);hand=locate(root,binding['hand'])
        upper=rig.pose.bones.get(binding['upper']);lower=rig.pose.bones.get(binding['forearm'])
        if rig.type!='ARMATURE' or not upper or not lower or lower.parent!=upper or not lower.bone.use_connect:raise RuntimeError('Contact needs a connected two-bone arm')
        if hand.parent!=rig or hand.parent_type!='BONE' or hand.parent_bone!=lower.name:raise RuntimeError('The registered hand must belong to its forearm bone')
        target=created[str(cue['target_object_id'])];point=Vector(cue['point'])
        normal_local=point.normalized();face_q=Vector((0,-1,0)).rotation_difference(normal_local)
        contact_anchor=Vector(binding['contact_anchor']);wrist_anchor=Vector(binding['wrist_anchor'])
        a,b=upper.bone.length,lower.bone.length
        start,hit,leave,end=phase(cue)
        if not all(math.isfinite(v) for v in (start,hit,leave,end)) or start<0 or not(start<hit<leave<end<=last/fps+0.001):raise RuntimeError('Contact timing exceeds this rendered scene')
        baseline=[]
        for frame in range(first,last+1):
            scene.frame_set(frame);bpy.context.view_layer.update()
            scale=rig.matrix_world.to_scale()
            if min(scale)<=0 or max(scale)-min(scale)>0.0001:raise RuntimeError('Contact needs a uniformly scaled character rig')
            if (hand.matrix_world @ wrist_anchor-rig.matrix_world @ lower.tail).length>TOLERANCE:raise RuntimeError('The hand wrist anchor is not bound to the forearm tip')
            for bone in (upper,lower):
                if any(abs(v-1)>0.0001 for v in bone.matrix.to_scale()):raise RuntimeError('Stretched arm bones cannot be used for contact')
            baseline.append((upper.matrix.copy(),lower.matrix.copy(),rig.matrix_world.copy(),hand.matrix_world.copy(),target.matrix_world.copy()))
        upper.rotation_mode='QUATERNION';lower.rotation_mode='QUATERNION';hand.rotation_mode='QUATERNION'
        marker=bpy.data.objects.new('Contact '+str(item['id'])+' '+cue['hand'],None);scene.collection.objects.link(marker)
        marker.parent=target;marker.location=point;marker.rotation_mode='QUATERNION';marker.rotation_quaternion=face_q
        marker['lightek_contact_actor']=str(item['id']);marker['lightek_contact_hand']=cue['hand']
        for offset,frame in enumerate(range(first,last+1)):
            scene.frame_set(frame)
            u0,l0,rig_world,h0,target_world=baseline[offset];t=(frame-1)/fps
            palm0=h0 @ contact_anchor;contact=target_world @ point
            face_world=target_world.to_quaternion() @ face_q;normal=(target_world.to_quaternion() @ normal_local).normalized()
            approach=contact+normal*.08
            lift=palm0+normal*(approach-palm0).dot(normal)
            lift.z=approach.z
            if t<start or t>end:
                palm=palm0;turn=0
            elif t<hit:
                r=(t-start)/(hit-start)
                if r<.35:palm=palm0.lerp(lift,smooth(r/.35))
                elif r<.75:palm=lift.lerp(approach,smooth((r-.35)/.4))
                else:palm=approach.lerp(contact,smooth((r-.75)/.25))
                turn=smooth(r/.35)
            elif t<=leave:palm=contact;turn=1
            else:
                r=(t-leave)/(end-leave)
                if r<.25:palm=contact.lerp(approach,smooth(r/.25))
                elif r<.65:palm=approach.lerp(lift,smooth((r-.25)/.4))
                else:palm=lift.lerp(palm0,smooth((r-.65)/.35))
                turn=1-smooth((r-.65)/.35)
            hand_q=h0.to_quaternion().slerp(face_world,turn)
            hand_scale=h0.to_scale();anchor_scaled=Vector([contact_anchor[i]*hand_scale[i] for i in range(3)]);wrist_scaled=Vector([wrist_anchor[i]*hand_scale[i] for i in range(3)])
            hand_origin=palm-hand_q @ anchor_scaled
            wrist_world=hand_origin+hand_q @ wrist_scaled
            local=rig_world.inverted() @ wrist_world;shoulder=u0.translation
            if start<=t<=end:
                delta=local-shoulder;d=delta.length
                if not(abs(a-b)+.001<d<a+b-.001):raise RuntimeError('Contact target or approach is outside the natural arm reach at frame '+str(frame))
                axis=delta/d;reference=rig_world.inverted().to_3x3() @ normal
                bend=reference-axis*reference.dot(axis)
                if bend.length<.0001:bend=Vector((0,0,-1))-axis*axis.dot(Vector((0,0,-1)))
                if bend.length<.0001:bend=Vector((1,0,0))-axis*axis.x
                along=(a*a-b*b+d*d)/(2*d);height=math.sqrt(max(0,a*a-along*along))
                elbow=shoulder+axis*along+bend.normalized()*height
                q1=(u0.to_quaternion() @ Vector((0,1,0))).rotation_difference((elbow-shoulder).normalized()) @ u0.to_quaternion()
                q2=(l0.to_quaternion() @ Vector((0,1,0))).rotation_difference((local-elbow).normalized()) @ l0.to_quaternion()
                upper.matrix=Matrix.LocRotScale(shoulder,q1,Vector((1,1,1)));bpy.context.view_layer.update()
                lower.matrix=Matrix.LocRotScale(elbow,q2,Vector((1,1,1)));bpy.context.view_layer.update()
            else:
                upper.matrix=u0;bpy.context.view_layer.update();lower.matrix=l0;bpy.context.view_layer.update()
            if (rig.matrix_world @ lower.tail-wrist_world).length>TOLERANCE:raise RuntimeError('The baked arm missed its wrist target')
            hand.matrix_world=Matrix.LocRotScale(hand_origin,hand_q,hand_scale)
            for bone in (upper,lower):
                bone.keyframe_insert(data_path='rotation_quaternion',frame=frame,group='Lightek prop contact')
                bone.keyframe_insert(data_path='location',frame=frame,group='Lightek prop contact')
            for path in ('location','rotation_quaternion','scale'):hand.keyframe_insert(data_path=path,frame=frame,group='Lightek palm orientation')
        errors=[];wrist_errors=[]
        for frame in range(first,last+1):
            scene.frame_set(frame);bpy.context.view_layer.update();t=(frame-1)/fps
            if hit-0.00001<=t<=leave+0.00001:
                errors.append((hand.matrix_world @ contact_anchor-target.matrix_world @ point).length)
                wrist_errors.append((hand.matrix_world @ wrist_anchor-rig.matrix_world @ lower.tail).length)
        if not errors or max(errors)>TOLERANCE or max(wrist_errors)>TOLERANCE:raise RuntimeError('Rendered palm contact did not meet the 2 mm tolerance')
        prepared.append({'actor_id':str(item['id']),'target_id':str(cue['target_object_id']),'hand':hand,'first':1+round(start*fps),'last':1+round(end*fps),'point':point,'normal':normal_local})
        reports.append({'actor_id':item['id'],'target_id':cue['target_object_id'],'hand':cue['hand'],'measured_frames':len(errors),'max_contact_error':max(errors),'max_wrist_error':max(wrist_errors),'tolerance':TOLERANCE})
    scene['lightek_contact_report']=json.dumps(reports);scene.frame_set(original);bpy.context.view_layer.update()
    return prepared
