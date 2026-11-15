#!/usr/bin/env python3
"""Pure final-local compact base candidates and component-wise fitted accepted shell.
Consumes actual native measurements; writes only new scoped candidates/fixtures.
No claim of native/world/gameplay acceptance follows from this generator.
"""
import argparse,copy,hashlib,json,math,pathlib
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
SOURCE_SHA='a74be8e35bc6545bec1134f7fd5e04ba75a253648c3b39810810781af3cb8ee2'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def dumps(x):return json.dumps(x,sort_keys=True,separators=(',',':'),allow_nan=False)
def write(path,data):path.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
def ceil2(x):return math.ceil((x-1e-9)*100)/100

def mapaxis(a,b):
 t=96*b+8;r=4*math.ceil((t+96*b/2+110*b/2+8)/4);h=4*math.ceil((r+110*b/2+12)/4);old,new=0,0
 for source,target in zip([136,313,420,432],[t,r,h-12,h]):
  if a<=source:return new+(a-old)*(target-new)/(source-old)
  old,new=source,target
 raise AssertionError('Interior sample beyondCamp')
def candidate(b,padn,padt,cart):
 stride=ceil2(padt+2.02);aisle=6.02+2*(.55+2.25);offset=(padn+aisle)/2
 width=2*padn+aisle;depth=5*stride+padt
 cartw=max(32*b,cart['width']);cartd=max(24*b,cart['depth']);cartx=28*b;cartz=-54*b
 shellw=width+8*b+.2;rearMargin=2.45*b+.1;frontMargin=6.02;shelld=depth+frontMargin+rearMargin
 supportw=shellw+.2;supportd=shelld+.2
 plot={'minX':-48*b,'maxX':48*b,'minZ':-78*b,'maxZ':32*b}
 # Fixed 24-stud cart approach and measured centered support both protected.
 protectedCartMinX=min(cartx-cartw/2,cartx-12)
 centrex=protectedCartMinX-.2-supportw/2;formationz=-23*b
 shellz=formationz+(rearMargin-frontMargin)/2
 loopCentreZ=-(mapaxis(336,b)-mapaxis(192,b));loopNearEdgeZ=loopCentreZ+18
 desiredFront=loopNearEdgeZ+2
 supportShift=max(0,desiredFront-(shellz-supportd/2));cartShift=max(0,desiredFront-(cartz-cartd/2))
 formationz+=supportShift;shellz+=supportShift;cartz+=cartShift
 support={'centreX':centrex,'centreZ':shellz,'width':supportw,'depth':supportd}
 z=[formationz+(i-2.5)*stride for i in range(6)]
 row={'rowOffsetX':offset,'formationCenterX':centrex,'formationCenterZ':formationz,'padNormalStuds':padn,'padTangentialStuds':padt,'zCenters':z,'support':support,'perimeter':dict(support,frontSign=-1,postWidth=.625*b,postDepth=.625*b),'slots':[]}
 for side in [-1,1]:
  for i,station in enumerate(z):row['slots'].append({'Index':len(row['slots'])+1,'Side':side,'X':centrex+side*offset,'Z':station,'PadNormalStuds':padn,'PadTangentialStuds':padt})
 supportBounds={'minX':centrex-supportw/2,'maxX':centrex+supportw/2,'minZ':shellz-supportd/2,'maxZ':shellz+supportd/2}
 cartbounds={'minX':cartx-cartw/2,'maxX':cartx+cartw/2,'minZ':cartz-cartd/2,'maxZ':cartz+cartd/2}
 failures=[]
 for name,bounds in [('Support',supportBounds),('CartPad',cartbounds)]:
  for key in ['minX','minZ']:
   if bounds[key]<plot[key]-1e-8:failures.append(f'{name}.{key} below contracted visible plot by {plot[key]-bounds[key]:.9f}')
  for key in ['maxX','maxZ']:
   if bounds[key]>plot[key]+1e-8:failures.append(f'{name}.{key} above contracted visible plot by {bounds[key]-plot[key]:.9f}')
 return {'b':b,'status':'SourcePreparedNativeFixturePending','analyticalRectangleContainmentPassed':not failures,'analyticalFailures':failures,'geometry':row,'plotBounds':plot,'supportBounds':supportBounds,'cartSupport':{'centreX':cartx,'centreZ':cartz,'width':cartw,'depth':cartd,'bounds':cartbounds,'loadedCentredSupportMinimum':cart,'unchangedSpawnFacing':True,'approachWidth':24,'uniformBundleShiftZ':cartShift},'shell':{'id':'CompactShowhouseShell_A','centreX':centrex,'centreZ':shellz,'width':shellw,'depth':shelld,'height':22,'frontSign':-1,'rearInnerMargin':rearMargin,'frontPadMargin':frontMargin,'componentHorizontalCrossSectionFactor':b,'wholeCompoundMeshWarp':False},'clearances':{'padGap':stride-padt,'padInnerAisle':aisle,'claimPlaqueFaceAisle':aisle-5.6,'cartSupportVsFoundationGap':cartbounds['minX']-supportBounds['maxX'],'cartApproachVsFoundationGap':cartx-12-supportBounds['maxX'],'nativeMeasurementContainmentMarginNormal':padn-13.918379783630371,'nativeMeasurementContainmentMarginTangent':padt-10.155370712280273},'functionalApproachCorrection':{'sourceLoopRadialOffset':192,'sourceBaseStructuralRadialOffset':336,'loopCentreZ':loopCentreZ,'loopWidth':36,'loopNearEdgeZ':loopNearEdgeZ,'supportRoadClearance':supportBounds['minZ']-loopNearEdgeZ,'cartRoadClearance':cartbounds['minZ']-loopNearEdgeZ,'uniformFormationSupportShellShiftZ':supportShift,'uniformCartBundleShiftZ':cartShift,'houseRamp':{'centreX':centrex,'centreZ':desiredFront-5.8,'width':20,'depth':12,'supportJoinOverlap':.2},'cartRamp':{'centreX':cartx,'centreZ':desiredFront-5.8,'width':24,'depth':12,'supportJoinOverlap':.2},'rigidFunctionalRampDimensionsPreserved':True},'acceptance':{'nativeFixturePassed':False,'cartDrivingTurningPassed':False,'shellNativeImportPassed':False,'allSitesFitPassed':False,'gameplayPassed':False}}

def affine(component,b,w,d,oldw,oldd):
 name=component['id'];hw,hd=w/2,d/2;ohw,ohd=oldw/2,oldd/2
 if name.startswith('corner_buttress_'):
  _,_,side,j=name.split('_');side=int(side);j=int(j)
  oldx=side*(ohw-2);newx=side*(hw-2*b);oldz=[-ohd+2,0,ohd-2][j];newz=[-hd+2*b,0,hd-2*b][j]
  a=[b,1,b];t=[newx-b*oldx,0,newz-b*oldz]
 elif name.startswith('side_wall_panel_')or name.startswith('side_crown_rail_'):
  side=int(name.split('_')[-2]if name.startswith('side_wall_panel_')else name.split('_')[-1])
  a=[b,1,d/oldd];t=[side*(hw-b*ohw),0,0]
 elif name.startswith('rear_sign_frame_'):
  oldx=float(name.split('_')[-1]);newx=oldx*w/oldw
  a=[b,1,b];t=[newx-b*oldx,0,hd-b*ohd]
 elif name=='rear_structural_wall'or name.startswith('rear_panel_relief_')or name=='rear_crown_rail':
  a=[w/oldw,1,b];t=[0,0,hd-b*ohd]
 else:raise AssertionError('Unknown frozen shell component '+name)
 assert all(v>0 for v in a);return a,t

def vector(a,b):return[b[i]-a[i]for i in range(3)]
def normal(a,b,c):
 x,y=vector(a,b),vector(a,c);n=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]];length=math.sqrt(sum(v*v for v in n));assert length>1e-12;return[v/length for v in n]
def merge(components):
 out={}
 for group in ['Support','Primary','Accent']:
  selected=[c for c in components if c['group']==group];vs=[];normals=[];uvs=[];triangles=[];polys=[]
  for c in selected:
   off=len(vs);vs.extend(c['vertices'])
   for f in c['faces']:
    n=normal(*[c['vertices'][i]for i in f[:3]]);normals.append(n);axes=[i for i in range(3)if i!=max(range(3),key=lambda i:abs(n[i]))];corners=[]
    for vi in f:uvs.append([c['vertices'][vi][a]*4 for a in axes]);corners.append([off+vi+1,len(uvs),len(normals)])
    polys.append(corners)
    for j in range(1,len(corners)-1):triangles.append([corners[0],corners[j],corners[j+1]])
  out[group]={'vertices':vs,'normals':normals,'uvs':uvs,'triangles':triangles,'polygons':polys,'source_components':[c['id']for c in selected]}
 return out

def fitted(root,c):
 source=root/'assets/map-art/redesign/mesh-data.json';assert sha(source)==SOURCE_SHA
 p=json.loads(source.read_text())['ShowhouseShell_A'];allvs=[v for component in p['components']for v in component['vertices']];lo=[min(v[i]for v in allvs)for i in range(3)];hi=[max(v[i]for v in allvs)for i in range(3)];oldw,oldd=hi[0]-lo[0],hi[2]-lo[2]
 q=copy.deepcopy(p);q['id']='CompactShowhouseShell_A';transforms={}
 for comp in q['components']:
  a,t=affine(comp,c['b'],c['shell']['width'],c['shell']['depth'],oldw,oldd);transforms[comp['id']]={'scale':a,'translation':t};comp['vertices']=[[a[i]*v[i]+t[i]for i in range(3)]for v in comp['vertices']]
 q['group_meshes']=merge(q['components']);q['source_component_sha256']=SOURCE_SHA;q['component_transforms']=transforms;q['coordinate_frame']='Canonical Roblox XYZ; identity ground pivot, local Y unchanged';q['scope']='Authorized uniform compact support correction; source-only, native import pending'
 # Verify topology, Y, affine positive determinants, exact factors and final envelope.
 assert len(q['components'])==32 and len(q['group_meshes'])==3
 for orig,comp in zip(p['components'],q['components']):assert orig['faces']==comp['faces']and orig['group']==comp['group']and all(a[1]==b[1]for a,b in zip(orig['vertices'],comp['vertices']))
 vs=[v for comp in q['components']for v in comp['vertices']];q['bounds_min']=[min(v[i]for v in vs)for i in range(3)];q['bounds_max']=[max(v[i]for v in vs)for i in range(3)]
 assert abs(q['bounds_max'][0]-q['bounds_min'][0]-c['shell']['width'])<1e-8 and abs(q['bounds_max'][2]-q['bounds_min'][2]-c['shell']['depth'])<1e-8
 # Transform each proven convex cell rather than redecomposing or bending the frozen surfaces.
 olddecomp=json.loads((root/'assets/map-art/redesign/TraditionalCSGDecomposition.json').read_text());oldp=next(x for x in olddecomp['prototypes']if x['id']=='ShowhouseShell_A');np=copy.deepcopy(oldp);np['id']=q['id']
 for group in np['groups']:
  mesh=q['group_meshes'][group['id']];group['source_triangles']=len(mesh['triangles'])
  for s in group['solids']:
   tr=transforms[s['source_component_id']];a,t=tr['scale'],tr['translation'];s['vertices']=[[a[i]*v[i]+t[i]for i in range(3)]for v in s['vertices']]
   for plane in s['planes']:
    n=[plane['n'][i]/a[i]for i in range(3)];length=math.sqrt(sum(x*x for x in n));plane['d']=(plane['d']+sum(n[i]*t[i]for i in range(3)))/length;plane['n']=[x/length for x in n]
   s['volume']*=a[0]*a[1]*a[2];s['bounds_min']=[min(v[i]for v in s['vertices'])for i in range(3)];s['bounds_max']=[max(v[i]for v in s['vertices'])for i in range(3)]
   assert max(sum(pl['n'][i]*v[i]for i in range(3))-pl['d']for pl in s['planes']for v in s['vertices'])<1e-7
  gv=mesh['vertices'];gl=[min(v[i]for v in gv)for i in range(3)];gh=[max(v[i]for v in gv)for i in range(3)];group['centre_xyz']=[(gl[i]+gh[i])/2 for i in range(3)];group['size_xyz']=[gh[i]-gl[i]for i in range(3)]
 decomposition={'source_sha256':hashlib.sha256(dumps(q).encode()).hexdigest(),'original_source_sha256':SOURCE_SHA,'source_path':f"CompactBaseLayoutShell_{round(c['b']*100):03d}.mesh-data.json",'source_style_version':2,'coordinate_frame':olddecomp['coordinate_frame'],'status':'Source-only private fit fixture; native final mesh import pending','prototypes':[np]}
 return q,decomposition

def main():
 p=argparse.ArgumentParser();p.add_argument('--root',type=pathlib.Path,default=ROOT);a=p.parse_args();root=a.root;doc=root/'docs/map-compaction';tools=root/'tools/map-compaction'
 measured=json.loads((doc/'RuntimeBaseFitResultSummary.json').read_text());cargo=json.loads((doc/'CompactBaseLayoutNativeCargo.json').read_text());assert cargo['nativeExecutionPassed']and cargo['releasedSpeciesCount']==32 and cargo['nativeMountPoseCalls']==128 and cargo['cleanup']['stageRemoved']
 padn=ceil2(measured['maxima']['centredFullSupportTransversePad']['value']);padt=ceil2(measured['maxima']['centredFullSupportTangentialPad']['value']);cases=[candidate(b,padn,padt,cargo['centredCartPadRequired'])for b in [.75,.8,.85,.9,.95,1]]
 result={'schemaVersion':1,'migrationId':'CompactMap_V1','status':'SourcePreparedNativeFixturePending','sourceInputs':{str(path.relative_to(root)):sha(path)for path in [doc/'BeforeManifest.json',doc/'RuntimeBaseFitNative_Before.json',doc/'CompactBaseLayoutNativeCargo.json']},'releasedSpeciesCount':32,'uniformDisplayScalesChanged':False,'candidates':cases,'firstAnalyticalCandidate':next(c['b']for c in cases if c['analyticalRectangleContainmentPassed']),'fullAcceptancePassed':False}
 write(doc/'CompactBaseLayoutCandidates.json',result)
 chosen=next(c for c in cases if c['analyticalRectangleContainmentPassed']);tag=f"{round(chosen['b']*100):03d}";shell,decomp=fitted(root,chosen);shellpath=tools/f'CompactBaseLayoutShell_{tag}.mesh-data.json';write(shellpath,{shell['id']:shell});decomp['source_sha256']=sha(shellpath);write(tools/f'CompactBaseLayoutShell_{tag}.csg.json',decomp)
 manifest={'schemaVersion':1,'status':'SourcePreparedNativeImportPending','b':chosen['b'],'prototypeId':shell['id'],'sourceSHA256':sha(shellpath),'frozenOriginalSourceSHA256':SOURCE_SHA,'coordinate_frame':shell['coordinate_frame'],'sourceDataPath':str(shellpath),'bounds_min':shell['bounds_min'],'bounds_max':shell['bounds_max'],'componentCount':len(shell['components']),'componentTransforms':shell['component_transforms'],'groups':[{'id':g,'triangles':len(m['triangles']),'preview_colour':next(z['preview_colour']for z in decomp['prototypes'][0]['groups']if z['id']==g)}for g,m in shell['group_meshes'].items()],'allFrozenComponentYUnchanged':True,'wholeCompoundMeshWarp':False,'nativeProofPassed':False}
 write(doc/f'CompactBaseLayoutShell_{tag}.Manifest.json',manifest)
 raw={'schemaVersion':1,'migrationId':'CompactMap_V1','runtimeValidated':False,'planHash':hashlib.sha256(dumps(chosen).encode()).hexdigest(),'bases':{f'Base_{i:02d}':chosen['geometry']for i in range(1,13)},'staticWallObstacles':[],'services':{r['name']:{'logicalInteractionEnvelope':r['properties']['Size']['value']}for r in json.loads((doc/'BeforeManifest.json').read_text())['objects']if r['path'].startswith('Workspace.MapBlockout.ServiceStallPatches.')and'CFrame'in r.get('properties',{})}}
 write(doc/'CompactBaseLayoutRuntimeGeometry.Prepared.json',raw)
 text=f"""# Compact base layout — source candidate

The user authorized one common six-by-two spacing and supporting geometry correction. All twelve slot IDs/order, inward facing, current canonical brainrot scales, original claim semantics and structural anchors remain unchanged. Only new candidate files and controlled fixture sources are written.

Actual native measurements cover 32 released species: 768 source-exact display placements and 128 source-exact cargo mounts. The common support pad rounds up to {padn} normal by {padt} tangent studs. A 12.18 stride leaves 2.02 between pads. The 11.62 pad-edge aisle leaves 6.02 between both original claim plaques after their unchanged 2.8-stud intrusion per side. Teased models remain excluded.

The loaded cart includes hidden/chassis parts and four current authored cargo poses. Its native pivot envelope X−8..8,Z−16..11.247915268 requires a centered 20 by 36 pad, with two studs per edge. The measured asymmetric pivot requires more depth than its span plus four.

The frozen Camp loop is evaluated by the same separable transform at the captured source radial distances336 and192. Its36-stud width is preserved. Formation, shell and support receive one common necessary Z correction; the cart bundle receives its common correction. Both support front edges stop two studs before the loop's nearest edge. Functional WedgeParts retain original House20×12 and Cart24×12 dimensions/Y/rise and meet support by .2stud. Roads are unchanged by this fit correction.

Factors .75 and .8 fail anchored contracted-plot containment after the necessary road/front-access correction. Factor {chosen['b']} is the first analytical candidate; this is numerical source geometry only. Full native owner fixture, fitted shell native import, every-site collision/approach, actual loaded driving and ordinary gameplay acceptance remain separate pending gates.

Selected source geometry: formation centroid({chosen['geometry']['formationCenterX']:.9f},{chosen['geometry']['formationCenterZ']:.9f}); Foundation {chosen['geometry']['support']['width']:.9f}×{chosen['geometry']['support']['depth']:.9f} centred({chosen['geometry']['support']['centreX']:.9f},{chosen['geometry']['support']['centreZ']:.9f}); cart support {chosen['cartSupport']['width']:.9f}×{chosen['cartSupport']['depth']:.9f} centred({chosen['cartSupport']['centreX']:.9f},{chosen['cartSupport']['centreZ']:.9f}). Full locals are in the generated candidate JSON.

The fitted shell preserves32 accepted component IDs/groups, colours, Y geometry and face topology. Each post cross section contracts in X/Z by selected b; lengths and centres are fitted independently. Flat hard normals, coordinate-projected UVs, unchanged winding and transformed exact convex cells are exported. Existing templates and frozen map-art sources remain untouched.

Prepared production runtime geometry deliberately retains runtimeValidated=false. A private completed owner exists only inside the ServerStorage fixture to exercise the guarded parser. Native interior pass does not prove shell import, loaded-turning, road-spur alignment, player spawn support, all-site fit or gameplay.
"""
 (doc/'CompactBaseLayoutPlan.md').write_text(text)
 print(json.dumps({'status':'SourcePreparedNativeFixturePending','firstAnalyticalCandidate':result['firstAnalyticalCandidate'],'shellSourceSHA256':manifest['sourceSHA256'],'groups':manifest['groups'],'preparedRuntimeBytes':len(dumps(raw).encode()),'candidates':[{'b':c['b'],'rectanglePassed':c['analyticalRectangleContainmentPassed'],'failures':c['analyticalFailures']}for c in cases]}))
if __name__=='__main__':main()
