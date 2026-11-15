#!/usr/bin/env python3
"""Independent numerical volume check of all final wall chunks and apertures."""
import argparse,json,hashlib
from pathlib import Path
from shapely.geometry import Polygon,box
from shapely.ops import unary_union
ap=argparse.ArgumentParser();ap.add_argument('--plan',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();p=json.loads(a.plan.read_text());walls=p['walls'];hits=[]
for i,w in enumerate(walls):
 for v in walls[i+1:]:
  ds=[max(0,min(w['cframe'][j]+w['size'][j]/2,v['cframe'][j]+v['size'][j]/2)-max(w['cframe'][j]-w['size'][j]/2,v['cframe'][j]-v['size'][j]/2)) for j in range(3)];vol=ds[0]*ds[1]*ds[2]
  if vol>1e-8:hits.append({'first':w['id'],'second':v['id'],'overlapVolume':vol})
assert not hits
openings=p['approvedOpeningPolygons'];bad=[]
for o in openings:
 # Full-thickness opening source geometry, not only its centre line.
 poly=unary_union([Polygon(q) for q in o['polygons']])
 for w in walls:
  x,z=w['cframe'][0],w['cframe'][2];sx,sz=w['size'][0],w['size'][2];area=poly.intersection(box(x-sx/2,z-sz/2,x+sx/2,z+sz/2)).area
  if area>1e-6:bad.append({'opening':o.get('crossingId',o.get('id')),'wall':w['id'],'area':area})
assert not bad
r={'status':'IndependentSourceVolumesPassed; native wall readback NotRun','candidate':p['candidate'],'sourcePlanSHA256':hashlib.sha256(a.plan.read_bytes()).hexdigest(),'wallCount':len(walls),'checkedUnorderedPairs':len(walls)*(len(walls)-1)//2,'positiveVolumeWallOverlaps':hits,'openingPolygonCount':len(openings),'fullThicknessApertureIntersections':bad,'nativeCollisionStatus':'NotRun','worldMutations':0};a.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:r[k] for k in ['status','wallCount','checkedUnorderedPairs','openingPolygonCount']},indent=2))
