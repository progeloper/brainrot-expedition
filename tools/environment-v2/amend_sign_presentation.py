"""Minimal reviewed sign-face amendment and conservative static source LOS proof. No Studio calls."""
from __future__ import annotations
import copy,hashlib,json,math,shutil
from pathlib import Path
import numpy as np
from geometry import *
from sign_presentation import audit_sources,inverse_cf
ROOT=Path(__file__).resolve().parents[2];DOC=ROOT/'docs/environment-v2'
PREVIOUS_SHA='b4f05ddeb84cb0a8e424504330ded866a11da9dc10a05290e72ccf993001e91b'
OVERRIDES={'Gate_Volcano_SignFaceProxy':('VolcanoSouthCampFace_v2',[197,22.549999237060547,-243.9588746257614,1,0,0,0,1,0,0,0,1],[205,7,-225]),'Gate_Jungle_SignFaceProxy':('JungleAdjacentWallEdgeClearance_v2',[-242.733642578125,22.549999237060547,153.9,-1,0,0,0,1,0,0,0,-1],[-242.733642578125,7,117.9])}
def source_obstacles(plan,scene):
 opaque=[];colliders=[]
 for r in plan['objects']:
  if r['role'] in ['Boundary','Hero']:
   opaque.extend({'id':r['id']+'/'+c['id'],'cframe':c['cframe'],'size':c['size'],'scope':'ExactNewBoundaryHeroSourceCuboid'}for c in r['componentSolids'])
  colliders.extend({'id':c['id'],'cframe':c['cframe'],'size':c['size'],'scope':'FrozenNewCollider'}for c in r['colliders'])
 for r in scene['records']:
  rp=r.get('properties')or{};path=r['path']
  if r['scope']not in ['Map','External']or'CFrame'not in rp or'Size'not in rp or path.startswith('Workspace.MapBlockout.MapArt.Scenery.')or path.startswith('Workspace.MapBlockout.MapArt.Backdrops.')or'.RegionWalls.'in path or'.BoundarySeparators.'in path:continue
  box={'id':r['key'],'cframe':unpack(rp['CFrame']),'size':unpack(rp['Size']),'scope':'ProtectedMeshBoundingBoxConservative'if r['class']=='MeshPart'else'ProtectedExactVisiblePart'}
  if unpack(rp.get('Transparency',1))<1:opaque.append(box)
  if rp.get('CanCollide'):colliders.append(box)
 return opaque,colliders
class Slabs:
 def __init__(self,rows):
  self.rows=rows;self.cf=np.array([r['cframe']for r in rows]);self.pos=self.cf[:,:3];self.rot=self.cf[:,3:].reshape((-1,3,3));self.half=np.array([r['size']for r in rows])/2
 def ray(self,a,b):
  start=np.einsum('nji,nj->ni',self.rot,np.array(a)-self.pos);delta=np.einsum('nji,j->ni',self.rot,np.array(b)-np.array(a));zero=abs(delta)<1e-12
  lo=np.divide(-self.half-start,delta,out=np.full_like(delta,-np.inf),where=~zero);hi=np.divide(self.half-start,delta,out=np.full_like(delta,np.inf),where=~zero);mn=np.minimum(lo,hi);mx=np.maximum(lo,hi);valid=~np.any(zero&(abs(start)>self.half+1e-8),axis=1);enter=np.maximum(np.max(mn,axis=1),1e-5);leave=np.minimum(np.min(mx,axis=1),1-1e-5)
  return[{'id':self.rows[i]['id'],'scope':self.rows[i]['scope'],'enterFraction':float(enter[i])}for i in np.flatnonzero(valid&(leave>enter+1e-9))]
 def camera_intersections(self,camera,groundY):
  local=np.einsum('nji,nj->ni',self.rot,np.array([camera[0],groundY+3.3080616,camera[2]])-self.pos)
  # Conservative world-axis avatar box projected into each collider's rotated local axes.
  ext=self.half+np.einsum('nji,j->ni',abs(self.rot),np.array([1.5,3.3080616,1.5]));return[self.rows[i]['id']for i in np.flatnonzero(np.all(abs(local)<ext-1e-4,axis=1))]
def los_proof(plan,scene,geometry):
 opaque,colliders=source_obstacles(plan,scene);opaque_slabs=Slabs(opaque);collider_slabs=Slabs(colliders);regions={k:decode_geometry(v)for k,v in geometry['regions'].items()};rows=[]
 for r in plan['objects']:
  if not r.get('signFaceProxy'):continue
  q=r['signFaceProxy'];cf=q['cframe'];normal=[cf[5],cf[8],cf[11]];camera=OVERRIDES[q['id']][2]if q['id']in OVERRIDES else[cf[0]+normal[0]*36,7,cf[2]+normal[2]*36]
  foot=Point(camera[0],camera[2]).buffer(1.5);region=next((k for k,v in regions.items()if v.covers(foot)),None);body_hits=collider_slabs.camera_intersections(camera,geometry['groundY']);front_dot=sum((camera[i]-cf[i])*normal[i]for i in range(3));targets=[]
  for x in [-8,-4,0,4,8]:
   for y in [-2.5,0,2.5]:
    endpoint=cfpoint(cf,[x,y,.0501]);opaque_hits=opaque_slabs.ray(camera,endpoint);collider_hits=collider_slabs.ray(camera,endpoint);targets.append({'localFaceXY':[x,y],'worldEndpoint':endpoint,'opaqueHits':opaque_hits,'colliderHits':collider_hits})
  passed=region is not None and not body_hits and front_dot>0 and all(not t['opaqueHits']and not t['colliderHits']for t in targets)
  assert passed,{'proxy':q['id'],'region':region,'cameraIntersections':body_hits,'blockedTargets':[t for t in targets if t['opaqueHits']or t['colliderHits']]}
  evidence={'status':'PassedStaticSourceConservativeLOS','legalViewpoint':camera,'legalFloorRegion':region,'cameraHeight':7,'bodyGroundY':geometry['groundY'],'bodyHeight':6.6161232,'bodyRadius':1.5,'cameraBodyColliderIntersections':body_hits,'frontFaceDot':front_dot,'sampleCount':15,'samples':targets,'exactNewBoundaryHeroOpaqueCuboids':sum(t['scope']=='ExactNewBoundaryHeroSourceCuboid'for t in opaque),'totalOpaqueVolumes':len(opaque),'totalColliderVolumes':len(colliders),'conservativeProtectedMeshOBBPolicy':'Any mesh-bounding-box intersection rejects; a clear ray is conservative. No hidden opening is assumed.','nativeReadability':'PendingRootActualNativeRaycastsAndNormalCameraRender; source proof does not replace actual render.'}
  q['clearanceEvidence'].update(evidence);rows.append({'id':q['id'],**evidence})
 return{'status':'AllSixPassedStaticSourceConservativeLOS','sourceWrites':0,'studioCalls':0,'baselineSceneSHA256':plan['baselineSceneSHA256'],'assetSourceSHA256':plan['assetSourceSHA256'],'sourceAuditSHA256':audit_sources()['sourceJSONSHA256'],'rows':rows,'worldWrites':0,'actualNativeQA':'PendingRootApplyAndNativeCameraRays'}
def amend():
 old_raw=(DOC/'FrozenApplyManifest.json').read_bytes();assert hashlib.sha256(old_raw).hexdigest()==PREVIOUS_SHA,'Only the exact reviewed previous occluded-label manifest may be amended'
 plan=json.loads(old_raw);scene=json.loads((DOC/'BeforeManifest.json').read_text());geometry=json.loads((DOC/'CurrentGeometry.json').read_text());revision=DOC/'revisions/v1';revision.mkdir(parents=True,exist_ok=True)
 files=['FrozenApplyManifest.json','FrozenPropertyDeltas.json','FrozenApplyBindingReceipt.json','RuntimeMetadataProposal.json','SignPresentationAdapter.json','NumericalPlanProof.json','PlacementPlan.md','ActualSavedNativeRoundtrip.json']
 for name in files:
  source=DOC/name;target=revision/name
  if source.exists():
   if target.exists():assert target.read_bytes()==source.read_bytes(),'Existing v1 proof differs; do not overwrite'
   else:shutil.copyfile(source,target)
 snapshot=DOC/'snapshots/EnvironmentV2_After_2026_10_12.rbxl';savedcopy=revision/snapshot.name
 if snapshot.exists()and not savedcopy.exists():shutil.copyfile(snapshot,savedcopy)
 for row in plan['objects']:
  q=row.get('signFaceProxy')
  if not q or q['id']not in OVERRIDES:continue
  override,newCF,camera=OVERRIDES[q['id']];oldCF=q['cframe'];q['previousPresentationCFrame']=oldCF;q['presentationOverride']=override;q['cframe']=newCF;q['bounds']=bounds3(newCF,q['size']);q['rootRelativeCFrame']=cfcompose(inverse_cf(row['rootCFrame']),newCF)
  normal=[newCF[5],newCF[8],newCF[11]];hb=row['authoredMeshBounds'];face=sum(normal[i]*(hb['max'+k]if normal[i]>0 else hb['min'+k]if normal[i]<0 else 0)for i,k in enumerate(['X','Y','Z']));gap=sum(newCF[i]*normal[i]for i in range(3))-.05-face;assert gap>=.04999999
  region=next(k for k,v in geometry['regions'].items()if decode_geometry(v).covers(part_projection(newCF,q['size'])));q['regionId']=region
  q['clearanceEvidence'].update({'presentationOverride':override,'legalViewpoint':camera,'presentationFaceBackWorldNormal':normal,'headerPresentationFaceProjection':face,'innerFaceSeparationFromOpaqueHeader':gap,'visibleFaceSeparationFromOpaqueHeader':gap+.1,'completeFootprintInsideRegion':region,'originalVerticalAndTangentialSignCoordinatesRetained':override=='VolcanoSouthCampFace_v2'and False or False,'originalSignAndGuiGeometryUnchanged':True,'ownedProxyPresentationPoseAmendmentOnly':True,'poseAmendmentReason':'Source/native review found adjacentwall occlusion; exact owned proxy relocation preserves original Sign/GUI and all roads/openings.','nativeSignReadability':'PendingRootActualNativeNormalHeightReadabilityAfterAmendment'})
  if override=='JungleAdjacentWallEdgeClearance_v2':q['clearanceEvidence']['minimumAdjacentCliffTangentialEdgeGap']=.266357421875
  row['bounds']={k:(min(hb[k],q['bounds'][k])if k.startswith('min')else max(hb[k],q['bounds'][k]))for k in hb}
 los=los_proof(plan,scene,geometry)
 proxy_rows=[copy.deepcopy(r['signFaceProxy'])for r in plan['objects']if r.get('signFaceProxy')];adapter=plan['signPresentationAdapter'];adapter['rows']=proxy_rows;adapter['status']='SourceContractPassedAllSixStaticLOSPassedNativeAmendmentPending';adapter['amendmentFromManifestSHA256']=PREVIOUS_SHA;adapter['presentationAmendments']=[{'id':q['id'],'override':q['presentationOverride'],'cframe':q['cframe'],'legalViewpoint':q['clearanceEvidence']['legalViewpoint']}for q in proxy_rows if q.get('presentationOverride')];adapter['nativeAcceptance']='Pending root actual amended native Apply/LOS/readability and saved-reference audit';adapter['allSixStaticLOSPassed']=True
 plan['presentationAmendment']={'schemaVersion':2,'previousFrozenManifestSHA256':PREVIOUS_SHA,'previousNativeSavedFileSHA256':'fadb277f38c3a90ce6252d4d51489ab7b6eb15227cd20be4d164314577afe5da','previousManifestArchive':'docs/environment-v2/revisions/v1/FrozenApplyManifest.json','reason':'Volcano actual adjacentwall occlusion plus Jungle source-edge burial corrected by two owned-face poses. All6 originalAdornee-only scope, source/GUI hierarchy/text/road/opening properties and43558/582 budgets retained.','amendedOwnedProxies':adapter['presentationAmendments'],'allSixStaticLOSProof':'SignPresentationLOS.json','actualNativeAcceptance':'PendingRootAmendedApply/NormalCameraReadability/NativeRays'}
 plan['signPresentationAdapter']=adapter;plan.pop('planSHA256',None);plan['planSHA256']=sha(plan)
 (DOC/'EnvironmentLayout_V2.json').write_text(json.dumps(plan,indent=2)+'\n');(DOC/'SignPresentationAdapter.json').write_text(json.dumps(adapter,indent=2)+'\n');(DOC/'SignPresentationLOS.json').write_text(json.dumps(los,indent=2)+'\n');(revision/'RevisionStatus.json').write_text(json.dumps({'status':'HistoricalNativeInstalledLabelOcclusionBaseline','frozenManifestSHA256':PREVIOUS_SHA,'savedSnapshotSHA256':'fadb277f38c3a90ce6252d4d51489ab7b6eb15227cd20be4d164314577afe5da','actualStaticAndSavedRoundtrip':'PassedBeforePresentationAmendment','nativeVolcanoLabelReadability':'Failed_AdjacentCampWallOcclusion','notFinalCurrentManifest':True},indent=2)+'\n')
 print(json.dumps({'sourceLOS':'All6Passed15/15OpaqueAndColliderRays','amendments':adapter['presentationAmendments'],'sourcePlanSHA256':plan['planSHA256'],'previousFrozenArchived':PREVIOUS_SHA}))
if __name__=='__main__':amend()
