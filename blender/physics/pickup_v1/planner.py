import numpy as np,math
from scipy.interpolate import PchipInterpolator,BSpline
from scipy.optimize import minimize
from ik_untracked import constrained_elbow

def geometry(S,C,a,b,angles):
 axis=C-S;dist=np.linalg.norm(axis);axis/=dist;along=(a*a-b*b+dist*dist)/(2*dist);h=math.sqrt(max(0,a*a-along*along));base=S+axis*along
 u=np.array([0.,1.,0.]);u-=axis*np.dot(u,axis);u/=np.linalg.norm(u);v=np.cross(axis,u)
 Es=base+ h*(np.cos(angles)[:,None]*u+np.sin(angles)[:,None]*v)
 return Es,base,u,v,h

def handR(C,E,b):
 v=(C-E)/b;n=np.array([-.5,0.,-1.]);n-=v*np.dot(n,v);n/=np.linalg.norm(n);alpha=math.atan2(.065,.315)
 d=math.cos(alpha)*v-math.sin(alpha)*n;n=math.sin(alpha)*v+math.cos(alpha)*n
 return np.column_stack([d,n,np.cross(d,n)])
class Plan:
 def __init__(self,t0,t1,Cfun,Sfun,a,b,start_locked=False,end_locked=False,start_elbow=None):
  self.a=a;self.b=b;self.Sfun=Sfun;self.Cfun=Cfun;times=np.linspace(t0,t1,max(2,int(math.ceil((t1-t0)/.02))+1));grid=np.arange(256)*2*math.pi/256
  sets=[];thetas=[];Rs=[];valids=[]
  for t in times:
   S=Sfun(t);C=Cfun(t);_,base,u,v,h=geometry(S,C,a,b,np.array([0.]))
   goal=np.array(start_elbow) if start_elbow is not None and t==times[0] else constrained_elbow(S,C,a,b,front=.008);g=goal-base;q=math.atan2(np.dot(g,v),np.dot(g,u));qs=np.r_[grid,q]
   E,*_=geometry(S,C,a,b,qs);valid=(E[:,0]>=S[0]+.008-1e-8)&(E[:,1]<=S[1]-.006+1e-8)
   if t==times[0] and not start_locked:valid&=(E[:,2]<=S[2]-.30*math.cos(math.radians(25)))
   if t==times[-1] and not end_locked:valid&=(E[:,2]<=S[2]-.30*math.cos(math.radians(25)))
   sets.append(E);thetas.append(qs);Rs.append(np.array([handR(C,e,b) for e in E]));valids.append(valid)
  costs=np.where(valids[0],.01*(sets[0][:,2]-np.min(sets[0][:,2])),np.inf)
  if start_locked:costs[:256]=np.inf
  parents=[]
  for i in range(1,len(times)):
   dt=times[i]-times[i-1];delta=sets[i-1][:,None,:]-sets[i][None,:,:];distance=np.sum(delta*delta,axis=2)
   trace=Rs[i-1].reshape(257,9)@Rs[i].reshape(257,9).T;angle=np.arccos(np.clip((trace-1)/2,-1,1))
   edge=.3*distance/dt**2+.003*angle*angle/dt**2
   edge[(distance>(2*dt)**2)|(angle>4*dt)]=np.inf
   total=costs[:,None]+edge;parent=np.argmin(total,axis=0);costs=total[parent,np.arange(257)]
   costs+=.0001*(sets[i][:,2]-np.min(sets[i][:,2]));costs[~valids[i]]=np.inf;parents.append(parent)
  last=256 if end_locked else int(np.argmin(costs))
  if not np.isfinite(costs[last]):raise ValueError(('No continuous elbow plan',t0,t1))
  indices=[last]
  for p in parents[::-1]:last=int(p[last]);indices.append(last)
  indices=indices[::-1];qs=np.unwrap(np.array([thetas[i][q] for i,q in enumerate(indices)]));self.t0=t0;self.t1=t1
  # Optimize the authored swivel path, rather than filtering measured forces.
  degree=5;count=18;knots=np.r_[np.repeat(t0,degree+1),np.linspace(t0,t1,count-degree+1)[1:-1],np.repeat(t1,degree+1)]
  samples=np.linspace(t0,t1,201);basis=BSpline(knots,np.eye(count),degree)
  B=basis(samples);B2=basis.derivative(2)(samples);B3=basis.derivative(3)(samples)
  initial=np.linalg.lstsq(basis(times),qs,rcond=None)[0]
  axes=[]
  for t in samples:
   S=Sfun(t);C=Cfun(t);_,base,u,v,h=geometry(S,C,a,b,np.array([0.]));axes.append((S,base,u,v,h))
  Ss=np.array([r[0] for r in axes]);bases=np.array([r[1] for r in axes]);us=np.array([r[2] for r in axes]);vs=np.array([r[3] for r in axes]);hs=np.array([r[4] for r in axes])
  endD=0.
  if end_locked:
   aa=[]
   for tt in [t1-.0001,t1+.0001]:
    S=Sfun(tt);C=Cfun(tt);_,base,u,v,h=geometry(S,C,a,b,np.array([0.]));g=constrained_elbow(S,C,a,b,front=.008)-base;aa.append(math.atan2(np.dot(g,v),np.dot(g,u)))
   endD=(aa[1]-aa[0]+math.pi)%(2*math.pi)-math.pi;endD/=.0002
  eqB=np.array([basis(t0),basis(t1),basis.derivative()(t0),basis.derivative()(t1),basis.derivative(2)(t0),basis.derivative(2)(t1)])
  eqY=np.array([qs[0],qs[-1],0.,endD,0.,0.])
  scales=np.linalg.norm(eqB,axis=1);eqB=eqB/scales[:,None];eqY=eqY/scales
  target=PchipInterpolator(times,qs)(samples)
  A=.001*(B2.T@B2)+.00001*(B3.T@B3)+.1*(B.T@B)
  rhs=.1*B.T@target
  scale=float(np.linalg.norm(A,2));A/=scale;rhs/=scale
  def margins(c):
   ang=B@c;E=bases+hs[:,None]*(np.cos(ang)[:,None]*us+np.sin(ang)[:,None]*vs)
   return np.r_[E[:,0]-Ss[:,0]-.008,Ss[:,1]-E[:,1]-.006]
  result=minimize(lambda c:float(c@A@c-2*rhs@c),initial,jac=lambda c:2*(A@c-rhs),constraints=[{'type':'eq','fun':lambda c:eqB@c-eqY,'jac':lambda c:eqB},{'type':'ineq','fun':margins}],method='SLSQP',options={'maxiter':300,'ftol':1e-9})
  if not result.success or min(margins(result.x))<-1e-7:raise ValueError(('Swivel trajectory optimization failed',t0,t1,result.message,float(min(margins(result.x))),float(max(abs(eqB@result.x-eqY)))))
  self.curve=BSpline(knots,result.x,degree)
 def elbow(self,C,t):
  S=self.Sfun(t);E,*_=geometry(S,C,self.a,self.b,np.array([float(self.curve(np.clip(t,self.t0,self.t1)))]));E=E[0]
  if E[0]<S[0]-.00001 or E[1]>S[1]+.00001:raise ValueError(('Interpolated elbow plan invalid',t))
  return E
