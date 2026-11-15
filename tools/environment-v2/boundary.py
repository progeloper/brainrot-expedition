"""Current-layout boundary planner; no live writes and no map transform."""
from __future__ import annotations
import math
from shapely.geometry import box,Point
from shapely.ops import unary_union
from geometry import *
DEPTHS=(40,32,24,16,8)

def rectangles(geom):
    """Disjoint axis rectangles, merging adjacent horizontal strips with identical X extents."""
    ps=polygons(geom)
    zs=sorted(set(round(z,8)for p in ps for x,z in p.exterior.coords))
    out=[];active={}
    for za,zb in zip(zs,zs[1:]):
        if zb-za<1e-7:continue
        xs=[]
        for line in lines(geom.intersection(LineString([(geom.bounds[0]-1,(za+zb)/2),(geom.bounds[2]+1,(za+zb)/2)]))):
            lo,_,hi,_=line.bounds
            if hi-lo>1e-7:xs.append((round(lo,8),round(hi,8)))
        current={}
        for lo,hi in sorted(xs):
            key=(lo,hi)
            if key in active and abs(active[key][3]-za)<1e-7:r=active[key];r[3]=zb
            else:r=[lo,za,hi,zb];out.append(r)
            current[key]=r
        active=current
    result=[box(*r)for r in out]
    assert abs(unary_union(result).symmetric_difference(geom).area)<1e-4
    return result

def plan_boundary(g,prototypes,depth_override=None,reuse_outer=True):
    regions={k:decode_geometry(v)for k,v in g['regions'].items()};world=unary_union(list(regions.values()))
    runs=true_boundaries(regions);road=decode_geometry(g['roadPolygons']);fixed=unary_union([decode_geometry(r['polygons'])for r in g['fixedReservations']])
    closed=unary_union([Point(c['intersection'][0],c['intersection'][2]).buffer(c['width']/2+42,cap_style=3)for c in g['closedAlternates']])
    # Only the existing already closed local crossing domains may intersect protected road ground.
    allowedRoad=road.difference(closed);opening_by={o['id']:decode_geometry(o['polygons'])for o in g['openings']}
    # Paid through-road clearing is widened only inside its existing normal 48-stud opening domain.
    protectedOpen={}
    for o in g['openings']:
        shp=opening_by[o['id']];x,y,z=o['ground'];domain=box(x-48,z-48,x+48,z+48)
        if o['paid']:shp=shp.union(road.buffer(6,join_style=2).intersection(domain))
        else:
            # Free 40-wide aperture extends through the full new cliff thickness.
            shp=shp.union(box(x-48,z-20,x+48,z+20))
        protectedOpen[o['id']]=shp
    openingUnion=unary_union(list(protectedOpen.values()));runsOut=[];objects=[];conflicts=[];headers=[]
    retained=[r for r in g['oldWalls']if '.BoundarySeparators.'in r['originalPath']]if reuse_outer else[]
    retainedGround=unary_union([part_projection(r['cframe'],r['size'])for r in retained]);owned=[retainedGround]
    for r in runs:
        attempts=[];selected=None
        for depth in ([depth_override[r['id']]]if isinstance(depth_override,dict)and r['id']in depth_override else[depth_override]if depth_override and not isinstance(depth_override,dict)else DEPTHS):
            rr=dict(r)
            if r['kind']=='Outer':
                mid=run_strip(r,depth);normal=(0,depth/2)if r['axis']=='X' else(depth/2,0)
                if r['fixed']==world.bounds[3]or r['fixed']==world.bounds[2]:normal=tuple(-v for v in normal)
                strip=affinity.translate(mid,xoff=normal[0],yoff=normal[1]);rr['actualFixed']=r['fixed']+normal[1 if r['axis']=='X'else 0]
            else:strip=run_strip(r,depth);rr['actualFixed']=r['fixed']
            cuts=[];cutOwners=[]
            if reuse_outer and r['kind']=='Outer':
                # Preserve continuous existing perimeter segments. Only genuinely absent portions receive new modules.
                for q in retained:
                    b=bounds3(q['cframe'],q['size']);axis=r['axis'];touch=(b['minZ']-TOL<=r['fixed']<=b['maxZ']+TOL)if axis=='X'else(b['minX']-TOL<=r['fixed']<=b['maxX']+TOL)
                    if touch:cuts.append((b['minX'],b['maxX'])if axis=='X'else(b['minZ'],b['maxZ']))
            for id,shp in protectedOpen.items():
                # Full thickness intersection may legitimately reach an incident seam at a corner.
                actual={**r,'fixed':rr['actualFixed']};ivs=prism_intervals(actual,depth,shp)
                if ivs:cuts.extend(ivs);cutOwners.append({'id':id,'intervals':ivs})
            actual={**r,'fixed':rr['actualFixed']}
            candidate=unary_union([run_strip(actual,depth,a,b)for a,b in subtract_intervals(r['first'],r['last'],cuts)])
            candidate=candidate.intersection(world)
            hitFixed=candidate.intersection(fixed).area;hitRoad=candidate.intersection(allowedRoad).area
            attempts.append({'depth':depth,'fixedReservationOverlapArea':hitFixed,'protectedRoadOverlapArea':hitRoad,'cuts':cutOwners})
            if hitFixed<.0001 and hitRoad<.0001:selected=(rr,depth,candidate,cutOwners);break
        if selected is None:
            conflicts.append({'code':'BoundaryDepthLadderNoFit','runId':r['id'],'attempts':attempts})
            rr,depth,candidate,cutOwners=rr,depth,candidate,cutOwners
        else:rr,depth,candidate,cutOwners=selected
        # Stable lexicographic run ownership resolves all T/corner contacts with disjoint solids.
        candidate=candidate.difference(unary_union(owned));owned.append(candidate)
        rects=rectangles(candidate);n=0
        for rect in rects:
            x0,z0,x1,z1=rect.bounds
            alongX=r['axis']=='X';length=(x1-x0)if alongX else(z1-z0);thick=(z1-z0)if alongX else(x1-x0)
            count=max(1,math.ceil(length/256));step=length/count
            for j in range(count):
                n+=1;lo=(x0 if alongX else z0)+j*step;hi=lo+step
                x=(lo+hi)/2 if alongX else(x0+x1)/2;z=(z0+z1)/2 if alongX else(lo+hi)/2
                H=72+[0,12,0,24][(len(objects))%4]
                obj=placed_object(prototypes['CliffRun'],r['id']+f'_Cliff_{n:02d}',r['regionPair'][0]if r['regionPair']else 'REGION_CAMP','Boundary',x,g['groundY'],z,0 if alongX else 90,(step/96,H/72,thick/40))
                obj['boundaryRunId']=r['id'];obj['boundaryKind']=r['kind'];obj['regionPair']=r['regionPair'];obj['coreHeight']=H;obj['depth']=thick;obj['length']=step
                obj['clearanceEvidence']={'selectedDepth':depth,'stableContactOwnership':True,'apertureOwners':cutOwners,'protectedRoadException':'Only captured five already closed crossings'}
                objects.append(obj)
        rr.update({'selectedDepth':depth,'attempts':attempts,'openingCuts':cutOwners,'solidPolygons':encode_geometry(candidate),'moduleCount':n});runsOut.append(rr)
    # One logical header owner per crossing, with disjoint cuboid pieces at a touched corner.
    # Coplanar collinear incident spans merge before physical decomposition.
    for o in g['openings']:
        x,y,z=o['ground'];incident=[r for r in runsOut if any(c['id']==o['id']for c in r['openingCuts'])]
        patches=[]
        for r in incident:
            actual={**r,'fixed':r['actualFixed']}
            cut=next(c for c in r['openingCuts']if c['id']==o['id'])['intervals']
            patches.extend(run_strip(actual,r['selectedDepth'],lo,hi)for lo,hi in cut)
        cover=unary_union(patches);bottom=o['newHeaderUnderside'];H=72;height=g['groundY']+H-bottom
        # Combine adjacent rectangular spans, then partition L/T-shaped corners without volumetric duplicates.
        pieces=[box(*cover.bounds)]
        for idx,rect in enumerate(pieces,1):
            x0,z0,x1,z1=rect.bounds;L=x1-x0;D=z1-z0
            obj=placed_object(prototypes['GateLintel'],o['id']+f'_Header_{idx:02d}',o['regionPair'][0],'Boundary',(x0+x1)/2,bottom,(z0+z1)/2,0,(L/96,height/54,D/40))
            obj['boundaryKind']='GateLintel';obj['openingId']=o['id'];obj['regionPair']=o['regionPair'];obj['length']=max(L,D);obj['depth']=min(L,D);obj['coreHeight']=H;obj['clearanceEvidence']={'underside':bottom,'oldLintelTop':bottom,'clearWidth':24 if o['paid']else 40,'incidentRuns':[r['id']for r in incident],'fullThicknessCornerSealed':True,'physicalPiece':idx,'logicalOpeningOwner':o['id']}
            headers.append(obj)
    # Pairwise ground wall overlap is meaningful; headers are overhead and deliberately touch side walls.
    geoms=[object_geometry(r)for r in objects];pairs=[]
    for i,a in enumerate(geoms):
        for j,b in enumerate(geoms[i+1:],i+1):
            area=a.intersection(b).area
            if area>1e-4:pairs.append({'a':objects[i]['id'],'b':objects[j]['id'],'area':area})
    if pairs:conflicts.append({'code':'BoundaryPositiveGroundOverlap','pairs':pairs})
    total=len(objects)+len(headers)+len(retained)
    if total>64:conflicts.append({'code':'BoundaryModuleCapExceeded','actual':total,'limit':64})
    return {'runs':runsOut,'objects':objects+headers,'floorRuns':len(runs),'sharedRuns':sum(r['kind']=='Shared'for r in runs),'outerRuns':4,'cliffModules':len(objects),'logicalLintels':len(g['openings']),'physicalLintels':len(headers),'retainedOuterCount':len(retained),'retainedOuter':retained,'moduleCount':total,'maximumLength':max(o['length']for o in objects+headers),'conflicts':conflicts,'groundPolygons':encode_geometry(unary_union(geoms+[retainedGround])),'openings':g['openings'],'closedAlternates':g['closedAlternates'],'securityStatus':{'NonRouteBypass':'PendingNativeJumpCartChecks','ClosedPaidThreshold':'NotAchieved','code':'ClosedPaidPhysicalBarrierAbsent','affectedPaidGates':list(g['gates'])},'heightInputs':{'minimum72':72,'measuredFeetRise':7.9361710846,'conservativeJumpRise':8,'measuredAvatarBoundsHeight':6.6161232,'horizontalProbeDistanceMinimum':48,'horizontalCartJumpReach':'PendingActualMeasurement','reachableLaunchSurfaceAnalysis':'PendingFinalPlacedGeometry'}}

def compact_rectangular_cover(geom):
    """Deterministic largest-rectangle partition of an exact orthogonal union, no geometry inflation."""
    import numpy as np,shapely,bisect
    rings=[ring for p in polygons(geom)for ring in [p.exterior,*p.interiors]]
    xs=sorted(set(round(x,8)for ring in rings for x,z in ring.coords));zs=sorted(set(round(z,8)for ring in rings for x,z in ring.coords))
    xc=np.array([(a+b)/2 for a,b in zip(xs,xs[1:])]);zc=np.array([(a+b)/2 for a,b in zip(zs,zs[1:])]);xx,zz=np.meshgrid(xc,zc);cells=shapely.covers(geom,shapely.points(xx,zz));out=[]
    def best_rect(mask,xxs,zzs):
        heights=[0.]*mask.shape[1];best=None
        for row,line in enumerate(mask):
            dz=zzs[row+1]-zzs[row]
            for c,v in enumerate(line):heights[c]=heights[c]+dz if v else 0
            stack=[]
            for col in range(len(heights)+1):
                h=heights[col]if col<len(heights)else 0;start=col
                while stack and stack[-1][1]>h+1e-7:
                    ix,hh=stack.pop();start=ix;x0=xxs[ix];x1=xxs[col];z1=zzs[row+1];z0=z1-hh
                    if x1-x0<=1e-7 or hh<=1e-7:continue
                    score=((x1-x0)*hh,-x0,-z0,-x1,-z1)
                    if best is None or score>best[0]:best=(score,[x0,z0,x1,z1])
                if not stack or stack[-1][1]<h-1e-7:stack.append((start,h))
        return best
    while cells.any():
        h=best_rect(cells,xs,zs);v=best_rect(cells.T,zs,xs);vb=v[1];vr=[vb[1],vb[0],vb[3],vb[2]];hs=h[0];vs=(v[0][0],-vr[0],-vr[1],-vr[2],-vr[3]);r=h[1]if hs>=vs else vr;x0,z0,x1,z1=r
        i0=bisect.bisect_left(xs,x0-1e-6);i1=bisect.bisect_left(xs,x1-1e-6);j0=bisect.bisect_left(zs,z0-1e-6);j1=bisect.bisect_left(zs,z1-1e-6);assert i1>i0 and j1>j0;assert cells[j0:j1,i0:i1].all();cells[j0:j1,i0:i1]=False;out.append(box(*r))
    union=unary_union(out);assert geom.symmetric_difference(union).area<1e-3
    assert abs(sum(r.area for r in out)-geom.area)<1e-3
    return sorted(out,key=lambda p:p.bounds)

def repartition_boundary(b,g,prototypes):
    """Merge source fragments by the exact physical union; closed/aperture geometry is unchanged."""
    old=[o for o in b['objects']if o['boundaryKind']!='GateLintel'];headers=[o for o in b['objects']if o['boundaryKind']=='GateLintel'];geom=unary_union([object_geometry(o)for o in old]);rects=compact_rectangular_cover(geom);objects=[]
    for idx,rect in enumerate(rects,1):
        x0,z0,x1,z1=rect.bounds;alongX=x1-x0>=z1-z0;L=max(x1-x0,z1-z0);D=min(x1-x0,z1-z0);count=math.ceil(L/256)
        for j in range(count):
            lo=(x0 if alongX else z0)+j*L/count;hi=lo+L/count;piece=box(lo,z0,hi,z1)if alongX else box(x0,lo,x1,hi);near=[o for o in old if object_geometry(o).intersection(piece).area>1e-4];H=max(o['coreHeight']for o in near);rids=sorted(set(o['boundaryRunId']for o in near));pairs=sorted(set(v for o in near for v in o['regionPair']),key=REGIONS.index);r=max(pairs,key=REGIONS.index)if pairs else 'REGION_FOREST';obj=placed_object(prototypes['CliffRun'],f'EV2_Cliff_{idx:02d}_{j+1:02d}',r,'Boundary',(lo+hi)/2 if alongX else(x0+x1)/2,g['groundY'],(z0+z1)/2 if alongX else(lo+hi)/2,0 if alongX else 90,(L/count/96,H/72,D/40));obj.update({'boundaryKind':'Outer'if all(o['boundaryKind']=='Outer'for o in near)else'Shared','boundaryRunIds':rids,'regionPair':pairs,'coreHeight':H,'depth':D,'length':L/count,'clearanceEvidence':{'sourceFragmentsMergedByExactUnion':True,'physicalGroundUnionUnchanged':True,'minimumSourceHeightPreserved':True,'sourceObjectIds':[o['id']for o in near]}});objects.append(obj)
    if len(objects)>=len(old):return b
    newgeom=unary_union([object_geometry(o)for o in objects]);assert newgeom.symmetric_difference(geom).area<.001
    b={**b,'objects':objects+headers,'cliffModules':len(objects),'moduleCount':len(objects)+len(headers)+len(b['retainedOuter']),'repartitionEvidence':{'sourceFragmentCount':len(old),'mergedPhysicalChunkCount':len(objects),'groundSymmetricDifferenceArea':newgeom.symmetric_difference(geom).area,'method':'Largest exact disjoint cuboid rectangle coverage with ≤256 chunks; preserves prior height maxima, source seams, protected apertures and closed crossings.'}}
    b['conflicts']=[c for c in b['conflicts']if c['code']!='BoundaryModuleCapExceeded']
    if b['moduleCount']>64:b['conflicts'].append({'code':'BoundaryModuleTargetExceeded','actual':b['moduleCount'],'target':64,'classification':'Explicit safety-first alternative; target is not claimed passed'})
    return b
