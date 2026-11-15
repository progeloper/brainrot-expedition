"""Independent exhaustive Camp footprint fit evidence at all permitted4-stud/cardinal roots."""
import json,math,sys
from pathlib import Path
import numpy as np,shapely
from shapely.geometry import box,Point
from shapely.ops import unary_union
from geometry import *
from boundary import plan_boundary
ROOT=Path(__file__).resolve().parents[2]
def translated_shapes(local,xy):
    arrays=[]
    for p in polygons(local):
        ext=np.asarray(p.exterior.coords);arr=shapely.polygons(xy[:,None,:]+ext[None,:,:])
        for ring in p.interiors:arr=shapely.difference(arr,shapely.polygons(xy[:,None,:]+np.asarray(ring.coords)[None,:,:]))
        arrays.append(arr)
    return shapely.union_all(np.asarray(arrays),axis=0)
def examine(g,a):
    p={r['id']:r for r in a['prototypes']};region=decode_geometry(g['regions']['REGION_CAMP']);road=decode_geometry(g['roadPolygons']).buffer(6,join_style=2);fixed=unary_union([decode_geometry(r['polygons'])for r in g['fixedReservations']]);b=plan_boundary(g,p,depth_override=8);walls=decode_geometry(b['groundPolygons']);body=local_shape(p['BurrowCore']).union(local_shape(p['BurrowBrow']));local=body.union(box(-18,-48,18,0));candidates=grid_candidates(region,(0,0),origin=tuple(g['origin']),yaws=(0,));xy=np.asarray([[c[2],c[3]]for c in candidates]);rows=[];best=None
    for yaw in (0,90,180,270):
        shape=affinity.rotate(local,-yaw,origin=(0,0));actual=translated_shapes(shape,xy);inregion=shapely.covers(region,actual);roadHit=shapely.intersects(actual,road);fixedHit=shapely.intersects(actual,fixed);wallsHit=shapely.intersects(actual,walls);fits=inregion&~roadHit&~fixedHit&~wallsHit
        indices=np.flatnonzero(inregion);blocks=unary_union([road,fixed,walls]);areas=shapely.area(shapely.intersection(actual[indices],blocks));j=int(np.argmin(areas));i=int(indices[j]);over=float(areas[j]);x,z=map(float,xy[i]);shapeAt=actual[i]
        record={'yaw':yaw,'candidateRoots':len(xy),'completeProjectionWithinCamp':int(inregion.sum()),'withinCampAndRoadClear':int((inregion&~roadHit).sum()),'withinCampRoadAndFixedClear':int((inregion&~roadHit&~fixedHit).sum()),'validWithMinimum8StudBoundaryDepth':int(fits.sum()),'bestReviewCandidate':{'root':[x,g['groundY'],z],'yaw':yaw,'overlapUnionArea':over,'roadShoulderOverlapArea':shapeAt.intersection(road).area,'fixedOverlapArea':shapeAt.intersection(fixed).area,'minimumDepthBoundaryOverlapArea':shapeAt.intersection(walls).area,'polygons':encode_geometry(shapeAt),'fixedOwners':[r['id']for r in g['fixedReservations']if shapeAt.intersection(decode_geometry(r['polygons'])).area>1e-6]}}
        rows.append(record)
        if best is None or(over,x,z,yaw)<best[0]:best=((over,x,z,yaw),record['bestReviewCandidate'])
    return{'status':'CampRequiredPlacementConflict'if sum(r['validWithMinimum8StudBoundaryDepth']for r in rows)==0 else'CampCandidateFound','baselineSceneSHA256':g['baselineSceneSHA256'],'assetSourceSHA256':a['sourceSHA256'],'method':'Independent vectorized exhaustive4-stud-grid/cardinal search, exact visible Core+Brow projection plus36x48 apron. No other new hero/prop/clearing reserved; minimum8cliffs atsame frozen seams. Protected frozen road shoulder6 and current12bases/6services reservations retained.','testedCandidates':sum(r['candidateRoots']for r in rows),'yawEvidence':rows,'bestReviewCandidateUninstalled':best[1],'worldWrites':0,'sourceWrites':0,'fullOpeningRetained':{'W':24,'H':22},'nativePersistentSourceAssetPending':True,'exceptionBasis':'Bible section6 explicitly permits full asset plus documented Camp placement conflict; no squeezing/shrinking/moving functional systems.'}
if __name__=='__main__':
    g=json.load(open(ROOT/'docs/environment-v2/CurrentGeometry.json'));a=json.load(open(ROOT/'assets/environment-v2/EnvironmentAssetSource.json'));r=examine(g,a);(ROOT/'docs/environment-v2/CampBurrowExhaustiveFit.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'status':r['status'],'testedCandidates':r['testedCandidates'],'rows':[(q['yaw'],q['withinCampRoadAndFixedClear'],q['validWithMinimum8StudBoundaryDepth'])for q in r['yawEvidence']],'best':{k:v for k,v in r['bestReviewCandidateUninstalled'].items()if k not in['polygons','fixedOwners']}}))
