"""Pure baseline-driven owned geometry plan; no live Studio writes."""
import json,math,hashlib,collections
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'docs/map-compaction';T=ROOT/'tools/map-compaction'
load=lambda p:json.loads(p.read_text())
before=load(D/'BeforeManifest.json');draft=load(T/'CompactDraft_b085.json')
baseLocals=load(D/'CompactBaseLayoutPartLocals_085.Prepared.json')
C=draft['candidate'];b=C['b'];O=C['origin'];factor=.75
shellMeta=load(D/'CompactBaseLayoutShell_085.Manifest.json');shellBounds=[shellMeta['bounds_min'],shellMeta['bounds_max']]
assert b==.85 and before['baselineManagedContentSHA256']==draft['baselineManagedContentSHA256']
def f(v):
 a=abs(v);knots=[(0,0),(136,C['t']),(313,C['r']),(420,C['h']-12),(432,C['h'])]
 if a>432:out=C['h']+(a-432)*C['outer']
 else:
  for (x0,y0),(x1,y1) in zip(knots,knots[1:]):
   if a<=x1:out=y0+(a-x0)*(y1-y0)/(x1-x0);break
 return math.copysign(out,v)
def tr(p):return [O[0]+f(p[0]-O[0]),p[1],O[2]+f(p[2]-O[2])]
def add(a,b):return[x+y for x,y in zip(a,b)]
def sub(a,b):return[x-y for x,y in zip(a,b)]
def rot(cf,q):return[sum(cf[3+i*3+j]*q[j]for j in range(3))for i in range(3)]
def cfPoint(cf,q):return add(cf[:3],rot(cf,q))
def moved(cf,p):return list(p)+cf[3:]
def compose(a,c):
 r=[sum(a[3+i*3+k]*c[3+k*3+j] for k in range(3))for i in range(3)for j in range(3)]
 return cfPoint(a,c[:3])+r
rows=before['objects'];byPath={r['path']:r for r in rows};byKey={r['key']:r for r in rows};ops=[];ownership={};roots={}
mapPath='Workspace.MapBlockout';basePath=mapPath+'.PlayerBasePatches.'
def own(path,kind):
 assert path not in ownership,('double ownership',path);ownership[path]=kind

def operation(r,kind,**fields):
 own(r['path'],kind);ops.append({'key':r['key'],'path':r['path'],'category':kind,**fields})
# Every floor has a genuine descriptor based on transformed axis boundaries.
for x in draft['floors']:
 r=byKey[x['id']];operation(r,'RegionFloor',cframe=[(x['x0']+x['x1'])/2,x['y'],(x['z0']+x['z1'])/2,1,0,0,0,1,0,0,0,1],size=[x['x1']-x['x0'],x['thickness'],x['z1']-x['z0']])
# The global Baseplate is a supporting region floor, with transformed actual edges.
for r in before['externalStaticObjects']:
 if r['class']=='Part' and r['name']=='Baseplate':
  cf=r['properties']['CFrame']['value'];s=r['properties']['Size']['value'];low=tr([cf[0]-s[0]/2,cf[1],cf[2]-s[2]/2]);high=tr([cf[0]+s[0]/2,cf[1],cf[2]+s[2]/2]);operation(r,'ExternalSupportingFloor',cframe=moved(cf,[(low[0]+high[0])/2,cf[1],(low[2]+high[2])/2]),size=[high[0]-low[0],s[1],high[2]-low[2]])
# Final base locals are common to all twelve owners; never scale an actor/template.
for x in baseLocals['bases']:
 r=byPath[basePath+x['id']];old=x['capturedStructuralPivot'];frame=moved(old,tr(old[:3]));roots[x['id']]={'old':old,'new':frame}
 operation(r,'BaseBundle',pivot=frame,attributes={'BaseOrigin':{'type':'CFrame','value':frame},'ReservationMin':{'type':'Vector3','value':[-56*b,0,-84*b]},'ReservationMax':{'type':'Vector3','value':[56*b,0,36*b]}})
 for part in x['parts']:
  r=byPath[part['sourcePath']];operation(r,'BaseBundleMember',cframe=compose(frame,part['localCFrame']),size=part['size'])
# Kiosks keep actual 24x18 facades/functional geometry and trim excess patch to28x22.
for r in rows:
 if r['path'].startswith(mapPath+'.ServiceStallPatches.') and 'properties'in r:
  old=r['properties']['CFrame']['value'];operation(r,'ServiceBundle',cframe=moved(old,tr(old[:3])),size=[28,old[1]*0+ r['properties']['Size']['value'][1],22])
# Ordinary native art is read-only geometry transformed once about captured ground root.
for r in rows:
 p=r['path']
 if p.startswith(mapPath+'.MapArt.Scenery.') and r['class']=='Model':
  old=r['pivot']['value'];children=[z for z in rows if z['path'].startswith(p+'.')]
  assert all(not z['properties']['CanCollide'] and not z['properties']['CanQuery'] for z in children if 'properties'in z),'Functional landmark needs rigid classification'
  assert not any(z['class'] in ['ProximityPrompt','Script','LocalScript','ClickDetector','Seat','VehicleSeat']for z in children)
  new=moved(old,tr(old[:3]));operation(r,'OrdinaryDecorativeModel',pivot=new,scale=r['scale']*factor);roots[r['attributes']['PlacementId']]={'old':old,'new':new,'factor':factor}
 if p.startswith(mapPath+'.MapArt.Backdrops.') and 'properties'in r:
  old=r['properties']['CFrame']['value'];s=r['properties']['Size']['value'];ground=[old[0],old[1]-s[1]/2,old[2]];newroot=tr(ground);new=add(newroot,[0,s[1]*factor/2,0]);operation(r,'DecorativeBackdrop',cframe=moved(old,new),size=[v*factor for v in s]);roots[r['attributes']['PlacementId']]={'old':moved(old,ground),'new':moved(old,newroot),'factor':factor}
 if p.startswith(mapPath+'.MapArt.Services.') and r['class']=='Model':
  old=r['pivot']['value'];new=moved(old,tr(old[:3]));operation(r,'ServiceArtBundle',pivot=new);roots[r['attributes']['PlacementId']]={'old':old,'new':new,'factor':1}
 if p.startswith(mapPath+'.MapArt.BaseShells.') and r['class']=='Model':
  id=r['name'].replace('Showhouse_','');base=roots[id];g=load(D/'CompactBaseLayoutRuntimeGeometry.Prepared.json')['bases'][id];q=[g['support']['centreX'],1,g['support']['centreZ']]
  # Original shell Y comes from actual base-facing local ground, not bounding centre.
  old=r['pivot']['value'];q[1]=old[1]-base['old'][1];new=compose(base['new'],q+[1,0,0,0,1,0,0,0,1]);operation(r,'FittedBaseShell',pivot=new,meshPrototype='CompactFittedShowhouse');roots[r['attributes']['PlacementId']]={'old':old,'new':new,'fitted':True}
# Gates own their fixed-size frame members; separator spans have separate edge ownership.
for r in rows:
 p=r['path']
 if p.startswith(mapPath+'.ProgressionGates.') and r['class']=='Model':
  threshold=byPath[p+'.Threshold']['properties']['CFrame']['value'];g=threshold[:3];g[1]=O[1];new=tr(g);delta=sub(new,g)
  operation(r,'GateBundleMetadata',gateGround=new)
  for child in rows:
   if child['path'].startswith(p+'.') and 'properties'in child and '.BoundarySeparators.'not in child['path']:
    old=child['properties']['CFrame']['value'];operation(child,'GateBundleMember',cframe=moved(old,add(old[:3],delta)))
retained={x['id']:x for x in draft['retainedOuterContainment']}
for x in draft['existingSeparatorClassification']:
 r=byKey[x['id']]
 if x['id'] in retained:
  t=retained[x['id']];operation(r,'RetainedOuterContainment',cframe=t['cframe'],size=t['size'])
 else:operation(r,'SupersededSharedSeparator',retire=True)
# Invisible legacy Parts remain query/reference adapters at transformed actual descriptors.
for r in rows:
 if r['path'].startswith(mapPath+'.Paths.Surface_'):
  old=r['properties']['CFrame']['value'];s=r['properties']['Size']['value'];ex=abs(old[3])*s[0]/2+abs(old[5])*s[2]/2;ez=abs(old[9])*s[0]/2+abs(old[11])*s[2]/2
  lo=tr([old[0]-ex,old[1],old[2]-ez]);hi=tr([old[0]+ex,old[1],old[2]+ez]);wx,wz=hi[0]-lo[0],hi[2]-lo[2]
  size=[wx if abs(old[3])>.5 else wz,s[1],wz if abs(old[3])>.5 else wx]
  operation(r,'LegacyRouteCompatibilityDescriptor',cframe=moved(old,[(lo[0]+hi[0])/2,old[1],(lo[2]+hi[2])/2]),size=size)
for r in rows:
 if r['path'].startswith(mapPath+'.Paths.StyledSurfaces.') and r['class']=='MeshPart':operation(r,'RebuiltRoadSurface',meshPrototype=r['name'])
# Ancestors and carried markers/GUI/parts inherit exactly one owner; nothing moves independently.
for r in rows:
 if r['class']=='StringValue' and r['name']=='InstalledFootprints':own(r['path'],'ArtFootprintCache')
for r in rows:
 if r['path'] in ownership:continue
 p=r['path'];parent=p.rsplit('.',1)[0]
 while parent not in ownership and parent.startswith(mapPath+'.'):parent=parent.rsplit('.',1)[0]
 if parent in ownership:own(p,ownership[parent]+'Child')
 elif r['class']=='Folder':own(p,'MetadataContainer')
 elif r['class']=='StringValue' and r['name']=='InstalledFootprints':own(p,'ArtFootprintCache')
 else:raise AssertionError(('Unclassified original',p,r['class']))
assert len([r for r in rows if r['path'] in ownership])==1555
footrow=next(r for r in rows if r['name']=='InstalledFootprints');footprints=load(D/'BeforeManifest.json')['objects'];footprints=json.loads(footrow['value']['Value'])
for fp in footprints:
 owner=roots[fp['id']]
 if owner.get('fitted'):
  # Precise world ground projection of authored rebuilt shell bounds.
  cf=owner['new'];corners=[cfPoint(cf,[x,0,z])for x in [shellBounds[0][0],shellBounds[1][0]]for z in [shellBounds[0][2],shellBounds[1][2]]]
  fp.update(minX=min(p[0]for p in corners),maxX=max(p[0]for p in corners),minZ=min(p[2]for p in corners),maxZ=max(p[2]for p in corners))
 else:
  a,c=owner['old'],owner['new'];scale=owner.get('factor',1)
  fp.update(minX=c[0]+(fp['minX']-a[0])*scale,maxX=c[0]+(fp['maxX']-a[0])*scale,minZ=c[2]+(fp['minZ']-a[2])*scale,maxZ=c[2]+(fp['maxZ']-a[2])*scale)
assert len(footprints)==343
out={'schemaVersion':1,'migrationId':'CompactMap_V1','status':'PreparedAwaitingNativeFitAndImport','candidate':C,'baselineManagedContentSHA256':before['baselineManagedContentSHA256'],'sourceBundleSHA256':before['sourceBundleSHA256'],'protectedAssetsContentSHA256':before['protectedAssetsContentSHA256'],'ownership':[{'key':r['key'],'path':r['path'],'category':ownership[r['path']]}for r in rows],'operations':ops,'walls':draft['walls'],'artFootprints':footprints,'runtimeGeometryPath':str(D/'CompactBaseLayoutRuntimeGeometry.Prepared.json'),'notes':['All320scenery models includingfive landmarks have no collidable/queryable geometry or interaction descendants in captured native state; ordinarydecorative classification uses actual installed state.','External Baseplate is supportingFloor: transform actualXZedge coordinates and preserveY/flags/studs/physics.','Common owner corrections preserve useful full-size ramps and .2stud support join; actual loaded driving remains a separate acceptance gate.']}
canonical=json.dumps(out,sort_keys=True,separators=(',',':'));out['geometryPlanHash']=hashlib.sha256(canonical.encode()).hexdigest()
(D/'OwnedGeometryPlan.Prepared.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps({'planHash':out['geometryPlanHash'],'managedOwnership':len(out['ownership']),'operations':len(ops),'categories':dict(collections.Counter(x['category']for x in out['ownership'])),'footprints':len(footprints)}))
