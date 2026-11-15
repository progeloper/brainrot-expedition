#!/usr/bin/env python3
"""Derive candidate coordinate metadata and runtime wall rows from immutable numeric inputs.
No Studio/source edits. RuntimeValidated remains false until the native world transaction verifies it.
"""
from pathlib import Path
import argparse,json,hashlib,math
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/map-compaction'
REGIONS={'REGION_CAMP':'Camp','REGION_FOREST':'Forest','REGION_BEACH':'Beach','REGION_SWAMP':'Swamp','REGION_JUNGLE':'Jungle','REGION_ARCTIC':'Arctic','REGION_VOLCANO':'Volcano','REGION_GLITCH':'Glitch Zone'}
SOURCE_KNOTS=[0,136,313,420,432]
def canonical(x):return json.dumps(x,sort_keys=True,separators=(',',':'),allow_nan=False)
def sha(x):return hashlib.sha256(x).hexdigest()
def axis(value,c):
 sign=-1 if value<0 else 1;a=abs(value);target=[0,c['t'],c['r'],c['h']-12,c['h']]
 if a>=432:return sign*(c['h']+(a-432)*c['outer'])
 for i in range(4):
  if a<=SOURCE_KNOTS[i+1]:return sign*(target[i]+(a-SOURCE_KNOTS[i])*(target[i+1]-target[i])/(SOURCE_KNOTS[i+1]-SOURCE_KNOTS[i]))
 raise AssertionError(value)
def union_area(rows):
 xs=sorted({v for r in rows for v in [r['x0'],r['x1']]});area=0
 for a,b in zip(xs,xs[1:]):
  intervals=sorted((r['z0'],r['z1'])for r in rows if r['x0']<b and r['x1']>a);length=0;lo=hi=None
  for z0,z1 in intervals:
   if lo is None:lo,hi=z0,z1
   elif z0<=hi:hi=max(hi,z1)
   else:length+=hi-lo;lo,hi=z0,z1
  if lo is not None:length+=hi-lo
  area+=(b-a)*length
 return area
def wall_obstacles(draft):
 rows=[]
 for row in draft['walls']+draft['retainedOuterContainment']:
  cf=row['cframe'];size=row['size'];assert len(cf)==12 and len(size)==3
  extents=[sum(abs(cf[3+axis*3+j])*size[j]/2 for j in range(3))for axis in range(3)]
  for v in cf+size:assert math.isfinite(v)
  if 'regionPair' in row:id=row['id']
  else:id='EXISTING_'+row['path'].split('ProgressionGates.',1)[1].replace('.BoundarySeparators.','_')
  assert len(id)<=128
  rows.append({'id':id,'minX':cf[0]-extents[0],'maxX':cf[0]+extents[0],'minY':cf[1]-extents[1],'maxY':cf[1]+extents[1],'minZ':cf[2]-extents[2],'maxZ':cf[2]+extents[2]})
 assert len({r['id']for r in rows})==len(rows)
 return sorted(rows,key=lambda r:r['id'])
def build(draft_path,base_path,out):
 before=json.loads((DOC/'BeforeManifest.json').read_text());draft=json.loads(draft_path.read_text());bases=json.loads(base_path.read_text())
 assert draft['baselineManagedContentSHA256']==before['baselineManagedContentSHA256']
 assert draft['sourceBundleSHA256']==before['sourceBundleSHA256']
 assert bases['runtimeValidated']is False,'Do not overwrite already validated runtime evidence'
 c=draft['candidate']
 for id,row in bases['bases'].items():
  assert abs(row['perimeter']['postWidth']-.625*c['b'])<=1e-6 and abs(row['perimeter']['postDepth']-.625*c['b'])<=1e-6,('candidate/base factor mismatch',id,c['b'])
 objects={r['key']:r for r in before['objects']};paths={r['path']:r for r in before['objects']}
 origin=[paths['Workspace.MapBlockout']['attributes']['OriginX'],paths['Workspace.MapBlockout']['attributes']['OriginZ']]
 assert c['origin'][0]==origin[0] and c['origin'][2]==origin[1]
 for r in draft['floors']:
  original=objects[r['id']];frame=original['properties']['CFrame']['value'];size=original['properties']['Size']['value']
  assert all(abs(frame[3+i]-([1,0,0,0,1,0,0,0,1][i]))<1e-6 for i in range(9))
  expected=[origin[0]+axis(frame[0]-size[0]/2-origin[0],c),origin[0]+axis(frame[0]+size[0]/2-origin[0],c),origin[1]+axis(frame[2]-size[2]/2-origin[1],c),origin[1]+axis(frame[2]+size[2]/2-origin[1],c)]
  assert max(abs(a-b)for a,b in zip(expected,[r['x0'],r['x1'],r['z0'],r['z1']]))<=1e-6
 updates=[]
 def add(path,attrs,removed,reason):
  row=paths[path];old=row['attributes'];assert isinstance(old,dict)
  updates.append({'key':row['key'],'path':path,'class':row['class'],'before':{k:old.get(k)for k in sorted(set(attrs)|set(removed))},'after':attrs,'remove':removed,'reason':reason})
 old=paths['Workspace.MapBlockout']['attributes'];attrs={'CampWidth':2*c['h'],'CampDepth':2*c['h'],'GridXEdges':canonical([axis(v,c)for v in json.loads(old['GridXEdges'])]),'GridZEdges':canonical([axis(v,c)for v in json.loads(old['GridZEdges'])])}
 add('Workspace.MapBlockout',attrs,[],'Origin-relative knot mapping; preserve origin/Y/thickness and OriginalCell dimensions.')
 regions=[]
 for rid,name in REGIONS.items():
  rows=[r for r in draft['floors']if r['regionId']==rid];assert rows
  area=union_area(rows);assert abs(area-draft['targetRegionAreas'][rid])<=1e-6
  a={'BoundsMin':{'type':'Vector3','value':[min(r['x0']for r in rows)-origin[0],0,min(r['z0']for r in rows)-origin[1]]},'BoundsMax':{'type':'Vector3','value':[max(r['x1']for r in rows)-origin[0],0,max(r['z1']for r in rows)-origin[1]]},'NavigableFloorArea':area};removed=[]
  path='Workspace.MapBlockout.'+name;original=paths[path]['attributes'];clearings=[]
  if 'HuntingClearings'in original:
   size=original['ClearingSize'];centres=json.loads(original['HuntingClearings']);mapped=[]
   for i,(x,z)in enumerate(centres,1):
    marker=[axis(x,c),axis(z,c)];x0,x1=axis(x-size/2,c),axis(x+size/2,c);z0,z1=axis(z-size/2,c),axis(z+size/2,c)
    mapped.append(marker);clearings.append({'id':f'C{i:02d}','marker':marker,'boundsMin':[x0,z0],'boundsMax':[x1,z1],'width':x1-x0,'depth':z1-z0})
   a['HuntingClearings']=canonical(mapped);a['OriginalClearingSize']=size;a['CompactClearingRectanglesLocal']=canonical(clearings)
   dims={round(v,8)for r in clearings for v in [r['width'],r['depth']]}
   if len(dims)==1:a['ClearingSize']=clearings[0]['width']
   else:removed.append('ClearingSize')
  add(path,a,removed,'Bounds are display metadata; runtime remains on real floor unions. Clearing rectangles are exact transformed local bounds, not one invented isotropic scalar.')
  regions.append({'regionId':rid,'folder':name,'floorParts':len(rows),'unionArea':area,'clearings':len(clearings),'boundsOriginRelative':{'min':a['BoundsMin']['value'],'max':a['BoundsMax']['value']}})
 a={'PathWidth':28,'SpineWidth':28,'SecondaryWidth':24,'CampLoopWidth':36,'JunctionSize':44,'PathPadSize':64,'BorderWidth':0,'OriginalBorderWidth':paths['Workspace.MapBlockout.Paths']['attributes']['BorderWidth']}
 add('Workspace.MapBlockout.Paths',a,[],'Publish canonical constant-width road metadata; removed old decorative borders are not generated by future compact tools.')
 services={}
 for name in ['AnnouncementStall','BrainrotTrainStall','BuyCartStall','KitStall','SellStall','WeaponHarpoonStall']:
  path='Workspace.MapBlockout.ServiceStallPatches.'+name;row=paths[path];size=row['properties']['Size']['value']
  assert size==([64,1,40]if name=='BuyCartStall'else[56,1,32])
  services[name]={'logicalInteractionEnvelope':size}
  a={'LogicalInteractionEnvelope':{'type':'Vector3','value':size}}
  original=row['attributes'];centre=original['WaitingAreaCentre']['value'];width,depth=original['WaitingAreaSize']['value']
  a['WaitingAreaCentre']={'type':'Vector3','value':[axis(centre[0],c),centre[1],axis(centre[2],c)]}
  a['WaitingAreaSize']={'type':'Vector2','value':[axis(centre[0]+width/2,c)-axis(centre[0]-width/2,c),axis(centre[2]+depth/2,c)-axis(centre[2]-depth/2,c)]}
  add(path,a,[],'Retain captured logical interaction size independently of compact support; transform original origin-relative waiting-area metadata. Sale/upgrade owner distance rules remain exact.')
 assert bases.get('services')==services,'Owner Prepared services disagree with captured logical sizes'
 walls=wall_obstacles(draft);runtime={**bases,'runtimeValidated':False,'services':services,'staticWallObstacles':walls}
 runtime['planHash']='0'*64
 runtime_text=canonical(runtime);assert len(runtime_text.encode())<=200000
 report={'schemaVersion':1,'migrationId':'CompactMap_V1','status':'CandidateMetadataPrepared','selectedCandidate':None,'applyAllowed':False,'candidate':c,'baselineManagedContentSHA256':before['baselineManagedContentSHA256'],'sourceBundleSHA256':before['sourceBundleSHA256'],'numericDraftSHA256':sha(draft_path.read_bytes()),'baseInputSHA256':sha(base_path.read_bytes()),'runtimeValidated':False,'finalPlanHash':'PendingRootCanonicalBinding','preserved':['map origin/Y/floor thickness','OriginalCell and OriginalFootprint reference dimensions','author identities','floor-instance names and source tags','live floor-union ownership','343 art-footprint schema','all actor/economy/physics rules'],'updates':updates,'regions':regions,'staticWallMask':{'newWalls':len(draft['walls']),'retainedOuter':len(draft['retainedOuterContainment']),'rows':len(walls),'artFootprintRowsRemain':343},'runtimePrepared':{'file':'CompactRuntimeGeometry.Prepared.json','bytes':len(runtime_text.encode()),'planHashPlaceholder':'0'*64,'note':'Root must bind the final reviewed plan hash and set runtimeValidated only after actual native owner/static proof. Publishing this draft as Completed is forbidden.'}}
 out.mkdir(parents=True,exist_ok=True);(out/'CompactMetadataPatch.Prepared.json').write_text(json.dumps(report,indent=2)+'\n');(out/'CompactRuntimeGeometry.Prepared.json').write_text(runtime_text+'\n')
 print(json.dumps({'metadataOwners':len(updates),'floorRegions':len(regions),'wallMaskRows':len(walls),'runtimeBytes':len(runtime_text.encode()),'runtimeValidated':False}))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--draft',type=Path,default=ROOT/'tools/map-compaction/CompactDraft_b085.json');p.add_argument('--bases',type=Path,default=DOC/'CompactBaseLayoutRuntimeGeometry.Prepared.json');p.add_argument('--out',type=Path,default=DOC/'source-patches/metadata');a=p.parse_args();build(a.draft,a.bases,a.out)
