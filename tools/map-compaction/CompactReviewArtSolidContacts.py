#!/usr/bin/env python3
"""Source corner/wall-slab clipping tied to preserved native MeshId evidence.
This is source geometry review, not new native EditableMesh readback or collision.
"""
import argparse,json,hashlib,math
from pathlib import Path
from CompactNativeGeometry import read_glb,decoded_groups,sub,cross,length
from CompactCheckSiteGeometry import props,world,transform,load,write
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
def clip(poly,axis,edge,less):
 out=[]
 for a,b in zip(poly,poly[1:]+poly[:1]):
  ia=a[axis]<=edge if less else a[axis]>=edge;ib=b[axis]<=edge if less else b[axis]>=edge
  if ia:out.append(a)
  if ia!=ib:
   t=(edge-a[axis])/(b[axis]-a[axis]);out.append([a[j]+t*(b[j]-a[j]) for j in range(3)])
 return out

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--plan',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 p=load(a.plan);m=load(ROOT/'docs/map-compaction/BeforeManifest.json');r=next(v for v in m['objects'] if v['path']=='Workspace.MapBlockout.MapArt.Scenery.Volcano_04_TallB.Primary');model=next(v for v in m['objects'] if v['path']=='Workspace.MapBlockout.MapArt.Scenery.Volcano_04_TallB');assert model['attributes']['PrototypeId']=='IceCluster_A'
 canonical=ROOT/'assets/map-art/generated/ASSET_EXPORT/AllFinalPrototypesCanonical.glb';d,b,raw=read_glb(canonical);mesh=decoded_groups(d,b)['IceCluster_A_Primary'];v=mesh['positions'];pr=props(r);cf=pr['CFrame'];low=[min(q[i] for q in v) for i in range(3)];high=[max(q[i] for q in v) for i in range(3)];ratio=[pr['Size'][i]/(high[i]-low[i]) for i in range(3)]
 source_root=model['pivot']['value'];anchor=transform(source_root[:3],p['candidate']);old_world=[world([q[i]*ratio[i] for i in range(3)],cf) for q in v];new_world=[[anchor[i]+(q[i]-source_root[i])*.75 for i in range(3)] for q in old_world]
 wall=next(w for w in p['walls'] if w['id']=='RW_REGION_CAMP_REGION_VOLCANO_R12_002');cx,cy,cz=wall['cframe'][:3];sx,sy,sz=wall['size'];wl=[cx-sx/2,cy-sy/2,cz-sz/2];wh=[cx+sx/2,cy+sy/2,cz+sz/2]
 ids=mesh['indices'];contacts=[];ys=[]
 for k in range(0,len(ids),3):
  tri=[new_world[j] for j in ids[k:k+3]];poly=tri
  for axis in range(3):
   if not poly:break
   poly=clip(poly,axis,wl[axis],False)
   if poly:poly=clip(poly,axis,wh[axis],True)
  if len(poly)<3:continue
  ar=sum(length(cross(sub(poly[j],poly[0]),sub(poly[j+1],poly[0])))/2 for j in range(1,len(poly)-1))
  if ar<=1e-10:continue
  ys.extend(q[1] for q in poly);contacts.append({'sourceTriangle':k//3+1,'clippedSourceWorldPolygon':poly,'clippedSurfaceArea':ar,'sourceWorldTriangle':tri})
 sourcebb=[[min(q[i] for q in new_world) for i in range(3)],[max(q[i] for q in new_world) for i in range(3)]]
 result={'status':'SourceFloat32MeshCornerClipping; current native solid readback NotRun','candidate':p['candidate'],'placementId':'Volcano_04_TallB','actualPrototypeId':'IceCluster_A','actualPartPath':r['path'],'actualMeshId':r['mesh']['MeshId'],'priorNativeGeometryPassed':r['attributes'].get('NativeGeometryPassed'),'sourceCanonicalGLBSHA256':hashlib.sha256(raw).hexdigest(),'sourceFrozenGeometrySHA256':r['attributes'].get('FrozenSourceSHA256'),'sourceWorldPivot':source_root,'mappedGroundPivot':anchor,'ordinaryScaleMultiplier':.75,'sourceMeshNativeScaleXYZ':ratio,'wallId':wall['id'],'wallBoundsWorld':[wl,wh],'renderedSourceBoundsWorld':sourcebb,'maximumXPenetrationStuds':max(0,wh[0]-sourcebb[0][0]),'groundY':p['candidate']['origin'][1],'sourceTriangles':len(ids)//3,'sourceTrianglesIntersectingWallSlab':len(contacts),'contactWorldYBounds':[min(ys),max(ys)] if ys else None,'maximumContactAboveGroundStuds':max(ys)-p['candidate']['origin'][1] if ys else None,'sourceContactSurfaceArea':sum(q['clippedSurfaceArea'] for q in contacts),'capturedFlags':{k:pr[k] for k in ['CanCollide','CanTouch','CanQuery','Anchored','CastShadow']},'contacts':contacts,'classification':'Derive from explicit Y/contact numbers; no trunk inference from placement suffix Tall','nativeCornerProofToleranceStuds':.01,'newNativeEditableMeshReadbackByThisTool':False,'worldMutations':0}
 write(a.output,result);print(json.dumps({k:result[k] for k in ['actualPrototypeId','actualMeshId','maximumXPenetrationStuds','sourceTriangles','sourceTrianglesIntersectingWallSlab','contactWorldYBounds','maximumContactAboveGroundStuds','sourceContactSurfaceArea']},indent=2))
if __name__=='__main__':main()
