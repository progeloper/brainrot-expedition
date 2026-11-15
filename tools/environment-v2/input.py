"""Bind the fresh native compact scene to geometry data. Does not run T or mutate Studio."""
import json,hashlib,math
from pathlib import Path
from collections import defaultdict
from shapely.geometry import box
from shapely.ops import unary_union
from geometry import *
ROOT=Path(__file__).resolve().parents[2]
EXPECTED_SCENE='f396b10caf4d1ab7e6b9aa8dd61fcab89bc904f33d95c899de887ac9950089e9'
COMPACT_HASH='916d8081573c119b7e868caf853998cd1895976a4d579ca773dbe640bc361dc1'
CANONICAL_ROADS='696d1821c5ebc3a595f9437366c1c777f31d6ea5f2b0f303fd8a2a895a32dbb0'

def load(path):return json.loads(Path(path).read_text())
def bind_scene(path=ROOT/'docs/environment-v2/BeforeManifest.json'):
 sourcefile=Path(path).resolve();raw=sourcefile.read_bytes();manifest=json.loads(raw)
 assert hashlib.sha256(raw).hexdigest()==EXPECTED_SCENE,'Fresh live scene bytes differ; remeasure and bind a new baseline'
 assert manifest['placeId']==91958083796436 and manifest['universeId']==10548905405 and manifest['mode']=='Edit'
 assert manifest['compactPlanHash']==COMPACT_HASH
 rows=[r for r in manifest['records']if r['scope']=='Map'];assert len(rows)==1581
 bypath={r['path']:r for r in rows};bykey={r['key']:r for r in rows};maprow=bypath['Workspace.MapBlockout']
 origin=(maprow['attributes']['OriginX'],maprow['attributes']['OriginZ'])
 floors=[];regions=defaultdict(list);ground=[]
 for r in rows:
  if r['name'].startswith('Floor_R'):
   cf=unpack(r['properties']['CFrame']);size=unpack(r['properties']['Size'])
   assert max(abs(a-b)for a,b in zip(cf[3:],[1,0,0,0,1,0,0,0,1]))<=1e-6
   region=NAMES[r['path'].split('.')[2]];geom=part_projection(cf,size);regions[region].append(geom);ground.append(cf[1]+size[1]/2)
   floors.append({'id':r['key'],'path':r['path'],'regionId':region,'cframe':cf,'size':size,'bounds':bounds3(cf,size)})
 assert len(floors)==25 and set(regions)==set(REGIONS) and max(ground)-min(ground)<1e-6
 regions={k:unary_union(v)for k,v in regions.items()};ground=sum(ground)/len(ground)
 mask=load(ROOT/'tools/map-compaction/generated/selected-b085/CompactRouteClearance.json')
 native=load(ROOT/'docs/map-compaction/CompactColdNativeAssetsProof.json')
 assert native['status']=='Passed' and native['completeBatch'] and native['roadGeometryHash']==CANONICAL_ROADS
 proof={r['id']:r for r in native['groups']if r['prototypeId']=='CompactMapRoads'}
 roads=[]
 for r in rows:
  if r['path'].startswith('Workspace.MapBlockout.Paths.StyledSurfaces.')and r['class']=='MeshPart':
   g=proof[r['name']];p=r['properties'];cf=unpack(p['CFrame']);size=unpack(p['Size'])
   assert p['MeshId']==g['meshId'] and g['passed'] and g['geometryCornersComplete']
   assert max(abs(a-b)for a,b in zip(cf[:3],g['canonicalCentre']))<=TOL
   assert max(abs(a-b)for a,b in zip(cf[3:],[1,0,0,0,1,0,0,0,1]))<=1e-6
   assert max(abs(size[i]-g['sizeXYZ'][i])for i in [0,2])<=TOL
   roads.append({'id':r['name'],'originalKey':r['key'],'meshId':p['MeshId'],'cframe':cf,'size':size,'actualNativeCorners':g['checkedCorners']})
 assert len(roads)==27 and sum(r['actualNativeCorners']for r in roads)==3141
 road=decode_geometry(mask['roadUnionPolygons']);owners=mask['routePolygonsByOwner']
 assert abs(road.area-mask['roadUnionArea'])<1e-2
 draft=load(ROOT/'tools/map-compaction/CompactDraft_b085.json')
 gates={};gate_reservations=[]
 for name in ['Beach','Swamp','Jungle','Arctic','Volcano','GlitchZone']:
  path='Workspace.MapBlockout.ProgressionGates.'+name
  model=bypath[path];members=[r for r in rows if r['path'].startswith(path+'.')and isinstance(r.get('properties'),dict)and'CFrame'in r['properties'] and '.BoundarySeparators.'not in r['path']]
  threshold=bypath[path+'.Threshold'];cf=unpack(threshold['properties']['CFrame']);G=[cf[0],ground,cf[2]]
  old=next(c for c in draft['crossings']if c.get('owningGate')==name)
  assert math.hypot(G[0]-old['apertureCentre'][0],G[2]-old['apertureCentre'][2])<=TOL
  opening=next(o for o in draft['approvedOpeningPolygons']if o['id']=='Gate_'+name)
  oshape=unary_union([Polygon(p)for p in opening['polygons']]);dx,dz=G[0]-old['apertureCentre'][0],G[2]-old['apertureCentre'][2];oshape=affinity.translate(oshape,xoff=dx,yoff=dz)
  # Existing invisible threshold/approach are reference volumes. Preserve their ground approach, while overhead art may lie above the actual clear ceiling.
  approach=next(r for r in members if r['name']=='Approach');ac=unpack(approach['properties']['CFrame']);asz=unpack(approach['properties']['Size']);ares=part_projection(ac,asz)
  door=next(r for r in members if r['name']=='DoorPresentation');dp=door['properties'];dsize=unpack(dp['Size'])
  lintel=next(r for r in members if r['name']=='Lintel');lp=lintel['properties'];lb=bounds3(unpack(lp['CFrame']),unpack(lp['Size']))
  gates[name]={'id':name,'originalKey':model['key'],'ground':G,'regionPair':old['regionPair'],'crossing':old,'openingPolygons':encode_geometry(oshape),'approachPolygons':encode_geometry(ares),'clearWidth':24,'existingLintelBounds':lb,'newHeaderUnderside':lb['maxY'],'closedPaidGeometry':{'status':'NotAchieved','code':'ClosedPaidPhysicalBarrierAbsent','existingDoorSize':dsize,'CanCollide':dp['CanCollide'],'CanQuery':dp['CanQuery'],'SourceOwnerForbidsCollidableDoor':True}}
  gate_reservations.append(ares.union(oshape))
 free=next(o for o in draft['approvedOpeningPolygons']if o['accessPolicy']=='ExistingFreeCampForestRoad')
 freeShape=unary_union([Polygon(p)for p in free['polygons']])
 openings=[{'id':'Gate_'+name,'regionPair':g['regionPair'],'ground':g['ground'],'polygons':g['openingPolygons'],'newHeaderUnderside':g['newHeaderUnderside'],'paid':True}for name,g in gates.items()]
 freeCross=next(c for c in draft['crossings']if c['accessPolicy']=='ExistingFreeCampForestRoad')
 openings.append({'id':free['id'],'regionPair':freeCross['regionPair'],'ground':freeCross['apertureCentre'],'polygons':encode_geometry(freeShape),'newHeaderUnderside':ground+20,'paid':False})
 fixed=[];base_ids=[];service_ids=[]
 for r in rows:
  p=r.get('properties') or {};path=r['path']
  if 'CFrame'not in p or 'Size'not in p:continue
  if path.startswith('Workspace.MapBlockout.PlayerBasePatches.') or path.startswith('Workspace.MapBlockout.MapArt.BaseShells.') or path.startswith('Workspace.MapBlockout.MapArt.Services.') or path.startswith('Workspace.MapBlockout.ServiceStallPatches.'):
   cf=unpack(p['CFrame']);size=unpack(p['Size']);fixed.append({'id':r['key'],'path':path,'kind':'FunctionalPart','polygons':encode_geometry(part_projection(cf,size))})
 for r in rows:
  if r['class']=='Model'and r['path'].startswith('Workspace.MapBlockout.PlayerBasePatches.'):
   if r['path'].count('.')!=3:continue
   base_ids.append(r['name']);cf=unpack(r['attributes']['BaseOrigin']);lo=unpack(r['attributes']['ReservationMin']);hi=unpack(r['attributes']['ReservationMax']);centre=[(a+b)/2 for a,b in zip(lo,hi)];size=[hi[0]-lo[0],.01,hi[2]-lo[2]]
   fixed.append({'id':r['key']+'/Reservation','path':r['path'],'kind':'ExistingBaseReservation','polygons':encode_geometry(part_projection(cfcompose(cf,frame(*centre)),size))})
  if r['path'].startswith('Workspace.MapBlockout.ServiceStallPatches.')and r['attributes'].get('LayoutRole')=='ServiceStall':
   service_ids.append(r['name']);cf=unpack(r['properties']['CFrame']);size=unpack(r['attributes']['LogicalInteractionEnvelope']);fixed.append({'id':r['key']+'/LogicalInteraction','path':r['path'],'kind':'ExistingServiceLogicalEnvelope','polygons':encode_geometry(part_projection(cf,size))})
   centre=unpack(r['attributes']['WaitingAreaCentre']);size=unpack(r['attributes']['WaitingAreaSize']);w=box(origin[0]+centre[0]-size[0]/2,origin[1]+centre[2]-size[1]/2,origin[0]+centre[0]+size[0]/2,origin[1]+centre[2]+size[1]/2);fixed.append({'id':r['key']+'/Waiting','path':r['path'],'kind':'ExistingServiceWaitingArea','polygons':encode_geometry(w)})
 assert len(base_ids)==12 and len(service_ids)==6
 for name,g in gates.items():fixed.append({'id':'Gate_'+name+'/Approach','kind':'ExistingGateApproach','polygons':g['approachPolygons']})
 hero={};archive=[];archiveWalls=[];oldWalls=[]
 for r in rows:
  if r['class']=='Model'and r['path'].startswith('Workspace.MapBlockout.MapArt.Scenery.')and r['path'].count('.')==4:
   archive.append({'originalKey':r['key'],'originalPath':r['path'],'category':'OwnedDecorativeScenery','oldOwner':'BrainrotExpedition_MapArt','reason':'Explicit authorised environment replacement'})
   if r['name'].endswith('Landmark'):
    region=NAMES[r['name'].replace('Landmark','')];hero[region]=unpack(r['pivot'])[:3]
  if r['path'].startswith('Workspace.MapBlockout.MapArt.Backdrops.')and'CFrame'in(r.get('properties')or{}):archive.append({'originalKey':r['key'],'originalPath':r['path'],'category':'OwnedDecorativeBackdrop','oldOwner':'BrainrotExpedition_MapArt','reason':'Explicit authorised environment replacement'})
  if r['path'].startswith('Workspace.MapBlockout.RegionWalls.')or'.BoundarySeparators.'in r['path']:
   p=r.get('properties')or{}
   if 'CFrame'in p:
    oldWalls.append({'originalKey':r['key'],'originalPath':r['path'],'cframe':unpack(p['CFrame']),'size':unpack(p['Size']),'category':'ExistingBoundary'})
    archiveWalls.append({'originalKey':r['key'],'originalPath':r['path'],'category':'SupersededBoundary','oldOwner':r['attributes'].get('CompactMapMigrationId',r['attributes'].get('ManagedBy')),'reason':'Archive only after complete approved boundary replacement validates'})
 assert len(archive)==325 and len(hero)==7 and len(oldWalls)==64
 out={'schemaVersion':2,'baselineSceneSHA256':EXPECTED_SCENE,'compactPlanHash':COMPACT_HASH,'sourcePath':str(sourcefile),'origin':list(origin),'groundY':ground,'floors':floors,'regions':{k:encode_geometry(v)for k,v in regions.items()},'roads':roads,'roadPolygons':encode_geometry(road),'roadMasksEvidence':{'routeGeometryHash':CANONICAL_ROADS,'actualNativeGroups':27,'actualNativeCorners':3141,'verifiedCurrentMeshIdFrameAndSize':True},'routes':owners,'gates':gates,'openings':openings,'closedAlternates':[c for c in draft['crossings']if c['accessPolicy']=='ExistingEquivalentRestriction'],'fixedReservations':fixed,'heroPreferences':hero,'archive':archive,'boundaryArchive':archiveWalls,'oldWalls':oldWalls,'fullNativeWildFit':load(ROOT/'docs/environment-v2/WildEnvelopeFit.json'),'geometryPolicy':'Actual current floor/part frames plus corner-verified current road union. Does not call map transform or use old source coordinates.'}
 return out
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();result=bind_scene();a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'status':'ActualCurrentGeometryBound','hash':result['baselineSceneSHA256'],'floors':len(result['floors']),'roadGroups':len(result['roads']),'openings':len(result['openings']),'archive':len(result['archive']),'boundaryArchive':len(result['boundaryArchive']),'protectedReservations':len(result['fixedReservations'])}))
