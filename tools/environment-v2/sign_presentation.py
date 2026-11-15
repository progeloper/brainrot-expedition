"""Source-audited gate-sign presentation proposal. Never mutates Studio or runtime Source."""
from __future__ import annotations
import json,hashlib,math,copy
from pathlib import Path
from geometry import *
ROOT=Path(__file__).resolve().parents[2]
SOURCE_SHA='ee0fac1b3cbbfa848181ecfa6997d0ba1dc0ab7091a6e778513b24ce41a55846'
RELEVANT={
'ServerScriptService.Server.Utility.RegionGateDescriptors':'08529c5b16788643f45d024d7349a5452152d584724acad76ca20bbefb015d6a',
'ServerScriptService.Server.Services.WorldProgressionRuntime':'811603234729c062f7c0e1d2237a6582622e0faad3d57fdd62d9f4057b2eff68',
'StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldProgressionController':'e4092bfd45557236147f9a899f2dc6384249d7b846276f9f9f80a44f0f9d993f'}
def inverse_cf(cf):
 r=[cf[3+i+3*j]for i in range(3)for j in range(3)];pos=[-sum(r[i*3+j]*cf[j]for j in range(3))for i in range(3)];return pos+r

def audit_sources():
 raw=(ROOT/'docs/environment-v2/LiveSources.json').read_bytes();assert hashlib.sha256(raw).hexdigest()==SOURCE_SHA
 sources=json.loads(raw);man=json.loads((ROOT/'docs/environment-v2/LiveSourceManifest.json').read_text());assert len(sources)==357==man['sourceCount']and man['allEditorBuffersCaptured']and man['sourceJSONSHA256']==SOURCE_SHA
 population={r['path']:r for r in man['sourceRecordPopulation']};assert len(population)==357;proof=[];adorneeUses=[]
 for r in sources:
  h=hashlib.sha256(r['source'].encode()).hexdigest();expected=population[r['path']];assert h==expected['sourceSHA256']==expected['editorSourceSHA256'];assert len(r['source'].encode())==expected['sourceBytes']
  uses=[i+1 for i,l in enumerate(r['source'].splitlines())if'Adornee'in l]
  if uses:adorneeUses.append({'path':r['path'],'lines':uses,'sourceSHA256':h,'scope':'Brainrot/base presentation; not progression gate Sign/GUI'})
  if r['path']in RELEVANT:
   assert h==RELEVANT[r['path']];assert'Adornee'not in r['source']and'GateSign'not in r['source']and'AlwaysOnTop'not in r['source'];proof.append({'path':r['path'],'sourceSHA256':h,'AdorneeTokenCount':0,'GateSignTokenCount':0,'AlwaysOnTopTokenCount':0})
 assert len(proof)==3
 assert all('GateSign'not in r['source']for r in sources),'Fresh source contains a gate sign consumer; re-review before rebind'
 runtime=next(r['source']for r in sources if r['path']=='ServerScriptService.Server.Services.WorldProgressionRuntime')
 assert 'local names={InteractionAnchor=true,Approach=true,Threshold=true,SafeCharacterExterior=true,'in runtime
 assert 'SafeCartExterior=true,DoorPresentation=true}'in runtime and 'for _,property in {"CFrame","Anchored","CanCollide","Name"}'in runtime
 descriptor=next(r['source']for r in sources if r['path']=='ServerScriptService.Server.Utility.RegionGateDescriptors')
 assert'partCount > 24'in descriptor and'for _, part in gate:GetDescendants() do if part:IsA("BasePart")'in descriptor
 return{'status':'SourceContractSupportsPresentationAdorneeRebind','sourceCount':357,'sourceJSONSHA256':SOURCE_SHA,'allSourceAndEditorHashesMatchCapturedManifest':True,'relevantSourceProof':proof,'allAdorneeUsesInFullSourcePopulation':adorneeUses,'gateSourceAdorneeAssertionsOrWatches':0,'gateSignConsumersInFullSourcePopulation':0,'descriptorRequiredNames':['InteractionAnchor','Approach','Threshold','SafeCharacterExterior','SafeCartExterior','DoorPresentation'],'runtimeWatchedPartProperties':['CFrame','Anchored','CanCollide','Name'],'proxyParentOutsideOriginalGateModel':'Existing owned EnvironmentV2 Header Model; GateDescendants/part-budget/tag/parent/watch graph unchanged','clientGatePresentation':'Only originalDoorPresentation.LocalTransparencyModifier and separateScreenGui panel; no SurfaceGui contract changed','liveExecution':'NotRunByPlanner; root must assert current357Source hashes still match before commit and run existing gate binding/prompt/GUI checks afterApply','worldWrites':0,'sourceWrites':0}

def build_proposal(plan,scene,g,audit):
 records=scene['records'];byPath={r['path']:r for r in records};regions={k:decode_geometry(v)for k,v in g['regions'].items()};rows=[]
 for gate in ['Beach','Swamp','Jungle','Arctic','Volcano','GlitchZone']:
  path='Workspace.MapBlockout.ProgressionGates.'+gate;sign=byPath[path+'.Sign'];gui=byPath[path+'.Sign.GateSign'];approach=byPath[path+'.Approach'];p=sign['properties'];oldCF=unpack(p['CFrame']);oldSize=unpack(p['Size']);assert oldSize==[16,5,.5] and unpack(gui['properties']['Face'])=='Enum.NormalId.Back'and gui['properties']['Adornee']=={'type':'nil'}and gui['properties']['AlwaysOnTop']is False
  header=next(h for h in plan['objects']if h.get('openingId')=='Gate_'+gate);oldHeaderBounds=header.get('authoredMeshBounds',header['bounds']);normal=[oldCF[5],oldCF[8],oldCF[11]];ac=unpack(approach['properties']['CFrame']);toApproach=[ac[i]-oldCF[i]for i in range(3)];dot=sum(v*w for v,w in zip(normal,toApproach));assert dot>0 and normal[1]==0 and sum(abs(v)for v in normal)==1
  # Header world bounds are an exact cuboid. FaceBack on the proxy matches the original GUI orientation.
  headerFaceProjection=sum(normal[i]*(oldHeaderBounds['max'+k]if normal[i]>0 else oldHeaderBounds['min'+k]if normal[i]<0 else 0)for i,k in enumerate(['X','Y','Z']))
  signProjection=sum(oldCF[i]*normal[i]for i in range(3));offset=headerFaceProjection-signProjection+.10
  cf=[oldCF[i]+normal[i]*offset for i in range(3)]+oldCF[3:];size=[16,5,.1];b=bounds3(cf,size);innerFace=sum(cf[i]*normal[i]for i in range(3))-.05;assert abs(innerFace-headerFaceProjection-.05)<1e-8
  shp=part_projection(cf,size);region=next(k for k in REGIONS if regions[k].covers(Point(cf[0],cf[2])));assert regions[region].covers(shp),f'Proxy fully outside existingfloorregion: {gate}'
  color=[round(v*255)for v in unpack(p['Color'])];id='Gate_'+gate+'_SignFaceProxy';ownedKey=header['id']+'/'+id
  parts=[]
  for r in records:
   rp=r.get('properties')or{}
   if r['scope']!='Map'or r['path'].startswith('Workspace.MapBlockout.MapArt.Scenery.')or r['path'].startswith('Workspace.MapBlockout.MapArt.Backdrops.')or '.RegionWalls.'in r['path']or'.BoundarySeparators.'in r['path']:continue
   if'CFrame'not in rp or'Size'not in rp:continue
   if unpack(rp.get('Transparency',1))>=1:continue
   ob=bounds3(unpack(rp['CFrame']),unpack(rp['Size']));depths=[min(b['max'+k],ob['max'+k])-max(b['min'+k],ob['min'+k])for k in ['X','Y','Z']]
   if min(depths)>1e-6:parts.append({'originalKey':r['key'],'path':r['path'],'positiveDepthsXYZ':depths})
  # Any preserved visible3D intersection requires explicit review rather than claiming it clear.
  proxy={'id':id,'sourceRole':'SignFace','sourceClass':'Part','shape':'Block','cframe':cf,'size':size,'colorRGB':color,'sourceTriangles':12,'ownedReferenceKey':ownedKey,'originalGuiKey':gui['key'],'originalGuiPath':gui['path'],'originalSignKey':sign['key'],'originalSignPath':sign['path'],'parentHeaderId':header['id'],'rootRelativeCFrame':cfcompose(inverse_cf(header['rootCFrame']),cf),'regionId':region,'bounds':b,'flags':{'Anchored':True,'Transparency':0,'LocalTransparencyModifier':0,'CanCollide':False,'CanTouch':False,'CanQuery':False,'CastShadow':False,'Reflectance':0,'CollisionGroup':'Default','Material':'Glacier','MaterialVariant':'Bingus_Saved_Studs_13719188279','StudsPerTile':.25},'sourceContractSHA256':SOURCE_SHA,'adorneeChange':{'originalKey':gui['key'],'property':'Adornee','oldValue':{'type':'nil'},'newValue':{'type':'OwnedInstance','ownerRowId':header['id'],'ownedChildId':id,'ownedReferenceKey':ownedKey}},'clearanceEvidence':{'originalFaceBackWorldNormal':normal,'facesOriginalApproachDot':dot,'originalVerticalAndTangentialSignCoordinatesRetained':True,'normalPresentationOffset':offset,'headerApproachFaceProjection':headerFaceProjection,'innerFaceSeparationFromOpaqueHeader':.05,'visibleFaceSeparationFromOpaqueHeader':.15,'completeFootprintInsideRegion':region,'noPhysicalOrQueryObstructionToProtectedRoutes':True,'primitiveExactWorldBounds':b,'preservedVisibleGeometryIntersections':parts,'sourceSupportedGuiAdorneeRebind':True,'nativeSignReadability':'PendingRootActualOrdinaryView/PlayCheck'}}
  rows.append(proxy)
 assert len(rows)==6
 return{'schemaVersion':2,'status':'SourceContractPassedProxyProposalNativePending','baselineSceneSHA256':plan['baselineSceneSHA256'],'basePlanSHA256BeforePresentation':plan.get('signPresentationAdapter',{}).get('basePlanSHA256BeforePresentation',plan['planSHA256']),'sourceSHA256':plan['assetSourceSHA256'],'sourceAudit':audit,'rows':rows,'originalPropertyChanges':{r['originalGuiKey']:{'Adornee':r['adorneeChange']['newValue']}for r in rows},'counts':{'newVisibleSignFaceParts':6,'newColliderParts':0,'newPrimitiveTriangles':72,'newSharedMeshIds':0,'environmentExposedMeshProjection':43486,'meshAndPrimitiveProjectionTotal':43558,'visibleTotal':277,'collidersTotal':305,'BasePartsTotal':582,'modelsUnchanged':147,'instancesExcludingLayerRoot':785,'instancesIncludingLayerRoot':786},'preservedOriginalGuiFields':['Parent','Face','AlwaysOnTop','Enabled','SizingMode','CanvasSize','PixelsPerStud','LightInfluence','allTextChildrenReferencesProperties'],'originalSignGeometryMaterialFlagsChanged':False,'originalPromptOrDoorChanges':False,'originalSourceChanges':0,'coldJournalContract':{'desiredOwnedInstanceEncoding':'{type:OwnedInstance, ownerRowId:<existingheader>, ownedChildId:<newproxy>, ownedReferenceKey:<header/proxy>}','sourcePropertyBeforeValue':{'type':'nil'},'commitResolution':'Resolve exact ownedstagePart ref with owner/rowid/name/class anddesiredtransform flags before assigning originalGui.Adornee; never guess fullpath ordescendantindex.','persist':'Journal OwnedRefs ObjectValue perproxy with OwnedReferenceKey/EnvironmentId/OriginalGuiKey; keep exact originalGUI refs from original checkpoint.','rollback':'Restore originalAdornee nil before destroyingstage; no otherGUI setter.','coldRebind':'Resolve desiredOwnedInstance from persistedObjectValue; actualoriginalGui.Adornee must equal exactownedRef; validateoriginalGUI Parent/FaceBack/AlwaysOnTopfalse/Textref identities andunchangedSources.'},'nativeAcceptance':'Pending. No runtime/API mutation bythisproposal.'}
if __name__=='__main__':
 import argparse
 ap=argparse.ArgumentParser();ap.add_argument('--bind-plan',action='store_true');args=ap.parse_args();audit=audit_sources();planPath=ROOT/'docs/environment-v2/EnvironmentLayout_V2.json';plan=json.loads(planPath.read_text());scene=json.loads((ROOT/'docs/environment-v2/BeforeManifest.json').read_text());g=json.loads((ROOT/'docs/environment-v2/CurrentGeometry.json').read_text());out=build_proposal(plan,scene,g,audit)
 if args.bind_plan:
  for proxy in out['rows']:
   h=next(r for r in plan['objects']if r['id']==proxy['parentHeaderId']);h['signFaceProxy']=proxy;h['authoredMeshBounds']=dict(h.get('authoredMeshBounds',h['bounds']));h['bounds']={k:(min(h['bounds'][k],proxy['bounds'][k])if k.startswith('min')else max(h['bounds'][k],proxy['bounds'][k]))for k in h['bounds']};h['expectedMeshExportTriangles']=h.get('expectedMeshExportTriangles',h['expectedExportTriangles']);h['expectedExportTriangles']=h['expectedMeshExportTriangles']+12
  b=plan['budget'];b.update({'newVisibleMeshParts':271,'newVisibleSignFaceParts':6,'newVisibleParts':277,'newColliders':305,'newBaseParts':582,'newInstancesExcludingRootFolders':785,'newInstancesIncludingLayerRoot':786,'actualExposedExportMeshTriangleProjection':43486,'actualExposedExportTriangleProjection':43558,'actualMeshAndPrimitiveTriangleProjection':43558,'nativeSharedMeshIdsExpected':34})
  exc=plan['triangleBudgetException'];exc.update({'sourceProjectedTriangles':43558,'actualExposedExportTriangleProjection':43558,'environmentMeshSourceProjectedTriangles':43486,'signFacePrimitiveTriangles':72,'actualInstalledTriangles':None,'percentOverOriginal':8.895000000000009,'signPresentationReason':'Six originalSurfaceGui.Adornee-only rebindings to exactnoncollidingfaceproxies preserveoriginalsignreadability without a headerairgap, prompt/source/geometry changes orAlwaysOnTop workaround.'});plan['signPresentationAdapter']=out;plan['applyEligible']=False;plan['purePlanEligible']=not any(r['clearanceEvidence']['preservedVisibleGeometryIntersections']for r in out['rows']);plan['pending']=[q for q in plan['pending']if'gate sign'not in q.lower()]+['Exactnative signface/GUIAdornee cold refs andordinary readability/runtimegatechecks'];plan.pop('planSHA256',None);plan['planSHA256']=sha(plan);planPath.write_text(json.dumps(plan,indent=2)+'\n');out['boundPlanSHA256']=plan['planSHA256']
 (ROOT/'docs/environment-v2/SignPresentationAdapter.json').write_text(json.dumps(out,indent=2)+'\n');(ROOT/'docs/environment-v2/GateSignSourceContractAudit.json').write_text(json.dumps(audit,indent=2)+'\n');print(json.dumps({'status':out['status'],'proxies':[(r['id'],r['cframe'][:3],r['regionId'],len(r['clearanceEvidence']['preservedVisibleGeometryIntersections']))for r in out['rows']],'boundPlanSHA256':out.get('boundPlanSHA256'),'counts':out['counts']}))
