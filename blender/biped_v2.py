"""Reusable grounded foot tracks and source-bound limb posing in local frames."""
import math
import bpy
from mathutils import Vector,Matrix
from bench_v1 import source,smooth,key_pose,key_object
import spatial_frame_v1
import kinematics_v1

def rotation(yaw):return spatial_frame_v1.facing((math.sin(math.radians(yaw)),-math.cos(math.radians(yaw)),0))
class FootTracks:
    def __init__(self,x,y,yaw):
        q=rotation(yaw);self.initial={side:(Vector((x,y,.104))+q @ Vector((sign*.17,0,0)),yaw) for side,sign in (('L',-1),('R',1))};self.steps={'L':[],'R':[]}
    def turn(self,start,end,x,y,yaw):
        q=rotation(yaw)
        for i,(side,sign) in enumerate((('L',-1),('R',1))):
            self.steps[side].append((start+(end-start)*i/2,start+(end-start)*(i+1)/2,Vector((x,y,.104))+q @ Vector((sign*.17,0,0)),yaw))
    def walk(self,start,end,x,distance,y,yaw=90):
        q=rotation(yaw)
        for i in range(8):
            a=start+(end-start)*i/8;b=start+(end-start)*(i+1)/8;side='L' if i%2==0 else 'R';sign=-1 if side=='L' else 1
            target=Vector((x+distance*smooth((i+1)/8),y,.104))+q @ Vector((sign*.17,0,0))
            self.steps[side].append((a,b,target,yaw))
    def at(self,side,t):
        point,yaw=self.initial[side];point=point.copy()
        for start,end,target,angle in self.steps[side]:
            if t>=end:point=target.copy();yaw=angle
            elif t>start:
                r=(t-start)/(end-start);point=point.lerp(target,smooth(r));point.z+=.07*math.sin(math.pi*r)
                return point,yaw+(angle-yaw)*smooth(r),False
            else:break
        return point,yaw,True
class Biped:
    def __init__(self,root,profile):
        self.root=root;self.rig=source(root,profile['rig']);self.body=self.rig.pose.bones.get(profile['body']);self.legs={};self.arms={}
        if not self.body or any(abs(v-1)>.00001 for v in self.rig.matrix_world.to_scale()):raise RuntimeError('Use an unscaled calibrated biped')
        for family,output,part in (('legs',self.legs,'foot'),('arms',self.arms,'hand')):
            for side,binding in profile[family].items():
                upper=self.rig.pose.bones.get(binding['upper']);lower=self.rig.pose.bones.get(binding['lower']);mesh=source(root,binding[part])
                if not upper or not lower or upper.parent!=self.body or lower.parent!=upper or not lower.bone.use_connect or mesh.parent!=self.rig or mesh.parent_bone!=lower.name:raise RuntimeError('Incompatible connected biped limb')
                output[side]=(upper,lower,mesh)
            if set(output)!={'L','R'}:raise RuntimeError('Both biped limbs must be registered')
    def limb(self,upper,lower,target,pole,drop,frame):
        shoulder=upper.bone.head_local+Vector((0,0,drop));local=self.rig.matrix_world.inverted() @ target
        elbow=kinematics_v1.elbow(shoulder,local,upper.bone.length,lower.bone.length,self.rig.matrix_world.inverted().to_3x3() @ pole)
        for bone,a,b in ((upper,shoulder,elbow),(lower,elbow,local)):
            q=bone.bone.matrix_local.to_quaternion();q=(q @ Vector((0,1,0))).rotation_difference((b-a).normalized()) @ q
            bone.matrix=Matrix.LocRotScale(a,q,Vector((1,1,1)));bpy.context.view_layer.update();key_pose(bone,frame)
    def pose(self,frame,position,yaw,drop,feet,hands=None):
        root=self.root;rig=self.rig;q=rotation(yaw);root.location=position;root.rotation_mode='QUATERNION';root.rotation_quaternion=q;key_object(root,frame);bpy.context.view_layer.update()
        matrix=self.body.bone.matrix_local.copy();matrix.translation+=Vector((0,0,drop));self.body.matrix=matrix;key_pose(self.body,frame);bpy.context.view_layer.update()
        for side,(upper,lower,foot) in self.legs.items():
            ankle,angle,_=feet[side];fq=rotation(angle);self.limb(upper,lower,ankle,q @ Vector((0,-1,0)),drop,frame)
            foot.rotation_mode='QUATERNION';foot.matrix_world=Matrix.LocRotScale(ankle-fq @ Vector((0,.09,0)),fq,Vector((1,1,1)));key_object(foot,frame)
        for side,(upper,lower,hand) in self.arms.items():
            sign=-1 if side=='L' else 1;origin=rig.matrix_world @ Vector((sign*.43,-.01,.72+drop));hq=q
            pole=q @ Vector((sign,-1,0))
            if hands and side in hands:
                origin,hq=hands[side][:2]
                if len(hands[side])>2:pole=hands[side][2]
            self.limb(upper,lower,origin+hq @ Vector((0,0,.12)),pole,drop,frame)
            hand.rotation_mode='QUATERNION';hand.matrix_world=Matrix.LocRotScale(origin,hq,Vector((1,1,1)));key_object(hand,frame)
    def errors(self,feet):
        errors=[];ground=[]
        for side,(upper,lower,foot) in self.legs.items():
            ankle=self.rig.matrix_world @ lower.tail;errors.extend([(ankle-feet[side][0]).length,((foot.matrix_world @ Vector((0,.09,0)))-ankle).length])
            if feet[side][2]:ground.append(abs((foot.matrix_world @ Vector((0,.004,-.104))).z))
        for upper,lower,hand in self.arms.values():errors.append(((hand.matrix_world @ Vector((0,0,.12)))-(self.rig.matrix_world @ lower.tail)).length)
        return errors,ground
