"""Bind complete actual native corner evidence to the frozen desired schedule. No Studio writes."""
from __future__ import annotations
import argparse,copy,hashlib,json,re
from pathlib import Path
from geometry import canonical,sha
from metadata import proposals
ROOT=Path(__file__).resolve().parents[2]
SCENE_SHA='f396b10caf4d1ab7e6b9aa8dd61fcab89bc904f33d95c899de887ac9950089e9'
ASSET_SHA='f9e940205f6c35805cff5674ef0079347090d4a8a431b02dbef457b3aba05dec'
IDENTITY=[1,0,0,0,1,0,0,0,1]
def read(path):return json.loads((ROOT/path).read_text())
def raw_sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
def write(path,value,minified=False):
 text=(canonical(value) if minified else json.dumps(value,indent=2,allow_nan=False))+'\n';(ROOT/path).write_text(text);return hashlib.sha256(text.encode()).hexdigest()
def bind(proof,asset_manifest,plan,proof_file_sha):
 assert plan['baselineSceneSHA256']==SCENE_SHA and plan['assetSourceSHA256']==ASSET_SHA and plan['purePlanEligible'] and not plan['conflicts']
 assert proof['status']=='Passed'and proof['completeBatch']and proof['sourceSHA256']==ASSET_SHA and proof['checkedGroups']==34 and proof['checkedTriangleCorners']==21258 and proof['actualNativeTriangles']==7086 and not proof['failures']
 assert asset_manifest['sourceSHA256']==ASSET_SHA
 units={r['id']:r for r in asset_manifest['meshGroups']};assert len(units)==34
 normalized=copy.deepcopy(proof);normalized['passed']=True;normalized['originalActualProofFileSHA256']=proof_file_sha
 expected={};seen=set()
 for g in normalized['groups']:
  u=units[g['id']];key=g['prototypeId']+'/'+g['groupId'];assert key not in expected and g['meshId']not in seen
  assert re.fullmatch(r'rbxassetid://[1-9][0-9]*',g['meshId']);seen.add(g['meshId'])
  assert g['prototypeId']==u['prototypeId'] and g['groupId']==u['groupId'] and g['passed']and g['geometryCornersComplete']and g['sourceWindingPassed']and g['hardNormalsPassed']and g['flatFacetNormalsPassed']and g['repeatingSavedMaterialUVPassed']and g['identityPartRotation']and not g['failures']
  assert g['actualTriangles']==g['expectedTriangles']==u['triangles']and g['checkedCorners']==g['geometryCornersMatched']==3*u['triangles']
  assert g['maximumPositionError']<=proof['positionToleranceStuds']and g['maximumUVError']<=proof['UVTolerance']and g['maximumNormalError']<=proof['normalTolerance']and g['maximumNormalAngleErrorDegrees']<=proof['normalAngleToleranceDegrees']and g['maximumWithinFaceNormalSpread']<=proof['withinFaceNormalSpreadTolerance']
  assert max(abs(a-b)for a,b in zip(g['canonicalCentre'],u['centre']))<1e-8
  assert max(abs(a-b)for a,b in zip(g['sizeXYZ'],u['size']))<1e-8
  g['exportGroup']=g['groupId'];g['complete']=True
  expected[key]={'prototypeId':g['prototypeId'],'exportGroup':g['groupId'],'meshId':g['meshId'],'localCFrame':u['centre']+IDENTITY,'size':u['size'],'triangles':u['triangles'],'sourceSHA256':ASSET_SHA,'actualNativeProofId':g['id'],'canonicalUnitFrameBasis':'Authored group centre and identity rotation; actual imported geometry every corner verified. Root normalizes unit templates in ServerStorage before Apply preflight.'}
 assert len(expected)==34 and sum(g['actualTriangles']for g in normalized['groups'])==7086
 mesh_count=0;primitive_count=0
 per_row=[]
 for row in plan['objects']:
  n=0
  for g in row['meshGroups']:
   k=g.get('prototypeId',row['prototypeId'])+'/'+g.get('exportGroup',g.get('groupId'));unit=expected[k];g.update({'exportGroup':unit['exportGroup'],'meshId':unit['meshId'],'nativeTriangles':unit['triangles'],'nativeGeometryVerified':True,'sourceSHA256':ASSET_SHA});n+=unit['triangles']
  extra=row.get('signFaceProxy',{}).get('sourceTriangles',0);assert extra in [0,12]
  assert n==row.get('expectedMeshExportTriangles',row['expectedExportTriangles']-extra) and n+extra==row['expectedExportTriangles'],row['id']
  row['expectedNativeMeshTriangles']=n;row['expectedNativeAndPrimitiveTriangles']=n+extra
  mesh_count+=n;primitive_count+=extra;per_row.append({'id':row['id'],'role':row['role'],'nativeMeshTriangles':n,'primitiveTriangles':extra,'totalTriangles':n+extra})
 assert mesh_count==43486 and primitive_count==72 and mesh_count+primitive_count==43558
 for row in plan['unplacedMandatoryObjects']:
  assert row['install']is False
  for g in row['meshGroups']:
   u=expected[g['prototypeId']+'/'+g['groupId']];g.update({'meshId':u['meshId'],'nativeTriangles':u['triangles'],'nativeGeometryVerified':True,'sourceSHA256':ASSET_SHA})
 plan['nativeGeometryEvidence']={'status':'Passed','actualProofPath':'assets/environment-v2/reports/FullThirtyFourNativeGeometryProof.json','actualProofFileSHA256':proof_file_sha,'sourceSHA256':ASSET_SHA,'groups':34,'actualPrototypeTriangles':7086,'checkedTriangleCorners':21258,'completeBatch':True,'temporaryEditableMeshesDestroyed':34,'meshIdBindings':{k:v['meshId']for k,v in expected.items()},'worldPlacementValidated':False,'savedMaterialValidatedByCornerQA':False,'countBasis':'Actual every-corner native prototype triangle counts times frozen desired placement multiplicities, plus six genuine 12-triangle primitive sign faces. Installed scene readback remains an Apply/Verify acceptance step.'}
 b=plan['budget'];b.update({'nativeTessellation':'34NativeGroupsEveryCornerPassed_7086PrototypeTriangles','actualNativeTriangleCountByFrozenSchedule':43558,'actualNativeMeshTrianglesByFrozenSchedule':43486,'actualNativeInstalledTriangleCount':None,'nativeInstalledSceneReadbackPending':True,'selectedExplicitCompositionBudget':43558,'selectedCompositionBudgetPass':True})
 e=plan['triangleBudgetException'];e.update({'selectedProjectedLimit':43558,'sourceProjectedTriangles':43558,'actualInstalledTriangles':43558,'nativeInstalledCountPending':False,'nativeGeometryScheduleCountBound':True,'actualInstalledSceneReadbackPending':True,'nativeBindingRequirement':'Apply/Verify must independently count installed actual MeshParts from these verified IDs plus six primitive sign faces and assert exactly43558. This frozen desired count is not a claim of completed world installation.','maximumApprovedActual':44000,'actualNativeProofFileSHA256':proof_file_sha})
 plan['status']='FrozenDesiredScheduleNativeGeometryBoundInstallationAcceptancePending';plan['applyEligible']=True;plan['geometryOnlyNativePending']=False
 plan['pending']=[q for q in plan['pending']if q!='Latest brick prototype geometry/native IDs/style sample']
 plan['applicationEligibilityScope']='Native geometry and deterministic source placement are ready for the reviewed Edit transaction. Remaining live/readability/navigation/jump/performance acceptance is not reported as passed.'
 plan.pop('planSHA256',None);plan['planSHA256']=sha(plan)
 return plan,normalized,expected,per_row
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--proof',default='assets/environment-v2/reports/FullThirtyFourNativeGeometryProof.json');args=ap.parse_args()
 assert raw_sha('docs/environment-v2/BeforeManifest.json')==SCENE_SHA
 plan,proof,expected,rows=bind(read(args.proof),read('assets/environment-v2/EnvironmentAssetManifest.json'),read('docs/environment-v2/EnvironmentLayout_V2.json'),raw_sha(args.proof))
 frozen_sha=write('docs/environment-v2/FrozenApplyManifest.json',plan,True);write('docs/environment-v2/EnvironmentLayout_V2.json',plan)
 proof_sha=write('docs/environment-v2/NormalizedNativeGeometryProof.json',proof,True);expected_sha=write('docs/environment-v2/ExpectedNativeBindings.json',expected,True)
 meta=proposals(plan,read('docs/environment-v2/BeforeManifest.json'),read('assets/environment-v2/EnvironmentAssetSource.json'));meta['frozenApplyManifestFileSHA256']=frozen_sha
 properties={r['originalKey']:{'Value':r['newValue']}for r in meta['changes']}
 for r in meta['appearanceEdits']:assert r['originalKey']not in properties;properties[r['originalKey']]={'Color':r['newValue']}
 for k,v in meta['ownedInstancePropertyChanges'].items():assert k not in properties;properties[k]=v
 scene=read('docs/environment-v2/BeforeManifest.json');by_path={r['path']:r for r in scene['records']};attributes={}
 for a in meta['attributeProposals']:
  a['attributes']['EnvironmentV2Hash']=frozen_sha;attributes[by_path[a['path']]['key']]=a['attributes']
 assert len(properties)==60 and sum('Adornee'in v for v in properties.values())==6
 meta_sha=write('docs/environment-v2/RuntimeMetadataProposal.json',meta)
 deltas={'schemaVersion':2,'manifestFileSHA256':frozen_sha,'manifestPlanSHA256':plan['planSHA256'],'baselineSceneSHA256':SCENE_SHA,'sourceSHA256':ASSET_SHA,'propertyChanges':properties,'attributeChanges':attributes,'allowBibleAlbedoEdits':True,'counts':{'StringValue':2,'Color':52,'Adornee':6,'OriginalPropertyRows':60,'ParentAttributeRows':2},'originalSourceWrites':0,'originalGeometryWrites':0,'AdorneeEncoding':'OwnedInstance must resolve through the exact staged/persistent OwnedRefs; never pass JSON table directly to Instance.Adornee.'}
 delta_sha=write('docs/environment-v2/FrozenPropertyDeltas.json',deltas,True)
 receipt={'status':'FrozenDesiredManifestReadyForActualEditApply','manifestFile':'docs/environment-v2/FrozenApplyManifest.json','manifestFileSHA256':frozen_sha,'manifestPlanSHA256':plan['planSHA256'],'applyEligible':True,'originalActualNativeProofSHA256':raw_sha(args.proof),'normalizedNativeProofFileSHA256':proof_sha,'expectedNativeBindingsFileSHA256':expected_sha,'metadataFileSHA256':meta_sha,'propertyDeltasFileSHA256':delta_sha,'counts':{'actualVerifiedGroups':34,'actualVerifiedPrototypeTriangles':7086,'actualCheckedCorners':21258,'frozenMeshTriangles':43486,'primitiveTriangles':72,'frozenMeshAndPrimitiveTriangles':43558,'visibleMeshParts':271,'visibleSignFaceParts':6,'colliders':305,'BaseParts':582,'instancesIncludingLayerRoot':786,'boundaryModules':70,'sharedMeshIds':34},'placementTriangles':rows,'worldInstallationReadback':'NotRunByPlanner; root actual Apply/Verify must count installed schedule','sourceWrites':0,'worldWrites':0}
 write('docs/environment-v2/FrozenApplyBindingReceipt.json',receipt)
 print(json.dumps({k:v for k,v in receipt.items()if k!='placementTriangles'}))
