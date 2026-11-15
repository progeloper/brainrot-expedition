#!/usr/bin/env python3
"""Standard GLB geometry packing and independent binary corner readback.
Inputs are canonical Roblox XYZ meshes with per-corner normals/UVs. This module
never assigns native IDs, opens Studio, or writes any existing art source.
"""
from __future__ import annotations
import hashlib,json,math,struct
from pathlib import Path

COMPONENTS={5121:('B',1),5123:('H',2),5125:('I',4),5126:('f',4)}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def sha(raw):return hashlib.sha256(raw).hexdigest()
def f32(v):return struct.unpack('<f',struct.pack('<f',v))[0]
def frows(v):return [[f32(x) for x in row] for row in v]
def sub(a,b):return [a[i]-b[i] for i in range(3)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def length(a):return math.sqrt(dot(a,a))

def read_glb(path):
 raw=Path(path).read_bytes();magic,version,total=struct.unpack_from('<4sII',raw)
 assert magic==b'glTF' and version==2 and total==len(raw),'Invalid GLB2 header/length'
 chunks=[];at=12
 while at<len(raw):
  n,t=struct.unpack_from('<I4s',raw,at);at+=8;assert n%4==0 and at+n<=len(raw)
  chunks.append((t,raw[at:at+n]));at+=n
 assert len(chunks)==2 and chunks[0][0]==b'JSON' and chunks[1][0]==b'BIN\0'
 doc=json.loads(chunks[0][1]);assert len(doc['buffers'])==1 and 'uri' not in doc['buffers'][0]
 assert doc['buffers'][0]['byteLength']<=len(chunks[1][1])
 return doc,chunks[1][1],raw

def accessor_rows(doc,binary,index):
 a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
 assert not a.get('normalized',False) and not a.get('sparse') and v['buffer']==0
 fmt,n=COMPONENTS[a['componentType']];width=WIDTH[a['type']];stride=v.get('byteStride',n*width)
 assert stride>=n*width and stride%n==0
 offset=v.get('byteOffset',0)+a.get('byteOffset',0)
 assert offset>=0 and offset+(a['count']-1)*stride+n*width<=v.get('byteOffset',0)+v['byteLength']
 return [list(struct.unpack_from('<'+fmt*width,binary,offset+i*stride)) for i in range(a['count'])]

def decoded_groups(doc,binary):
 parents={}
 for i,n in enumerate(doc['nodes']):
  for child in n.get('children',[]):assert child not in parents;parents[child]=i
 groups={}
 for ni,node in enumerate(doc['nodes']):
  if 'mesh' not in node:continue
  assert node['name'] not in groups and not any(k in node for k in ('matrix','rotation','scale'))
  prims=doc['meshes'][node['mesh']]['primitives'];assert len(prims)==1
  p=prims[0];assert p.get('mode',4)==4 and not p.get('targets')
  pos=accessor_rows(doc,binary,p['attributes']['POSITION']);uv=accessor_rows(doc,binary,p['attributes']['TEXCOORD_0']);norm=accessor_rows(doc,binary,p['attributes']['NORMAL'])
  assert len(pos)==len(uv)==len(norm)
  ids=[r[0] for r in accessor_rows(doc,binary,p['indices'])];assert len(ids)%3==0 and all(0<=v<len(pos) for v in ids)
  assert set(ids)==set(range(len(pos))),'Unreferenced encoded vertices'
  parent=doc['nodes'][parents[ni]]['name']
  groups[node['name']]={'id':node['name'],'rootId':parent,'translation':node.get('translation',[0,0,0]),'positions':pos,'normals':norm,'uvs':uv,'indices':ids,'material':doc['materials'][p['material']],'extras':node.get('extras',{})}
 return groups

def encode(groups,compensate=False):
 doc={'asset':{'version':'2.0','generator':'CompactNativeGeometry_v1','extras':{'CoordinateSystem':'Canonical Roblox XYZ Y-up','NativeImporterCompensation':'diag(-1,1,-1)' if compensate else 'None','SurfaceStyle':'SavedBingusStuds','StudsPerTile':.25}},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'CompactMapAssets','children':[]}],'meshes':[],'accessors':[],'bufferViews':[],'materials':[]}
 binary=bytearray();roots={};materials={}
 def add_accessor(rows,w,kind=5126):
  binary.extend(b'\0'*((-len(binary))%4));offset=len(binary);fmt=COMPONENTS[kind][0];size=COMPONENTS[kind][1]
  flat=[x for row in rows for x in row];assert all(math.isfinite(x) for x in flat)
  binary.extend(struct.pack('<'+fmt*len(flat),*flat));vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(flat)*size})
  values=frows(rows) if kind==5126 else rows
  a={'bufferView':vi,'componentType':kind,'count':len(rows),'type':{1:'SCALAR',2:'VEC2',3:'VEC3'}[w]}
  if w==3:a.update(min=[min(x[j] for x in values) for j in range(3)],max=[max(x[j] for x in values) for j in range(3)])
  ai=len(doc['accessors']);doc['accessors'].append(a);return ai
 for g in groups:
  root=g['rootId']
  if root not in roots:
   roots[root]=len(doc['nodes']);doc['nodes'][0]['children'].append(roots[root]);doc['nodes'].append({'name':root,'children':[]})
  rgb=tuple(g['rgb'])
  if rgb not in materials:
   materials[rgb]=len(doc['materials']);doc['materials'].append({'name':g['id']+'_RGB','pbrMetallicRoughness':{'baseColorFactor':[x/255 for x in rgb]+[1],'metallicFactor':0,'roughnessFactor':.9},'doubleSided':False})
  positions=[[-p[0],p[1],-p[2]] if compensate else p for p in g['positions']]
  normals=[[-n[0],n[1],-n[2]] if compensate else n for n in g['normals']]
  primitive={'attributes':{'POSITION':add_accessor(positions,3),'NORMAL':add_accessor(normals,3),'TEXCOORD_0':add_accessor(g['uvs'],2)},'indices':add_accessor([[i] for i in range(len(positions))],1,5125),'material':materials[rgb],'mode':4}
  mi=len(doc['meshes']);doc['meshes'].append({'name':g['id'],'primitives':[primitive]})
  centre=g['centre'];translation=[-centre[0],centre[1],-centre[2]] if compensate else centre
  ni=len(doc['nodes']);doc['nodes'][roots[root]]['children'].append(ni);doc['nodes'].append({'name':g['id'],'mesh':mi,'translation':frows([translation])[0],'extras':{'RootId':root,'CanonicalCentre':centre,'CanonicalRole':g['role'],'ExportGroup':g['groupId'],'ArtOwner':'BrainrotExpedition_MapArt'}})
 doc['buffers']=[{'byteLength':len(binary)}];js=canonical(doc);js+=b' '*((-len(js))%4);binary+=b'\0'*((-len(binary))%4)
 return struct.pack('<4sII',b'glTF',2,12+8+len(js)+8+len(binary))+struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(binary),b'BIN\0')+binary

def validate_binary(path,source,compensate=False):
 doc,binary,raw=read_glb(path);actual=decoded_groups(doc,binary)
 assert not doc.get('images') and not doc.get('textures') and not doc.get('animations') and not doc.get('cameras') and not doc.get('extensionsUsed')
 assert set(actual)=={g['id'] for g in source}
 reports=[];corners=0
 for g in source:
  a=actual[g['id']];assert a['rootId']==g['rootId'] and a['indices']==list(range(len(g['positions'])))
  p=[[-v[0],v[1],-v[2]] if compensate else v for v in g['positions']]
  n=[[-v[0],v[1],-v[2]] if compensate else v for v in g['normals']]
  centre=[-g['centre'][0],g['centre'][1],-g['centre'][2]] if compensate else g['centre']
  assert a['positions']==frows(p) and a['normals']==frows(n) and a['uvs']==frows(g['uvs']) and a['translation']==frows([centre])[0],'Encoded float32 corner or pivot differs from original source'
  assert a['material']['pbrMetallicRoughness']['baseColorFactor']==[v/255 for v in g['rgb']]+[1]
  max_normal_spread=0;min_winding_dot=math.inf
  for i in range(0,len(p),3):
   pp=a['positions'][i:i+3];nn=a['normals'][i:i+3]
   spread=max(length(sub(v,nn[0])) for v in nn);max_normal_spread=max(max_normal_spread,spread);assert spread<=1e-6
   winding=dot(cross(sub(pp[1],pp[0]),sub(pp[2],pp[0])),nn[0]);assert winding>0,'Winding does not follow authored flat normal'
   min_winding_dot=min(min_winding_dot,winding)
   assert all(abs(length(v)-1)<1e-6 for v in nn)
  corners+=len(p)
  reports.append({'id':g['id'],'rootId':g['rootId'],'role':g['role'],'triangles':len(p)//3,'checkedCorners':len(p),'sourceFloat32CornerErrors':0,'maximumWithinFaceNormalSpread':max_normal_spread,'minimumWindingDotNormal':min_winding_dot,'canonicalCentre':g['centre']})
 return {'status':'SourceBinaryPassed; actual native readback NotRun','file':str(path),'sha256':sha(raw),'bytes':len(raw),'compensationXZApplied':compensate,'groups':reports,'checkedGroups':len(source),'triangles':corners//3,'checkedCorners':corners,'embeddedImages':0,'nativeAssetIdsInvented':0,'worldMutations':0}
