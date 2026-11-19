"""Right-handed local surface frames, transformed into shared scene coordinates."""
from mathutils import Vector, Matrix

def frame(origin,normal,forward):
    up=Vector(normal).normalized();tangent=Vector(forward);tangent-=up*tangent.dot(up)
    if tangent.length<.00001:raise RuntimeError('Surface forward must not be parallel to its normal')
    tangent.normalize();right=tangent.cross(up).normalized()
    rotation=Matrix((right,tangent,up)).transposed().to_4x4();rotation.translation=Vector(origin)
    return rotation

def facing(forward,up=(0,0,1)):
    # The source character looks along local -Y, with local +Z upright.
    return frame((0,0,0),up,Vector(forward)*-1).to_quaternion()
