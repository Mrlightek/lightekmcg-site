"""Body-relative front reach and elbow plane, preserving earlier calibrated drivers."""
import math
from mathutils import Vector
from biped_v2 import Biped as BipedV2
from biped_v3 import Biped as BipedV3

class Biped(BipedV3):
    def __init__(self,root,profile,physics):
        super().__init__(root,profile,physics);self.front_margins=[]
    def limb(self,upper,lower,target,pole,drop,frame):
        if not upper.name.startswith('Arm.'):
            return BipedV2.limb(self,upper,lower,target,pole,drop,frame)
        shoulder=self.rig.matrix_world @ (upper.bone.head_local+Vector((0,0,drop)))
        front=self.root.matrix_world.to_quaternion() @ Vector((0,-1,0))
        distance=(target-shoulder).length;a,b=upper.bone.length,lower.bone.length
        if not abs(a-b)+1e-5 <= distance <= a+b:raise RuntimeError('The arm target is outside its calibrated reach')
        cosine=max(-1,min(1,(a*a+b*b-distance*distance)/(2*a*b)))
        flexion=180-math.degrees(math.acos(cosine));lo,hi=self.physics['elbow_flexion_deg']
        if not lo<=flexion<=hi:raise RuntimeError('Reach violates the calibrated elbow flexion limit')
        if (target-shoulder).dot(front)<-.002:raise RuntimeError('Turn toward the object before reaching behind the shoulder')
        side=-1 if upper.name.endswith('.L') else 1
        pole=self.root.matrix_world.to_quaternion() @ Vector((side*.4,-1,-.2))
        BipedV2.limb(self,upper,lower,target,pole,drop,frame)
        elbow=self.rig.matrix_world @ lower.head
        margin=min((target-shoulder).dot(front),(elbow-shoulder).dot(front))
        if margin<-.002:raise RuntimeError('The elbow crossed behind its shoulder plane')
        self.front_margins.append(margin);self.elbow_angles.append(flexion)
