#!/usr/bin/env python3
"""Rebuild compact constant-width road union; export genuine native-import GLBs.
Read-only source inputs. No Studio access, IDs invented or original asset writes.
Python3.12 + Shapely2.2 in the documented temporary authoring runtime.
"""
from __future__ import annotations
import argparse,copy,hashlib,json,math,struct
from collections import defaultdict
from pathlib import Path
from shapely.geometry import Polygon,Point,box,GeometryCollection,LineString
from shapely.ops import unary_union
from shapely import constrained_delaunay_triangles,set_precision
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
REGIONS={'REGION_CAMP':'Camp','REGION_FOREST':'Forest','REGION_BEACH':'Beach','REGION_SWAMP':'Swamp','REGION_JUNGLE':'Jungle','REGION_ARCTIC':'Arctic','REGION_VOLCANO':'Volcano','REGION_GLITCH':'Glitch Zone'}
EPS=1e-7

def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def sha(raw): return hashlib.sha256(raw).hexdigest()
def read(path): raw=path.read_bytes();return json.loads(raw),sha(raw)
def write(path,value): path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def polys(g):
 if g.is_empty:return []
 if g.geom_type=='Polygon':return [g]
 return [p for c in getattr(g,'geoms',[]) for p in polys(c)]
def pg(p):return {'exterior':[list(v) for v in p.exterior.coords],'holes':[[list(v) for v in r.coords] for r in p.interiors]}
def geometry(g):return [pg(p) for p in sorted(polys(g),key=lambda p:(p.bounds,p.area))]
def point(d,c):
 sign=-1 if d<0 else 1;a=abs(d);old,new=0,0
 for s,t in zip([136,313,420,432],[c['t'],c['r'],c['h']-12,c['h']]):
  if a<=s:return sign*(new+(a-old)*(t-new)/(s-old))
  old,new=s,t
 return sign*(new+(a-old)*c['outer'])
def mapped_axis(v,axis,c):return c['origin'][axis]+point(v-c['origin'][axis],c)
def localpoly(g,n,rows):
 ux,uz=n[2],-n[0]
 return Polygon([(g[0]+n[0]*s+ux*u,g[2]+n[2]*s+uz*u) for s,u in rows])
def f32(v):return struct.unpack('<f',struct.pack('<f',v))[0]

def encode_meshes(meshes,compensate=False):
 doc={'asset':{'version':'2.0','generator':'BrainrotExpedition CompactBuildRoadMeshes','extras':{'NumericCoordinateSystem':'Roblox XYZ Y-up','NativeImporterCompensation':'diag(-1,1,-1)' if compensate else 'None canonical source','SurfaceStyle':'SavedBingusStuds','StudsPerTile':.25}},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'CompactMapRoads','children':[]}],'meshes':[],'accessors':[],'bufferViews':[],'materials':[]}
 binary=bytearray();material={}
 def accessor(rows,width,kind=5126):
  binary.extend(b'\0'*((-len(binary))%4));offset=len(binary);fmt='f' if kind==5126 else 'I'
  flat=[v for row in rows for v in row];binary.extend(struct.pack('<'+fmt*len(flat),*flat))
  view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(flat)*4})
  values=[tuple(f32(v) for v in row) if kind==5126 else tuple(row) for row in rows]
  a={'bufferView':view,'componentType':kind,'count':len(rows),'type':{1:'SCALAR',2:'VEC2',3:'VEC3'}[width]}
  if width==3:a['min']=[min(v[i] for v in values) for i in range(3)];a['max']=[max(v[i] for v in values) for i in range(3)]
  idx=len(doc['accessors']);doc['accessors'].append(a);return idx
 for m in meshes:
  if m['region'] not in material:
   material[m['region']]=len(doc['materials']);doc['materials'].append({'name':'Path_'+m['region'].replace(' ',''),'pbrMetallicRoughness':{'baseColorFactor':[v/255 for v in m['pathRGB']]+[1],'metallicFactor':0,'roughnessFactor':.9},'doubleSided':False})
  positions=[[-v[0],v[1],-v[2]] if compensate else list(v) for v in m['localVertices']]
  normal=[[0,1,0]]*len(positions);indices=[[i] for i in range(len(positions))]
  prim={'attributes':{'POSITION':accessor(positions,3),'NORMAL':accessor(normal,3),'TEXCOORD_0':accessor(m['uvs'],2)},'indices':accessor(indices,1,5125),'material':material[m['region']],'mode':4}
  mi=len(doc['meshes']);doc['meshes'].append({'name':m['id'],'primitives':[prim]})
  pivot=m['pivot'];translation=[-pivot[0],pivot[1],-pivot[2]] if compensate else pivot
  ni=len(doc['nodes']);doc['nodes'][0]['children'].append(ni);doc['nodes'].append({'name':m['id'],'mesh':mi,'translation':translation,'extras':{'ArtOwner':'BrainrotExpedition_MapArt','PlacementId':m['id'],'CanonicalRobloxPivot':pivot,'CompactGeometryHash':m['routeGeometryHash']}})
 doc['buffers']=[{'byteLength':len(binary)}];js=canonical(doc);js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4)
 raw=struct.pack('<4sII',b'glTF',2,12+8+len(js)+8+len(binary))+struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(binary),b'BIN\0')+binary
 return raw,doc,bytes(binary)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--plan',type=Path,default=ROOT/'docs/map-compaction/RouteBoundaryDraft.json');ap.add_argument('--output',type=Path,default=ROOT/'tools/map-compaction/generated');ap.add_argument('--selected-interior-fit-proof',type=Path);args=ap.parse_args()
 plan,plan_sha=read(args.plan);old,old_sha=read(ROOT/'assets/map-art/routes/NarrowedRouteManifest.json');data,data_sha=read(ROOT/'assets/map-art/InstallMapArtData.json')
 assert len(plan['routes'])==85 and len(plan['connectivityCaps'])==26 and len(plan['gateAprons'])==6
 assert plan['routePointsCanonicalSHA256']==old['routePointsCanonicalSHA256']
 source_files={p:sha((ROOT/p).read_bytes()) for p in ['assets/map-art/BuildMapArtRoutes.py','assets/map-art/BuildMapArtRouteUV.py','assets/map-art/BuildMapArtStudioRoadImport.py','assets/map-art/routes/NarrowedRouteManifest.json']}
 floor_regions=defaultdict(list)
 for f in plan['floors']:floor_regions[f['regionId']].append(box(f['x0'],f['z0'],f['x1'],f['z1']))
 region_floors={REGIONS[k]:unary_union(v) for k,v in floor_regions.items()};floor_union=unary_union(list(region_floors.values()))
 route_shapes=defaultdict(list)
 for p in plan['routePrimitives']:route_shapes[p['routeId']].append(Polygon(p['polygon']))
 routes={k:unary_union(v) for k,v in route_shapes.items()}
 apron_reports=[]
 for a in plan['gateAprons']:
  g,n,offset,w=a['ground'],a['normal'],a['lateralRouteOffset'],a['ordinaryWidth'];half=w/2
  # Preserve actual former24-wide centered throats. Offset approaches keep the
  # transformed original lane and their existing union connector. New prompt
  # requires16-stud tapers for every gate, irrespective of old8-stud main tapers.
  off=abs(offset)>1e-8;lo=min(-12,offset-half) if off else -12;hi=max(12,offset+half) if off else 12
  domain=localpoly(g,n,[(-48,offset-half),(48,offset-half),(48,offset+half),(-48,offset+half)])
  desired=localpoly(g,n,[(-48,offset-half),(-32,lo),(32,lo),(48,offset-half),(48,offset+half),(32,hi),(-32,hi),(-48,offset+half)])
  before=routes[a['routeId']];routes[a['routeId']]=unary_union([before.difference(domain),desired.intersection(floor_union)])
  apron_reports.append({'id':a['id'],'routeId':a['routeId'],'ground':g,'ordinaryWidth':w,'throatClearWidth':24,'throatEachSide':32,'taperEachSide':16,'lateralRouteOffset':offset,'localLateralBounds':[lo,hi],'domainPolygons':geometry(domain),'surfacePolygons':geometry(desired),'changedArea':before.symmetric_difference(routes[a['routeId']]).area,'graphPolicy':'Existing gate connector/apron only; every semantic control point stays frozen at T(source).','nativeDriving':'NotRun'})
 uncut=unary_union(list(routes.values()));raw_mask=uncut.intersection(floor_union)
 assert raw_mask.is_valid and raw_mask.geom_type=='Polygon','Rebuilt complete route surface is disconnected'
 mask=set_precision(raw_mask,1e-6)
 assert mask.is_valid and mask.geom_type=='Polygon'
 vertex_distance=max([Point(v).distance(mask) for ring in [raw_mask.exterior,*raw_mask.interiors] for v in ring.coords]+[Point(v).distance(raw_mask) for ring in [mask.exterior,*mask.interiors] for v in ring.coords])
 assert vertex_distance<=2e-6 and raw_mask.difference(mask.buffer(1e-5)).area<1e-8 and mask.difference(raw_mask.buffer(1e-5)).area<1e-8
 assert raw_mask.symmetric_difference(mask).area<.01
 route_geometry_hash=sha(canonical({'candidate':plan['candidate'],'baselineManagedContentSHA256':plan['baselineManagedContentSHA256'],'sourceRouteHash':plan['routePointsCanonicalSHA256'],'mask':geometry(mask),'topY':old['topY'],'material':'Glacier','variant':'Bingus_Saved_Studs_13719188279','studsPerTile':.25}))
 meshes=[];cover=[];expected_ids={g['id'] for g in old['groups']};c=plan['candidate']
 for region,region_floor in sorted(region_floors.items()):
  regional=mask.intersection(region_floor)
  for ix in range(4):
   for iz in range(3):
    x0,x1=[mapped_axis(v,0,c) for v in (-1091+640*ix,-1091+640*(ix+1))];z0,z1=[mapped_axis(v,2,c) for v in (-958+640*iz,-958+640*(iz+1))]
    group_mask=unary_union(polys(regional.intersection(box(x0,z0,x1,z1))))
    if group_mask.area<=EPS:continue
    group_mask=set_precision(group_mask,1e-6);rid=f'Path_{region.replace(" ","")}_{ix}_{iz}'
    xlo,zlo,xhi,zhi=group_mask.bounds;px,pz=(xlo+xhi)/2,(zlo+zhi)/2
    triangles=sorted(polys(constrained_delaunay_triangles(group_mask)),key=lambda p:(p.centroid.x,p.centroid.y,p.bounds))
    vertices=[];uvs=[];triangle_shapes=[];dropped_area=0
    for tri in triangles:
     coords=list(tri.exterior.coords)[:3];assert len(coords)==3
     # Roblox +Y corresponds to clockwise winding in numerical X/Z.
     up=(coords[1][1]-coords[0][1])*(coords[2][0]-coords[0][0])-(coords[1][0]-coords[0][0])*(coords[2][1]-coords[0][1])
     if up<0:coords=[coords[0],coords[2],coords[1]]
     local=[[f32(x-px),0.0,f32(z-pz)] for x,z in coords]
     up=(local[1][2]-local[0][2])*(local[2][0]-local[0][0])-(local[1][0]-local[0][0])*(local[2][2]-local[0][2])
     if up<=0:
      assert tri.area<1e-5,'Float32 erased a meaningful road triangle';dropped_area+=tri.area;continue
     vertices.extend(local);uvs.extend([[f32((x-xlo)/(xhi-xlo)),f32(1-(z-zlo)/(zhi-zlo))] for x,z in coords]);triangle_shapes.append(Polygon([(v[0]+px,v[2]+pz) for v in local]))
    rendered=unary_union(triangle_shapes)
    assert len(vertices)//3<=20000 and rendered.hausdorff_distance(group_mask)<.0001
    assert rendered.symmetric_difference(group_mask).area<.02
    cover.append(group_mask)
    meshes.append({'id':rid,'region':region,'cell':[ix,iz],'pivot':[px,old['topY'],pz],'size':[xhi-xlo,0,zhi-zlo],'boundsXZ':[xlo,zlo,xhi,zhi],'pathRGB':data['palettes'][region]['Path'],'triangles':len(vertices)//3,'localVertices':vertices,'uvs':uvs,'polygons':geometry(group_mask),'routeGeometryHash':route_geometry_hash,'float32CoverageDifferenceArea':rendered.symmetric_difference(group_mask).area,'float32HausdorffErrorStuds':rendered.hausdorff_distance(group_mask),'droppedFloat32DegenerateArea':dropped_area,'cellBoundsXZ':[x0,z0,x1,z1]})
 rebuilt=unary_union(cover);assert rebuilt.symmetric_difference(mask).area<.01
 ids={m['id'] for m in meshes};assert ids==expected_ids,f'Report changed group IDs before import: new={ids-expected_ids},missing={expected_ids-ids}'
 assert len(meshes)==27
 args.output.mkdir(parents=True,exist_ok=True)
 canonical_raw,doc,binary=encode_meshes(meshes);import_raw,idoc,ibinary=encode_meshes(meshes,True)
 (args.output/'CompactRoadsCanonical.glb').write_bytes(canonical_raw);(args.output/'CompactRoadsStudioImport.glb').write_bytes(import_raw)
 # Auditable standard OBJ, with source world coordinates and authored source UVs.
 lines=['# Compact roads; canonical Roblox XYZ, +Y normals, saved-stud material','vn 0 1 0'];vbase=0
 for m in meshes:
  lines.append('o '+m['id']);p=m['pivot']
  lines.extend(f'v {v[0]+p[0]:.17g} {v[1]+p[1]:.17g} {v[2]+p[2]:.17g}' for v in m['localVertices']);lines.extend(f'vt {u:.17g} {1-v:.17g}' for u,v in m['uvs'])
  for i in range(0,len(m['localVertices']),3):lines.append('f '+' '.join(f'{vbase+j+1}/{vbase+j+1}/1' for j in [i,i+1,i+2]))
  vbase+=len(m['localVertices'])
 (args.output/'CompactRoadsCanonical.obj').write_text('\n'.join(lines)+'\n')
 expected=[]
 for m in meshes:
  vv=m['localVertices'];triangles=[[vv[i+j]+m['uvs'][i+j] for j in range(3)] for i in range(0,len(vv),3)]
  expected.append({'id':m['id'],'region':m['region'],'pivot':m['pivot'],'size':m['size'],'triangles':triangles,'localBounds':[[min(v[i] for v in vv) for i in range(3)],[max(v[i] for v in vv) for i in range(3)]],'pathRGB':m['pathRGB']})
 write(args.output/'CompactRoadExpectedGeometry.json',expected)
 clean=[{k:v for k,v in m.items() if k not in ['localVertices','uvs']} for m in meshes]
 report={'schemaVersion':1,'migrationId':'CompactMap_V1','status':'ProvisionalSourceExactNativeImportPrepared','nativeImportStatus':'NotRun','selectedCandidate':None,'finalCandidateApproved':False,'worldInstalled':False,'candidate':c,'baselineManagedContentSHA256':plan['baselineManagedContentSHA256'],'sourceBundleSHA256':plan['sourceBundleSHA256'],'sourceRoutePointSHA256':plan['routePointsCanonicalSHA256'],'routeGeometryHash':route_geometry_hash,'sourceDraftPath':str(args.plan),'sourceDraftSHA256':plan_sha,'sourceGroupsManifestSHA256':old_sha,'paletteManifestSHA256':data_sha,'groups':clean,'meshGroups':len(clean),'triangles':sum(g['triangles'] for g in clean),'corners':sum(g['triangles']*3 for g in clean),'topY':old['topY'],'preparedBoundingThickness':old['thickness'],'physicalFloorReplacement':False,'canonicalGLB':{'file':'CompactRoadsCanonical.glb','sha256':sha(canonical_raw),'bytes':len(canonical_raw)},'studioImportGLB':{'file':'CompactRoadsStudioImport.glb','sha256':sha(import_raw),'bytes':len(import_raw),'compensation':'Measured native Y180 baked into XZ positions/normals/node translations','embeddedImages':0},'geometryChecks':{'surfaceComponentCount':len(polys(mask)),'maskArea':mask.area,'floorClippedOutsideArea':uncut.difference(floor_union).area,'precisionGridStuds':1e-6,'maximumInputOutputVertexSetDistance':vertex_distance,'positiveAreaOutsidePrecisionTolerance':raw_mask.difference(mask.buffer(1e-5)).area+mask.difference(raw_mask.buffer(1e-5)).area,'precisionCoverageDifferenceArea':raw_mask.symmetric_difference(mask).area,'regionalPartitionCoverageDifferenceArea':rebuilt.symmetric_difference(mask).area,'original27GroupIDsPreserved':ids==expected_ids,'maximumFloat32HausdorffError':max(g['float32HausdorffErrorStuds'] for g in clean),'totalFloat32CoverageDifferenceArea':sum(g['float32CoverageDifferenceArea'] for g in clean)},'material':{'base':'Glacier','variant':'Bingus_Saved_Studs_13719188279','studsPerTile':.25,'studMaterialAssetId':13719188279,'TextureID':'','SurfaceAppearanceCount':0,'historicalAtlasUVStatus':'Superseded by current saved-stud material; new UVs are geometry-verified source values only'},'gateAprons':apron_reports,'oldAssetsUnchanged':all(sha((ROOT/p).read_bytes())==h for p,h in source_files.items()),'sourceAssetHashes':source_files,'limitations':['Actual native every-corner readback is mandatory before preparation/application.','Source exact clearances do not prove loaded-cart driving or gate neighbor access.','Whole-map candidate selection and owner fit remain parent-owned; this builder cannot bypass fit gates.']}
 if args.selected_interior_fit_proof:
  fit,fitsha=read(args.selected_interior_fit_proof);assert fit['b']==c['b'] and fit['nativeProposalFitPassed'] and fit['nativeExecutionPassed']
  report.update(status='SelectedSourceGeometryReadyForNativeImport',selectedCandidate=c,candidateSelectedForNativeGeometryImport=True,interiorFitEvidence={'path':str(args.selected_interior_fit_proof),'sha256':fitsha,'nativeProposalFitPassed':True,'fullAcceptancePassed':fit['fullAcceptancePassed']},geometryBatchReadyForNativeImport=True)
 write(args.output/'CompactRouteMeshManifest.json',report)
 obstacle_rows=[]
 for w in plan['walls']:
  x,y,z=w['cframe'][:3];sx,sy,sz=w['size'];obstacle_rows.append({'id':w['id'],'kind':'RegionWall','regionIds':w['regionPair'],'x0':x-sx/2,'x1':x+sx/2,'z0':z-sz/2,'z1':z+sz/2,'y0':y-sy/2,'y1':y+sy/2,'polygon':list(box(x-sx/2,z-sz/2,x+sx/2,z+sz/2).exterior.coords)})
 clearance={'schemaVersion':1,'migrationId':'CompactMap_V1','routeGeometryHash':route_geometry_hash,'baselineManagedContentSHA256':plan['baselineManagedContentSHA256'],'candidate':c,'topY':old['topY'],'roadWidthPolicy':'28 main/spine;36 Camp loop/diagonal/exterior;24 secondary/cart;20 house/service;44 junction;64 pad','roadUnionPolygons':geometry(mask),'roadUnionArea':mask.area,'sourceComponentCount':1,'sceneryClearanceStuds':2,'sceneryForbiddenPolygons':geometry(mask.buffer(2,join_style=2)),'routePolygonsByOwner':[{'routeId':r['id'],'role':r['role'],'width':r['width'],'controlPoints':r['controlPoints'],'polygons':geometry(routes[r['id']].intersection(floor_union))} for r in plan['routes']],'gateAprons':apron_reports,'wallObstacles':obstacle_rows,'wallColliderUnionPolygons':geometry(unary_union([Polygon(w['polygon']) for w in obstacle_rows])),'gateCrossingPolicy':[{'id':x['id'],'routeId':x['routeId'],'accessPolicy':x['accessPolicy'],'owningGate':x.get('owningGate'),'regionPair':x['regionPair'],'apertureWidth':x['apertureWidth']} for x in plan['crossings']],'functionalApproachRule':'Per-owner base/service approach validation remains separate; do not exclude an approved approach owner from its own intended existing connector.'}
 write(args.output/'CompactRouteClearance.json',clearance)
 print(json.dumps({k:report[k] for k in ['status','meshGroups','triangles','corners','routeGeometryHash','geometryChecks','studioImportGLB']},indent=2))
if __name__=='__main__':main()
