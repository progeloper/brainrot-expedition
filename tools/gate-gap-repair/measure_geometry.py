import json, math, collections
from pathlib import Path
ROOT=Path('/private/tmp/GateGapAudit')
data=json.loads((ROOT/'Live.json').read_text())
geo=data['geometry']
def attrs(p): return p['attrs'] if isinstance(p['attrs'],dict) else {}
def bounds(p):
 c=p['cf']; s=p['size']; e=[sum(abs(c[3+3*i+j])*s[j]/2 for j in range(3)) for i in range(3)]
 return [c[i]-e[i] for i in range(3)]+[c[i]+e[i] for i in range(3)]
def axisaligned(p):
 r=p['cf'][3:]
 return all(sum(abs(abs(v)-1)<1e-5 for v in r[i:i+3])==1 and all(abs(v)<1e-5 or abs(abs(v)-1)<1e-5 for v in r[i:i+3]) for i in (0,3,6))
def merge(intervals):
 out=[]
 for a,b in sorted(intervals):
  if out and a<=out[-1][1]+.0001: out[-1][1]=max(b,out[-1][1])
  else: out.append([a,b])
 return out
def gaps(intervals,lo,hi):
 out=[];cur=lo
 for a,b in merge(intervals):
  a,b=max(a,lo),min(b,hi)
  if b<=a: continue
  if a>cur+.0001: out.append([cur,a])
  cur=max(cur,b)
 if cur<hi-.0001: out.append([cur,hi])
 return out
def linecoverage(parts,axis,fixed,height,lo=-math.inf,hi=math.inf):
 alongidx=0 if axis=='X' else 2; fixedidx=2 if axis=='X' else 0
 intervals=[]; owners=[]
 for p in parts:
  b=bounds(p)
  if b[fixedidx]-.0001<=fixed<=b[fixedidx+3]+.0001 and b[1]-.0001<=height<=b[4]+.0001 and b[alongidx+3]>lo and b[alongidx]<hi:
   a,z=max(lo,b[alongidx]),min(hi,b[alongidx+3]); intervals.append([a,z]);owners.append({'path':p['path'],'interval':[a,z]})
 return merge(intervals),owners
structural=[p for p in geo if p['class']=='Part' and p['collide'] and p['query'] and ('EV2_Run_' in p['path'] or '.Gate_' in p['path'] or '.X_Camp_Exterior_' in p['path'])]
gateparts=[p for p in geo if p['class']=='Part' and p['collide'] and '.ProgressionGates.' in p['path']]
assert all(axisaligned(p) for p in structural+gateparts)
paid=[]; proposals=[]
for th in [p for p in geo if '.ProgressionGates.' in p['path'] and p['path'].endswith('.Threshold')]:
 key=th['path'].split('.')[-2];c=th['cf']; R=[c[3],c[6],c[9]]
 axis='X' if abs(R[0])>.9 else 'Z'; fixed=c[2] if axis=='X' else c[0]; center=c[0] if axis=='X' else c[2]
 pure,pureowners=linecoverage(structural,axis,fixed,5,center-70,center+70)
 pre,_=linecoverage(structural+gateparts,axis,fixed,5,center-70,center+70)
 # structural gap containing threshold
 hole=[z for z in gaps(pure,center-70,center+70) if z[0]<center<z[1]]
 assert len(hole)==1,(key,pure,hole)
 cut=hole[0];ap=[center-12,center+12]
 row={'gate':key,'axis':axis,'fixed':fixed,'center':center,'actualStructuralOpening':cut,'actualOpeningWidth':cut[1]-cut[0],'centerOffsetFromStructuralOpening':center-(cut[0]+cut[1])/2,'desiredAperture':ap,'preRepairGapsBelowHeader':gaps(pre,*cut),'structuralOwners':pureowners,'nativeThresholdCF':c,'thresholdSize':th['size']}
 for side,interval in [('Negative',[cut[0]-.25,ap[0]]),('Positive',[ap[1],cut[1]+.25])]:
  first,last=interval
  pos=[fixed,10.05,(first+last)/2] if axis=='Z' else [(first+last)/2,10.05,fixed]
  size=[40,20,last-first] if axis=='Z' else [last-first,20,40]
  # More narrow depth than source walls is adequate on plane but 40 produces proper joins to 8..96-depth native structures.
  proposal={'gate':key,'side':side,'worldPosition':pos,'worldSize':size,'nativeCFrame':[ *pos,1,0,0,0,1,0,0,0,1],'alongInterval':interval,'wallDepth':40,'bottom':.05,'top':20.05,'minimalGapInterval':[cut[0],ap[0]] if side=='Negative' else [ap[1],cut[1]],'brickCourseMax':[8,4,8]}
  proposals.append(proposal)
 paid.append(row)
# Real floor rectangle union per region, pure grid edge merger.
byregion=collections.defaultdict(list)
for p in geo:
 if attrs(p).get('LayoutRole')=='Floor' and attrs(p).get('GeneratedBy')=='CreateBasicMap_v1':
  b=bounds(p);byregion[p['path'].split('.')[2]].append({'x0':b[0],'x1':b[3],'z0':b[2],'z1':b[5]})
def perimeters(rects):
 xs=sorted(set(v for r in rects for v in (r['x0'],r['x1'])))
 zs=sorted(set(v for r in rects for v in (r['z0'],r['z1'])))
 occupied=set()
 for i in range(len(xs)-1):
  for j in range(len(zs)-1):
   x,z=(xs[i]+xs[i+1])/2,(zs[j]+zs[j+1])/2
   if any(r['x0']<x<r['x1'] and r['z0']<z<r['z1'] for r in rects):occupied.add((i,j))
 lines=collections.defaultdict(list)
 for i,j in occupied:
  if (i-1,j) not in occupied:lines[('Z',xs[i],1)].append([zs[j],zs[j+1]])
  if (i+1,j) not in occupied:lines[('Z',xs[i+1],-1)].append([zs[j],zs[j+1]])
  if (i,j-1) not in occupied:lines[('X',zs[j],1)].append([xs[i],xs[i+1]])
  if (i,j+1) not in occupied:lines[('X',zs[j+1],-1)].append([xs[i],xs[i+1]])
 return [{'axis':k[0],'fixed':k[1],'inward':k[2],'first':z[0],'last':z[1]} for k,v in sorted(lines.items()) for z in merge(v)]
boundary=[]
for region,rects in sorted(byregion.items()):
 for edge in perimeters(rects):
  cov,owners=linecoverage(structural+gateparts,edge['axis'],edge['fixed'],5,edge['first'],edge['last'])
  missing=gaps(cov,edge['first'],edge['last'])
  boundary.append({'region':region,**edge,'coverage':cov,'gaps':missing,'owners':owners})
result={'method':'Actual anchored/collidable/queryable Part AABBs with asserted cardinal rotations; no native visible MeshPart envelopes treated as collision. Union floor perimeter checked at Y=5 including exact span endpoints. Gate openings analysed at same plane; intended open aperture remains 24 studs. These are geometric measurements; root owns native casts and gameplay authorization tests.','inputPartCount':len(geo),'structuralColliders':len(structural),'paidGateParts':len(gateparts),'paidGates':paid,'proposedJambEnvelopes':proposals,'perimeterLines':boundary}
(ROOT/'GeometryCoverage.json').write_text(json.dumps(result,indent=2))
print('gate measurements')
for p in paid:print(p['gate'],p['axis'],p['fixed'],'opening',p['actualStructuralOpening'],'offset',round(p['centerOffsetFromStructuralOpening'],5),'gaps',p['preRepairGapsBelowHeader'])
print('\nall region perimeter openings')
for e in boundary:
 if e['gaps']:print(e['region'],e['axis'],e['fixed'],[e['first'],e['last']],e['gaps'])
