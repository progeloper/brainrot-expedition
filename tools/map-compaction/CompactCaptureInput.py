#!/usr/bin/env python3
"""Flatten complete captured evidence; numeric planning is executed in Luau.
Read only. This does not recapture Studio or grant apply eligibility.
"""
import hashlib,json
from pathlib import Path
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
OUTPUT=Path(__file__).with_name('CompactBaselineInput.json')
def read(rel):
 p=ROOT/rel;raw=p.read_bytes();return json.loads(raw),hashlib.sha256(raw).hexdigest()
manifest,manifest_sha=read('docs/map-compaction/BeforeManifest.json')
routes,routes_sha=read('docs/map-art/OriginalRouteSnapshot.json')
oldgates,gate_sha=read('docs/map-art/RouteGateAnchors.json')
narrow,narrow_sha=read('assets/map-art/routes/NarrowedRouteManifest.json')
objects={x['path']:x for x in manifest['objects']}
def val(row,k):
 v=row['properties'][k];return v.get('value') if isinstance(v,dict) and 'value' in v else v
regions={'Camp':'REGION_CAMP','Forest':'REGION_FOREST','Beach':'REGION_BEACH','Swamp':'REGION_SWAMP','Jungle':'REGION_JUNGLE','Arctic':'REGION_ARCTIC','Volcano':'REGION_VOLCANO','Glitch Zone':'REGION_GLITCH'}
floors=[];legacy=[];actual_routes=[]
for x in manifest['objects']:
 a=x['attributes'] if isinstance(x['attributes'],dict) else {}
 if a.get('LayoutRole')=='Floor' and '.Floor_R' in x['path']:
  cf,size=val(x,'CFrame'),val(x,'Size');region=regions[x['path'].split('.')[2]]
  assert cf[3:]==[1,0,0,0,1,0,0,0,1]
  floors.append({'id':x['key'],'path':x['path'],'regionId':region,'cframe':cf,'size':size,'x0':cf[0]-size[0]/2,'x1':cf[0]+size[0]/2,'z0':cf[2]-size[2]/2,'z1':cf[2]+size[2]/2,'y':cf[1],'thickness':size[1],'ground':cf[1]+size[1]/2})
 if a.get('ManagedBy')=='Phase8Perimeter_v1' and x['class'] in ['Part','MeshPart']:
  legacy.append({'id':x['key'],'path':x['path'],'regionId':a['RegionId'],'axis':a['PerimeterAxis'],'fixed':a['PerimeterFixed'],'first':a['PerimeterFirst'],'last':a['PerimeterLast'],'cframe':val(x,'CFrame'),'size':val(x,'Size'),'flags':{k:val(x,k) for k in ['Anchored','CanCollide','CanQuery','CanTouch','CastShadow','CollisionGroup']}})
 if a.get('ArtRole')=='Path' and x['class']=='MeshPart': actual_routes.append({'key':x['key'],'path':x['path'],'attributes':a,'mesh':x.get('mesh'), 'meshId':x.get('mesh',{}).get('MeshId'),'cframe':val(x,'CFrame'),'size':val(x,'Size')})
gates=[]
pairs={'Beach':['REGION_BEACH','REGION_FOREST'],'Swamp':['REGION_FOREST','REGION_SWAMP'],'Jungle':['REGION_CAMP','REGION_JUNGLE'],'Arctic':['REGION_ARCTIC','REGION_FOREST'],'Volcano':['REGION_CAMP','REGION_VOLCANO'],'GlitchZone':['REGION_GLITCH','REGION_JUNGLE']}
for old in oldgates:
 path='Workspace.MapBlockout.ProgressionGates.'+old['name']
 row={'name':old['name'],'normal':old['normal'],'regionPair':pairs[old['name']],'bindings':{}}
 for key,name in [('thresholdCFrame','Threshold'),('safeCartCFrame','SafeCartExterior'),('safeCharacterCFrame','SafeCharacterExterior'),('interactionCFrame','InteractionAnchor')]:
  part=objects[path+'.'+name];row[key]=val(part,'CFrame');row['bindings'][key]={'key':part['key'],'path':part['path'],'size':val(part,'Size')}
 row['ground']=[row['thresholdCFrame'][0],floors[0]['ground'],row['thresholdCFrame'][2]]
 assert all(abs(a-b)<.01 for a,b in zip(row['ground'],old['ground'])),(old['name'],row['ground'],old['ground'])
 gates.append(row)
assert len(floors)==25 and len(legacy)==41
assert len(routes['routes'])==85 and len(narrow['connectivityCaps'])==26
assert len(actual_routes)==27,len(actual_routes)
assert {x['attributes']['RouteHash'] for x in actual_routes}=={routes['routePointsCanonicalSHA256']}
road_binding_sha=hashlib.sha256(json.dumps(actual_routes,sort_keys=True,separators=(',',':')).encode()).hexdigest()
output={'actualRoadBindingsSHA256':road_binding_sha,'schemaVersion':1,'migrationId':'CompactMap_V1','applyEligible':False,'baselineManagedContentSHA256':manifest['baselineManagedContentSHA256'],'beforeManifestSHA256':manifest_sha,'capturedAtUTC':manifest['capturedAtUTC'],'placeId':manifest['placeId'],'universeId':manifest['universeId'],'sourceBundleSHA256':manifest['sourceBundleSHA256'],'sourceLayoutVersion':objects['Workspace.MapBlockout']['attributes']['LayoutVersion'],'routePointsCanonicalSHA256':routes['routePointsCanonicalSHA256'],'sourceEvidence':{'routeSnapshotSHA256':routes_sha,'routeGateAnchorsSHA256':gate_sha,'installedRouteManifestSHA256':narrow_sha,'routeSource':routes['sourceFile'],'routeSourceSHA256':routes['sourceSHA256'],'sourceLiveSymmetricDifferenceArea':routes['sourceLiveSymmetricDifferenceArea']},'floors':floors,'legacySeparators':legacy,'routes':routes['routes'],'gates':gates,'gateRouteOwners':narrow['gateAprons'],'connectivityCaps':narrow['connectivityCaps'],'actualRoads':actual_routes,'collisionMatrix':manifest['collisionMatrix'],'fitStatus':'NotRun','policy':'Immutable fresh geometry bindings plus independently reconstructed full original route graph; candidate selection/apply requires all measured fit rows and runtime proof.'}
OUTPUT.write_text(json.dumps(output,indent=2,sort_keys=True)+'\n')
print(json.dumps({'path':str(OUTPUT),'floors':len(floors),'legacySeparators':len(legacy),'routes':len(routes['routes']),'actualRoads':len(actual_routes),'gates':len(gates),'baselineManagedContentSHA256':manifest['baselineManagedContentSHA256']}))
