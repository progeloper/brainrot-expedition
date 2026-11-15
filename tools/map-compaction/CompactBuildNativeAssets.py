#!/usr/bin/env python3
"""One persistent native-import GLB: compact roads, fitted shell, closed wall cube.
Candidate remains provisional; encoding/native asset QA cannot authorize Apply.
"""
from __future__ import annotations
import argparse,json
from pathlib import Path
from CompactNativeGeometry import encode,validate_binary,sha,f32,cross,sub,dot,length
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def write(p,d):p.write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
def unit_cube():
 corners=[]
 # A real closed unit cuboid, twelve outward oriented triangles, hard normals.
 faces=[([1,0,0],[[.5,-.5,-.5],[.5,.5,-.5],[.5,.5,.5],[.5,-.5,.5]]),([-1,0,0],[[-.5,-.5,.5],[-.5,.5,.5],[-.5,.5,-.5],[-.5,-.5,-.5]]),([0,1,0],[[-.5,.5,-.5],[-.5,.5,.5],[.5,.5,.5],[.5,.5,-.5]]),([0,-1,0],[[-.5,-.5,.5],[-.5,-.5,-.5],[.5,-.5,-.5],[.5,-.5,.5]]),([0,0,1],[[.5,-.5,.5],[.5,.5,.5],[-.5,.5,.5],[-.5,-.5,.5]]),([0,0,-1],[[-.5,-.5,-.5],[-.5,.5,-.5],[.5,.5,-.5],[.5,-.5,-.5]])]
 uv=[[0,0],[0,4],[4,4],[4,0]]
 for normal,quad in faces:
  for ids in [(0,1,2),(0,2,3)]:
   assert dot(cross(sub(quad[ids[1]],quad[ids[0]]),sub(quad[ids[2]],quad[ids[0]])),normal)>0
   corners.extend({'position':quad[i],'normal':normal,'uv':uv[i]} for i in ids)
 return {'id':'CompactWallCube_Unit','rootId':'CompactWallCube','groupId':'Unit','centre':[0,0,0],'rgb':[255,255,255],'role':'WallUnit','positions':[r['position'] for r in corners],'normals':[r['normal'] for r in corners],'uvs':[r['uv'] for r in corners]}
def expected(g):
 p,n,u=g['positions'],g['normals'],g['uvs']
 low=[min(v[i] for v in p) for i in range(3)];high=[max(v[i] for v in p) for i in range(3)]
 return {'id':g['id'],'prototypeId':g['rootId'],'groupId':g['groupId'],'role':g['role'],'centre':g['centre'],'size':[high[i]-low[i] for i in range(3)],'localBounds':[low,high],'rgb':g['rgb'],'triangles':[[[f32(v) for v in p[k]+u[k]+n[k]] for k in range(i,i+3)] for i in range(0,len(p),3)]}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--roads',type=Path,required=True);ap.add_argument('--shell',type=Path,required=True);ap.add_argument('--shell-manifest',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--selected-interior-fit-proof',type=Path);a=ap.parse_args()
 rm=json.loads((a.roads/'CompactRouteMeshManifest.json').read_text());rr=json.loads((a.roads/'CompactRoadExpectedGeometry.json').read_text());shell=json.loads(a.shell.read_text());sm=json.loads(a.shell_manifest.read_text());assert sm['b']==rm['candidate']['b'] and sm['sourceSHA256']==shell['sourceSHA256'] and len(rr)==27 and len(shell['groups'])==3
 groups=[]
 for r in rr:
  corners=[v for t in r['triangles'] for v in t]
  groups.append({'id':r['id'],'rootId':'CompactMapRoads','groupId':r['id'],'centre':r['pivot'],'rgb':r['pathRGB'],'role':'Road','positions':[v[:3] for v in corners],'uvs':[v[3:5] for v in corners],'normals':[[0,1,0] for _ in corners]})
 for r in shell['groups']:
  c=r['groupCanonicalCentre'];corners=[v for t in r['triangles'] for v in t]
  groups.append({'id':shell['prototypeId']+'_'+r['id'],'rootId':shell['prototypeId'],'groupId':r['id'],'centre':c,'rgb':r['materialRGB'],'role':'FittedShell','positions':[sub(v['position'],c) for v in corners],'normals':[v['normal'] for v in corners],'uvs':[v['uv'] for v in corners]})
 groups.append(unit_cube());assert len(groups)==31
 a.output.mkdir(parents=True,exist_ok=True)
 raw=encode(groups);imp=encode(groups,True);canpath=a.output/'CompactAssetsCanonical.glb';ipath=a.output/'CompactAssetsStudioImport.glb';canpath.write_bytes(raw);ipath.write_bytes(imp)
 cr=validate_binary(canpath,groups);ir=validate_binary(ipath,groups,True)
 write(a.output/'CompactAssetsBinaryVerification.json',{'canonical':cr,'studioImport':ir,'sourceShellSHA256':shell['sourceSHA256'],'shellCornersFileSHA256':sha(a.shell.read_bytes()),'roadGeometryHash':rm['routeGeometryHash'],'nativeReadbackStatus':'NotRun'})
 rows=[expected(g) for g in groups];write(a.output/'CompactAssetExpectedGeometry.json',rows)
 template=(ROOT/'assets/map-art/VerifyImportedPrototypeGeometry.template.luau').read_text()
 template=template.replace('MapArt_ImportedPrototypes','CompactMap_ImportedAssets').replace('__SOURCE_HASH__',shell['sourceSHA256']).replace('__CANONICAL_HASH__',sha(raw)).replace('__IMPORT_HASH__',sha(imp))
 template=template.replace('Match every oriented triangle corner\'s canonical position, repeating saved-stud', 'Match every oriented triangle corner\'s canonical position, source').replace('repeatingSavedMaterialUVPassed', 'sourceUVValuesPassed')
 template=template.replace('if #report.groups~=29 then','if #report.groups~=#EXPECTED then').replace('Expected29 complete native mesh groups','Expected complete compact native mesh groups')
 template=template.replace('assert(math.max(math.abs(part.Size.X-row.size[1]),math.abs(part.Size.Y-row.size[2]),math.abs(part.Size.Z-row.size[3]))<=.01,\n            "Native bounding size differs from final source dimensions")','local planarOK=row.role=="Road" and part.Size.Y>0 and part.Size.Y<=.05001 and (math.abs(part.Size.Y-.001)<=1e-5 or math.abs(part.Size.Y-.05)<=1e-5)\n        assert(math.abs(part.Size.X-row.size[1])<=.01 and math.abs(part.Size.Z-row.size[3])<=.01 and (row.role=="Road" and planarOK or row.role~="Road" and math.abs(part.Size.Y-row.size[2])<=.01),"Native bounds/clamp differ from compact source")')
 template=template.replace('sourceSHA256="'+shell['sourceSHA256']+'",','sourceSHA256="'+shell['sourceSHA256']+'",\n        roadGeometryHash="'+rm['routeGeometryHash']+'",')
 (a.output/'CompactVerifyNativeAssets.luau').write_text(template.replace('__EXPECTED_JSON__',json.dumps(rows,separators=(',',':'))))
 qa=a.output/'qa';qa.mkdir(exist_ok=True)
 for r in rows:(qa/(r['id']+'.verify.luau')).write_text(template.replace('__EXPECTED_JSON__',json.dumps([r],separators=(',',':'))))
 report={'schemaVersion':1,'migrationId':'CompactMap_V1','status':'SourceBinaryVerified; actual native import NotRun','candidate':rm['candidate'],'selectedCandidate':None,'finalCandidateApproved':False,'worldInstalled':False,'roadGeometryHash':rm['routeGeometryHash'],'roadCanonicalSourceSHA256':rm['canonicalGLB']['sha256'],'roadStandaloneImportSHA256':rm['studioImportGLB']['sha256'],'sourceShellSHA256':shell['sourceSHA256'],'shellOriginalSourceSHA256':shell['originalSourceSHA256'],'shellCornersFileSHA256':sha(a.shell.read_bytes()),'canonicalSourceSHA256':sha(raw),'studioImportSHA256':sha(imp),'canonicalFile':canpath.name,'studioImportFile':ipath.name,'groups':len(groups),'triangles':sum(len(g['positions'])//3 for g in groups),'corners':sum(len(g['positions']) for g in groups),'roots':['CompactMapRoads',shell['prototypeId'],'CompactWallCube'],'groupRecords':[{k:v for k,v in r.items() if k!='triangles'}|{'triangles':len(r['triangles'])} for r in rows],'requiredNativeRoot':'ServerStorage.CompactMap_ImportedAssets','verifier':'CompactVerifyNativeAssets.luau','nativeGeometryOnly':True,'embeddedImages':0,'nativeIDsInvented':0,'worldMutations':0,'surfaceStyle':'SavedGlacier/BingusStuds .25; native template prep separate','geometryPolicy':'Hard normals/UV/winding retained per object. Native measured Y180 import compensation in XZ positions/normals/translations only. Source shell ground root remains0; per-group bbox centres are nodes, not root shifts.'}
 if a.selected_interior_fit_proof:
  fit=json.loads(a.selected_interior_fit_proof.read_text());assert fit['b']==rm['candidate']['b'] and fit['nativeProposalFitPassed'] and fit['nativeExecutionPassed']
  report.update(status='SelectedNativeImportBatchFinalized; actual native corner readback NotRun',selectedCandidate=rm['candidate'],candidateSelectedForNativeGeometryImport=True,geometryBatchReadyForNativeImport=True,interiorFitEvidence={'path':str(a.selected_interior_fit_proof),'sha256':sha(a.selected_interior_fit_proof.read_bytes()),'nativeProposalFitPassed':True,'fullAcceptancePassed':fit['fullAcceptancePassed']},wholeMapApplicationAcceptance='Pending cart turns/full sites; source export cannot bypass parent Apply/Verify/Rollback')
 write(a.output/'CompactNativeAssetManifest.json',report);print(json.dumps({k:report[k] for k in ['status','groups','triangles','corners','roadGeometryHash','canonicalSourceSHA256','studioImportSHA256']},indent=2))
if __name__=='__main__':main()
