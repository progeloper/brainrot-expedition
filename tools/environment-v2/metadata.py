"""Metadata-only proposals for existing owners. Does not edit scripts or Studio."""
import json,hashlib,copy,math
from pathlib import Path
from geometry import *
ROOT=Path(__file__).resolve().parents[2]
PATH_RGB={'REGION_CAMP':[207,175,120],'REGION_FOREST':[179,148,96],'REGION_BEACH':[227,187,109],'REGION_SWAMP':[134,133,96],'REGION_JUNGLE':[175,147,97],'REGION_ARCTIC':[151,194,219],'REGION_VOLCANO':[105,87,100],'REGION_GLITCH':[113,103,161]}
def proposals(plan,scene,assets):
 rows=scene['records'];bykey={r['key']:r for r in rows};foot=next(r for r in rows if r['path']=='Workspace.MapBlockout.MapArt.InstalledFootprints');runtime=next(r for r in rows if r['path']=='Workspace.MapBlockout.CompactMapRuntimeGeometry');originalFoot=json.loads(foot['properties']['Value']);remove={bykey[r['originalKey']]['name']for r in plan['archive']};keep=[r for r in originalFoot if r['id']not in remove];assert len(keep)==18
 newfoot=copy.deepcopy(keep)
 for o in plan['objects']:
  if o['role']=='Boundary':continue
  b=o['bounds'];newfoot.append({'id':o['id'],'regionId':o['regionId'],'minX':b['minX'],'maxX':b['maxX'],'minZ':b['minZ'],'maxZ':b['maxZ']})
 newfoot.sort(key=lambda r:r['id']);assert len(newfoot)<=345 and len(set(r['id']for r in newfoot))==len(newfoot)
 raw=json.loads(runtime['properties']['Value']);assert raw['schemaVersion']==1 and raw['migrationId']=='CompactMap_V1'and raw['planHash']==plan['compactPlanHash']and raw['runtimeValidated']
 proposed=copy.deepcopy(raw);mask=[]
 for o in plan['objects']:
  for c in o['colliders']:
   r={k:c[k]for k in ['id','minX','maxX','minY','maxY','minZ','maxZ']};assert len(r['id'])<=128 and all(math.isfinite(r[k])for k in r if k!='id');assert r['minX']<r['maxX']and r['minY']<r['maxY']and r['minZ']<r['maxZ'];mask.append(r)
 # If perimeter reuse is selected, preserve those original actual collider masks, never remove their query obstacle.
 for r in plan.get('retainedOuter',[]):
  mask.append({'id':'EV2_RetainedOuter_'+str(len(mask)),**bounds3(r['cframe'],r['size'])})
 mask.sort(key=lambda r:r['id']);assert len(mask)<=512 and len(set(r['id']for r in mask))==len(mask);proposed['staticWallObstacles']=mask
 assert proposed['bases']==raw['bases']and proposed['services']==raw['services']and proposed['planHash']==raw['planHash']
 floorIDs={r['id']:r['regionId']for r in json.loads((ROOT/'docs/environment-v2/CurrentGeometry.json').read_text())['floors']};paletteNames={v:k for k,v in NAMES.items()if k not in ['Glitch','GlitchZone']};colors=[]
 for r in rows:
  if r['key']in floorIDs:
   rgb=assets['palettes'][paletteNames[floorIDs[r['key']]]]['Ground'];kind='ExistingFloorRegionalAlbedo'
  elif r['path'].startswith('Workspace.MapBlockout.Paths.StyledSurfaces.')and r['class']=='MeshPart':
   rgb=PATH_RGB[NAMES[r['attributes']['Region']]];kind='ExistingDecorativePathRegionalAlbedo'
  else:continue
  colors.append({'originalKey':r['key'],'path':r['path'],'property':'Color','oldValue':r['properties']['Color'],'newRGB':rgb,'newValue':{'type':'Color3','value':[v/255 for v in rgb]},'scope':kind,'allOtherPropertiesRetained':True})
 assert len(colors)==52
 footText=canonical(newfoot);runtimeText=canonical(proposed);assert len(footText.encode())<=262144 and len(runtimeText.encode())<=200000
 changes=[{'originalKey':foot['key'],'path':foot['path'],'property':'Value','previousSHA256':hashlib.sha256(foot['properties']['Value'].encode()).hexdigest(),'nextSHA256':hashlib.sha256(footText.encode()).hexdigest(),'newValue':footText,'records':len(newfoot),'preservedOriginalRecords':18,'loaderMaximumRecords':345,'loaderMaximumBytes':262144,'bytes':len(footText.encode())},{'originalKey':runtime['key'],'path':runtime['path'],'property':'Value','previousSHA256':hashlib.sha256(runtime['properties']['Value'].encode()).hexdigest(),'nextSHA256':hashlib.sha256(runtimeText.encode()).hexdigest(),'newValue':runtimeText,'records':len(mask),'loaderMaximumRecords':512,'loaderMaximumBytes':200000,'bytes':len(runtimeText.encode())}]
 return{'schemaVersion':2,'baselineSceneSHA256':plan['baselineSceneSHA256'],'environmentPlanSHA256':plan['planSHA256'],'sourceWrites':0,'worldWrites':0,'changes':changes,'footprintRows':newfoot,'staticCollisionMasks':mask,'appearanceEdits':colors,'ownedInstancePropertyChanges':plan.get('signPresentationAdapter',{}).get('originalPropertyChanges',{}),'originalGuiAdorneeEdits':[r['adorneeChange']for r in plan.get('signPresentationAdapter',{}).get('rows',[])],'signSourceContractAudit':plan.get('signPresentationAdapter',{}).get('sourceAudit'),'boundaryFootprintMetadataPolicy':'Header/SignFace proxies are not 2D spawnfootprint rows; all actualheadercolliders are global3Dstaticmasks. Proxies are20studs aboveground andnoncolliding/nonquery, so addno3Dmask oropen-ground obstruction. Headerwhole-renderbounds includeproxy fornativeBoundsverification.','attributeProposals':[{'path':p,'attributes':{'EnvironmentV2Owner':'BR_EnvironmentArt_V2','EnvironmentV2Hash':plan['planSHA256'],'EnvironmentV2Status':'Completed'}}for p in ['Workspace.MapBlockout','Workspace.MapBlockout.MapArt']],'cacheSafety':'Install only in Edit. Both existing owners cache geometry at first load; start a new Play session after exact Value rebinding. Do not change geometry mid-session.','retainedCompactMapContract':{'planHash':raw['planHash'],'basesEqual':True,'servicesEqual':True,'schemaVersion':raw['schemaVersion'],'runtimeValidated':True},'nativeCollisionProof':'Pending actual new collider readback; these are exact source-planned AABBs, not a claimed native raycast pass.'}
if __name__=='__main__':
 plan=json.loads((ROOT/'docs/environment-v2/EnvironmentLayout_V2.json').read_text());scene=json.loads((ROOT/'docs/environment-v2/BeforeManifest.json').read_text());assets=json.loads((ROOT/'assets/environment-v2/EnvironmentAssetSource.json').read_text());assert plan['assetSourceSHA256']==assets['sourceSHA256'];result=proposals(plan,scene,assets);out=ROOT/'docs/environment-v2/RuntimeMetadataProposal.json';out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'sourceWrites':0,'metadataChanges':len(result['changes']),'appearanceEdits':len(result['appearanceEdits']),'counts':[{'path':r['path'],'records':r['records'],'bytes':r['bytes']}for r in result['changes']]}))
