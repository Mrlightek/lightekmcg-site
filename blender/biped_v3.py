"""Anatomically bounded arm IK for the contact-hand study; v2 stays immutable."""
import math
from mathutils import Vector
from biped_v2 import Biped as BipedV2

class Biped(BipedV2):
    def __init__(self,root,profile,physics):
        super().__init__(root,profile)
        self.physics=physics;self.elbow_angles=[]
    def limb(self,upper,lower,target,pole,drop,frame):
        if upper.name.startswith('Arm.'):
            shoulder=self.rig.matrix_world @ (upper.bone.head_local+Vector((0,0,drop)))
            distance=(target-shoulder).length
            a,b=upper.bone.length,lower.bone.length
            cosine=max(-1,min(1,(a*a+b*b-distance*distance)/(2*a*b)))
            flexion=180-math.degrees(math.acos(cosine))
            lo,hi=self.physics['elbow_flexion_deg']
            if not lo<=flexion<=hi:
                raise RuntimeError('Reach violates the calibrated elbow flexion limit: '+str(flexion))
            self.elbow_angles.append(flexion)
            # Elbow below the shoulder/wrist line, not an upward chicken-wing pole.
            pole=Vector((0,0,-1))
        return super().limb(upper,lower,target,pole,drop,frame)
