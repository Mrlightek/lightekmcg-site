"""Shared geometric limb model. No stretch, mass dynamics or hidden constraints."""
import math

def elbow(shoulder,target,upper,lower,pole):
    delta=target-shoulder;distance=delta.length
    if distance<abs(upper-lower)+.00001 or distance>upper+lower+.00001:
        raise RuntimeError('The limb target is outside its calibrated reach')
    axis=delta/distance;bend=pole-axis*pole.dot(axis)
    if bend.length<.00001:raise RuntimeError('The limb bend direction is degenerate')
    along=(upper*upper-lower*lower+distance*distance)/(2*distance)
    height=math.sqrt(max(0,upper*upper-along*along))
    return shoulder+axis*along+bend.normalized()*height
