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

class ElbowTracker:
 def __init__(self):self.previous=None;self.velocity=0.
 def solve(self,S,W,a,b,axis_target=None,side=-1,front=.001):
  v=W-S;d=np.linalg.norm(v)
  if not abs(a-b)<d<a+b:raise ValueError(('limb_reach',float(d),a+b))
  axis=v/d;along=(a*a-b*b+d*d)/(2*d);h=math.sqrt(max(0,a*a-along*along));base=S+axis*along
  u=np.array([0.,1.,0.]);u-=axis*np.dot(u,axis);u/=np.linalg.norm(u);v=np.cross(axis,u)
  goal=constrained_elbow(S,W,a,b,axis_target,side,front)
  if self.previous is None:self.previous=goal;return goal
  delta=self.previous-base;qprev=math.atan2(np.dot(delta,v),np.dot(delta,u));g=goal-base;qgoal=math.atan2(np.dot(g,v),np.dot(g,u));error=(qgoal-qprev+math.pi)%(2*math.pi)-math.pi
  speed=np.clip(error*(40 if axis_target is not None else 12),-6,6)
  self.velocity=float(np.clip(speed,self.velocity-.16,self.velocity+.16))
  q=qprev+self.velocity*.002
  options=[base+h*(u*math.cos(q)+v*math.sin(q))]
  for dim,offset in [(0,front),(1,side*.001)]:
   A=h*u[dim];B=h*v[dim];rhs=S[dim]+offset-base[dim];r=math.hypot(A,B)
   if r>1e-10 and abs(rhs)<=r:
    z=math.atan2(B,A);w=math.acos(np.clip(rhs/r,-1,1))
    options.extend(base+h*(u*math.cos(z+dq)+v*math.sin(z+dq)) for dq in [-w,w])
  options=[E for E in options if E[0]>=S[0]+front-1e-8 and side*(E[1]-S[1])>=.001-1e-8]
  if not options:raise ValueError('continuous elbow constraints infeasible')
  E=min(options,key=lambda E:np.linalg.norm(E-self.previous))
  if np.linalg.norm(E-self.previous)>.006:raise ValueError(('elbow discontinuity',float(np.linalg.norm(E-self.previous))))
  self.previous=E;return E
