import json,pathlib,math,hashlib
root=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition');doc=root/'docs/map-compaction';baseline=json.loads((doc/'BeforeManifest.json').read_text());cand=next(c for c in json.loads((doc/'CompactBaseLayoutCandidates.json').read_text())['candidates']if c['analyticalRectangleContainmentPassed']);b=cand['b'];g=cand['geometry'];out={'schemaVersion':1,'status':'PreparedForNativeFitNotApplied','b':b,'functionalApproachCorrection':cand['functionalApproachCorrection'],'managedSourceSHA256':baseline['baselineManagedContentSHA256'],'candidateRuntimeGeometryPath':str(doc/'CompactBaseLayoutRuntimeGeometry.Prepared.json'),'bases':[]}
def localcf(parent,cf):
 r=[parent[3:6],parent[6:9],parent[9:12]];s=[cf[3:6],cf[6:9],cf[9:12]];p=[sum(r[i][j]*(cf[i]-parent[i])for i in range(3))for j in range(3)];return p+[sum(r[k][i]*s[k][j]for k in range(3))for i in range(3)for j in range(3)]
for base in sorted([r for r in baseline['objects']if r['class']=='Model'and r['name'].startswith('Base_')],key=lambda r:r['name']):
 row={'id':base['name'],'capturedStructuralPivot':base['pivot']['value'],'parts':[],'shellPlacementLocal':[g['support']['centreX'],1,g['support']['centreZ']]}
 for part in [r for r in baseline['objects']if r.get('parentPath')==base['path']and'CFrame'in r.get('properties',{})]:pass
 for part in [r for r in baseline['objects']if r['path'].startswith(base['path']+'.')and'CFrame'in r.get('properties',{})and r['path'].count('.')==base['path'].count('.')+1]:
  cf=localcf(base['pivot']['value'],part['properties']['CFrame']['value']);size=part['properties']['Size']['value'][:];name=part['name'];cf[0]*=b;cf[2]*=b
  if name.startswith('Slot_'):
   index=int(name.split('_')[1]);slot=g['slots'][index-1];cf[0]=slot['X'];cf[2]=slot['Z'];side=slot['Side'];cf[3:]=[0,0,side,0,1,0,-side,0,0];size[0]=g['padTangentialStuds'];size[2]=g['padNormalStuds']
  elif name=='Foundation':cf[0]=g['support']['centreX'];cf[2]=g['support']['centreZ'];size[0]=g['support']['width'];size[2]=g['support']['depth']
  elif name=='CartDisplay':cf[0]=cand['cartSupport']['centreX'];cf[2]=cand['cartSupport']['centreZ'];size[0]=cand['cartSupport']['width'];size[2]=cand['cartSupport']['depth']
  elif name=='CartRamp':cf[0]=cand['functionalApproachCorrection']['cartRamp']['centreX'];cf[2]=cand['functionalApproachCorrection']['cartRamp']['centreZ']
  elif name=='HouseRamp':cf[0]=cand['functionalApproachCorrection']['houseRamp']['centreX'];cf[2]=cand['functionalApproachCorrection']['houseRamp']['centreZ']
  elif name in ['CartSpawn','DepositReturnZone','PlayerSpawn']:cf[2]+=cand['functionalApproachCorrection']['uniformCartBundleShiftZ']
  # Spawn/deposit/player markers retain physical dimensions, Y and captured rotation.
  item={'name':name,'sourcePath':part['path'],'class':part['class'],'localCFrame':cf,'size':size,'preserveOriginalFlagsPhysicsAndY':True}
  if name.startswith('Slot_'):
   child=next(x for x in baseline['objects']if x['path']==part['path']+'.BrainrotPlacement');item['BrainrotPlacementLocalCFrame']=child['attachment']['CFrame']['value'];item['stableSlotIndex']=int(name.split('_')[1])
  row['parts'].append(item)
 out['bases'].append(row)
out['knownChecksRemaining']=['all native released visual full support and gaps','claim plaque face six-stud aisle','loaded cart twenty-by-thirty-six support and twenty-four-stud approach','house ramp coplanar support presentation','every-site cart return and player spawn ground','fitted shell actual native import/corner proof','ordinary driving/turning and gameplay']
f=doc/('CompactBaseLayoutPartLocals_%03d.Prepared.json'%round(b*100));f.write_text(json.dumps(out,indent=2)+'\n');print(len(out['bases']),sum(len(r['parts'])for r in out['bases']),hashlib.sha256(f.read_bytes()).hexdigest())
