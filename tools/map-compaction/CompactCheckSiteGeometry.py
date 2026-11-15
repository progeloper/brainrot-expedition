#!/usr/bin/env python3
"""Pure candidate site review from frozen complete live manifest and route masks.
AABB overlap is a potential intersection, never a solid/native/gameplay pass.
"""
from __future__ import annotations
import argparse,hashlib,json,math
from pathlib import Path
from shapely.geometry import Polygon,box
from shapely.ops import unary_union
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text())
def write(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
def scalar(v):return v['value'] if isinstance(v,dict) and 'value' in v else v
def props(r):return {k:scalar(v) for k,v in r.get('properties',{}).items()}
def amap(v,c):
 sign=-1 if v<0 else 1;a=abs(v);old,new=0,0
 for k,t in zip([136,313,420,432],[c['t'],c['r'],c['h']-12,c['h']]):
  if a<=k:return sign*(new+(a-old)*(t-new)/(k-old))
  old,new=k,t
 return sign*(new+(a-old)*c['outer'])
def transform(v,c):return [c['origin'][0]+amap(v[0]-c['origin'][0],c),v[1],c['origin'][2]+amap(v[2]-c['origin'][2],c)]
def rotate(v,cf):return [sum(cf[3+i*3+j]*v[j] for j in range(3)) for i in range(3)]
def world(v,cf):r=rotate(v,cf);return [r[i]+cf[i] for i in range(3)]
def local(v,cf):d=[v[i]-cf[i] for i in range(3)];return [sum(cf[3+j*3+i]*d[j] for j in range(3)) for i in range(3)]
def corners(r):
 p=props(r);cf=p['CFrame'];s=p['Size']
 return [world([x*s[0]/2,y*s[1]/2,z*s[2]/2],cf) for x in [-1,1] for y in [-1,1] for z in [-1,1]]
def bounds(vs):return [min(v[0] for v in vs),min(v[2] for v in vs),max(v[0] for v in vs),max(v[2] for v in vs)]
def area_hits(shape,walls):
 hits=[]
 for w in walls:
  x,y,z=w['cframe'][:3];sx,sy,sz=w['size'];wp=box(x-sx/2,z-sz/2,x+sx/2,z+sz/2);over=shape.intersection(wp).area
  if over>1e-6:hits.append({'wallId':w['id'],'regionPair':w.get('regionPair'), 'overlapAreaXZ':over,'wallBoundsXZ':list(wp.bounds),'wallY':[y-sy/2,y+sy/2]})
 return hits

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--plan',type=Path,required=True);ap.add_argument('--roads',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 p=load(a.plan);m=load(ROOT/'docs/map-compaction/BeforeManifest.json');c=p['candidate'];rows=m['objects'];bykey={r['key']:r for r in rows};clear=load(a.roads/'CompactRouteClearance.json')
 roots={r['attributes']['PlacementId']:r for r in rows if r['class']=='Model' and '.MapArt.' in r['path'] and isinstance(r.get('attributes'),dict) and 'PlacementId' in r['attributes']}
 roots.update({r['attributes']['PlacementId']:r for r in rows if r['class']=='Part' and '.MapArt.Backdrops.' in r['path']})
 f=next(r for r in rows if r['path']=='Workspace.MapBlockout.MapArt.InstalledFootprints');footprints=json.loads(f['value']['Value']);assert len(footprints)==343 and len(roots)==343
 walls=p['walls'];retained=p['retainedOuterContainment'];allwalls=walls+[dict(w,regionPair=[w['regionId']],id=w['id']+'_RetainedOuter') for w in retained]
 ordinary=[];mapped=[];counts={};potentials=[]
 for f in footprints:
  root=roots[f['id']];path=root['path'];category='Scenery' if '.Scenery.' in path else 'ShellSource' if '.BaseShells.' in path else 'Service' if '.Services.' in path else 'Backdrop'
  if root['class']=='Model':
   sourcepivot=scalar(root['pivot']);points=[q for r in rows if r['path'].startswith(path+'.') and r['class'] in ['Part','MeshPart','WedgePart'] and props(r).get('Transparency',0)<1 for q in corners(r)]
  else:sourcepivot=props(root)['CFrame'];points=corners(root)
  assert points
  scale=.75 if category in ['Scenery','Backdrop'] else 1 if category=='Service' else c['b'];anchor=transform(sourcepivot[:3],c)
  moved=[[anchor[i]+(q[i]-sourcepivot[i])*scale for i in range(3)] for q in points];b=bounds(moved);shape=box(*b);hits=area_hits(shape,allwalls)
  item={'id':f['id'],'category':category,'sourcePath':path,'prototypeId':root.get('attributes',{}).get('PrototypeId'),'sourceGroundPivot':sourcepivot,'mappedGroundRoot':anchor,'uniformSourceScaleMultiplier':scale,'candidateSourceEnvelopeXZ':b,'candidateSourceYBounds':[min(q[1] for q in moved),max(q[1] for q in moved)],'potentialWallIntersections':hits,'solidIntersectionStatus':'NotAssessed; native trunk/foliage mesh review required if AABB intersects','sourceFootprintXZ':[f['minX'],f['minZ'],f['maxX'],f['maxZ']]}
  if category=='ShellSource':item['status']='Superseded by fitted shell/owner layout; retained only to compare historical envelope'
  ordinary.append(item);counts[category]=counts.get(category,0)+1
  if hits:
   parts=[root] if root['class']=='Part' else [r for r in rows if r['path'].startswith(path+'.') and r['class'] in ['Part','MeshPart','WedgePart'] and props(r).get('Transparency',0)<1]
   groups=[]
   for part in parts:
    vv=[[anchor[i]+(q[i]-sourcepivot[i])*scale for i in range(3)] for q in corners(part)];bb=bounds(vv);yl,yh=min(q[1] for q in vv),max(q[1] for q in vv);hh=[h for h in area_hits(box(*bb),allwalls) if min(yh,h['wallY'][1])-max(yl,h['wallY'][0])>1e-6]
    if hh:groups.append({'name':part['name'],'path':part['path'],'meshId':part.get('mesh',{}).get('MeshId'),'exportGroup':part.get('attributes',{}).get('ExportGroup'),'boundsXZ':bb,'boundsY':[yl,yh],'wallHits':hh,'actualTriangleSolidIntersection':'NotRun'})
   item['potentialNativeGroup3DBoundIntersections']=groups
   potentials.append(item)
  old=box(f['minX'],f['minZ'],f['maxX'],f['maxZ']);pts=[transform([x,0,z],c) for x,z in old.exterior.coords];bm=bounds(pts)
  mapped.append({'id':f['id'],'mappedHistoricalFootprintXZ':bm,'potentialWallIntersections':area_hits(box(*bm),allwalls),'referencePolicy':'T of historical metadata edges only; actual uniform scaled geometry envelope above is authoritative for placement'})
 # A full loaded-cart gate footprint:20-wide tangent by36-long normal.
 floor=unary_union([box(f['x0'],f['z0'],f['x1'],f['z1']) for f in p['floors']]);roadmask=unary_union([Polygon(r['exterior'],r['holes']) for r in clear['roadUnionPolygons']]);gateproof=[]
 for gate in p['gateAprons']:
  g,n=gate['ground'],gate['normal'];ux,uz=n[2],-n[0];car=Polygon([(g[0]+n[0]*z+ux*x,g[2]+n[2]*z+uz*x) for x,z in [(-10,-18),(10,-18),(10,18),(-10,18)]])
  gateproof.append({'id':gate['id'],'routeId':gate['routeId'],'ground':g,'normal':n,'loadedProjectionWidth':20,'loadedProjectionLength':36,'apertureClearWidth':24,'nominalSideMargin':2,'floorOutsideArea':car.difference(floor).area,'roadOutsideArea':car.difference(roadmask).area,'newWallIntersections':area_hits(car,walls),'drivingAndNeighborAccess':'NotRun','fullProjectionPolygon':list(car.exterior.coords)})
 write(a.output/'CompactGateProjectionGeometry.json',{'status':'Source planar full20x36 gate footprint review; actual native driving NotRun','candidate':c,'routeGeometryHash':clear['routeGeometryHash'],'gates':gateproof,'worldMutations':0})
 # Retain exact captured outer instance identities; archive only shared-only old rows.
 outerids={r['id'] for r in retained};archive=[]
 for r in p['existingSeparatorClassification']:
  kinds={v['kind'] for v in r['portions']}
  assert kinds in [{'InterRegion'},{'OuterContainment'}],'Mixed/unclassified separator needs explicit owner handling'
  if kinds=={'InterRegion'}:assert r['id'] not in outerids;archive.append({'id':r['id'],'path':r['path'],'sourceCFrame':r['source']['cframe'],'sourceSize':r['source']['size'],'sourceFlags':r['source']['flags'],'policy':'Move this exact original instance to owned rollback archive before new shared walls become collidable; do not leave duplicate old separator collisions'})
 assert len(archive)==31 and len(retained)==10 and len(outerids)==10
 write(a.output/'CompactSeparatorMigration.json',{'status':'Provisional numerical migration plan; not applied','candidate':c,'baselineManagedContentSHA256':p['baselineManagedContentSHA256'],'sourcePlanSHA256':sha(a.plan),'capturedSeparatorCount':41,'archiveSharedOnlyCount':len(archive),'retainedOuterCount':len(retained),'newSharedWallCount':len(walls),'preserveRetainedInstanceIdentity':True,'retainedOuterRows':retained,'archiveSharedRows':archive,'worldMutations':0})
 # Frozen per-site approaches transformed into owner local frames, independent of b*locals.
 baseprepared=load(ROOT/'docs/map-compaction/CompactBaseLayoutPartLocals_080.Prepared.json');routeby={r['id']:r for r in p['routes']};sites=[]
 for base in baseprepared['bases']:
  cf=base['capturedStructuralPivot'][:];cf[:3]=transform(cf[:3],c);site={'id':base['id'],'structuralTargetCFrame':cf,'cartSpur':{},'houseSpur':{}}
  for kind,width in [('Cart',24),('House',20)]:
   r=routeby[base['id']+'_'+kind+'Spur'];localpoints=[local(q,cf) for q in r['controlPoints']]
   site[kind.lower()+'Spur']={'routeId':r['id'],'width':width,'localControlPoints':localpoints,'sourceSemanticFrozen':True,'ordinaryLandingLocalX':28*c['b'] if kind=='Cart' else -24*c['b'],'mappedSpurLocalX':localpoints[-1][0]}
  loop=routeby['Camp_Loop'];looplocal=[local(q,cf) for q in loop['controlPoints']];zs=[q[2] for q in looplocal if abs(q[2])<1000]
  qloop=-(amap(336,c)-amap(192,c));site['frozenLoopCentreLocalZ']=qloop;site['frozenLoopWidth']=36;site['nearestLoopEdgeLocalZ']=qloop+18
  site['cartLandingCentreLateralDifference']=site['cartSpur']['ordinaryLandingLocalX']-site['cartSpur']['mappedSpurLocalX'];site['straight20WideCartCentreToleranceOn24Lane']=2
  site['loadedApproachStatus']='Turning/physics NotRun; body20x36 and native45-case cargos must be checked, no straight on-road claim from pad fit'
  sites.append(site)
 report={'status':'Source AABB review; actual solid/gameplay intersections NotRun','candidate':c,'baselineManagedContentSHA256':p['baselineManagedContentSHA256'],'sourceBeforeManifestSHA256':sha(ROOT/'docs/map-compaction/BeforeManifest.json'),'sourcePlanSHA256':sha(a.plan),'routeGeometryHash':clear['routeGeometryHash'],'fullCapturedArtFootprints':len(footprints),'categories':counts,'sharedWalls':len(walls),'retainedOuterPortions':len(retained),'potentialSourceEnvelopeIntersectingArtCount':len(potentials),'potentialScenerySourceEnvelopeIntersectingArtCount':sum(r['category']=='Scenery' for r in potentials),'potentialMappedHistoricalFootprintIntersectingArtCount':sum(bool(r['potentialWallIntersections']) for r in mapped),'potentialIntersections':potentials,'artSourceEnvelopes':ordinary,'mappedHistoricalFootprints':mapped,'siteApproaches':sites,'limits':['AABB intersections are candidates for native solid review, not proof of actual tree-trunk/foliage wall overlap.','Fitted shells and owner support/centroid overrides supersede their historical bounds.','Full cart gate projection20x36 and actual turning/neighbor/mob tests remain parent-owned native checks.'],'worldMutations':0}
 write(a.output/'CompactArtWallIntersections.json',report)
 write(a.output/'CompactBaseApproachGeometry.json',{'status':'Frozen source route contacts; not native loaded driving proof','candidate':c,'baselineManagedContentSHA256':p['baselineManagedContentSHA256'],'routeGeometryHash':clear['routeGeometryHash'],'sites':sites,'worldMutations':0})
 print(json.dumps({k:report[k] for k in ['status','categories','potentialSourceEnvelopeIntersectingArtCount','potentialScenerySourceEnvelopeIntersectingArtCount','potentialMappedHistoricalFootprintIntersectingArtCount']},indent=2))
if __name__=='__main__':main()
