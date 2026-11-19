import numpy as np,math

def constrained_elbow(S,W,a,b,axis_target=None,side=-1,front=.001):
 v=W-S;d=np.linalg.norm(v)
 if not abs(a-b)<d<a+b:raise ValueError(('limb_reach',float(d),a+b))
 axis=v/d;along=(a*a-b*b+d*d)/(2*d);h=math.sqrt(max(0,a*a-along*along));base=S+axis*along
 u=np.array([0.,1.,0.]);u-=axis*np.dot(u,axis);u/=np.linalg.norm(u);v=np.cross(axis,u)
 pole=np.array([0.,side*.3,-1.]) if axis_target is None else -axis_target
 q=math.atan2(np.dot(pole,v),np.dot(pole,u));angles=[q]
 for dim,offset in [(0,front),(1,side*.001)]:
  A=h*u[dim];B=h*v[dim];rhs=S[dim]+offset-base[dim];r=math.hypot(A,B)
  if r>1e-10 and abs(rhs)<=r:
   z=math.atan2(B,A);w=math.acos(np.clip(rhs/r,-1,1));angles.extend([z-w,z+w])
 options=[base+h*(u*math.cos(t)+v*math.sin(t)) for t in angles]
 options=[E for E in options if E[0]>=S[0]+front-1e-8 and side*(E[1]-S[1])>=.001-1e-8]
 if not options:raise ValueError('front/outward elbow constraints infeasible')
 return min(options,key=lambda E:E[2]-.2*side*E[1] if axis_target is None else np.dot(E,axis_target))
