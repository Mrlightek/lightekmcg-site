"""Pinned contact action solver. Writes only the requested operation work directory."""
import argparse,json,hashlib,gzip,warnings
from pathlib import Path
import numpy as np
from scipy.optimize import OptimizeWarning
import solve,feasible

def run(output):
 with warnings.catch_warnings():
  warnings.filterwarnings('ignore',category=OptimizeWarning,message='Unrecognized options detected.*')
  data=solve.simulate();report=feasible.analyze(data)
 if not report.get('simulation_checks_passed'):
  output.write_text(json.dumps({'report':report},default=lambda x:x.item()));return
 frames=[]
 for frame in range(193):
  row=data['rows'][round(frame/24/.001)];pose=feasible.model(row)
  parts=[{k:(v.tolist() if isinstance(v,np.ndarray) else v) for k,v in p.items()} for p in pose['parts']]
  frames.append({'frame':frame+1,'scene_time':frame/24,'physics_time':row['t'],'parts':parts,'eyes':pose['eyes'],'geoms':row['geoms'],'ball':row['ball'],'ball_quat':row['ball_quat'],'normal_N':row['N']})
 raw=json.dumps(data,separators=(',',':')).encode();compressed=output.with_suffix('.json.gz');compressed.write_bytes(gzip.compress(raw,mtime=0))
 report['events']=data['events'];output.write_text(json.dumps({'report':report,'frames':frames,'simulation_sha256':hashlib.sha256(raw).hexdigest(),'raw_file':compressed.name},default=lambda x:x.item()))
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);run(parser.parse_args().output)
