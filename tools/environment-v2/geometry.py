"""Pure deterministic geometry for the current saved world; never applies map compaction."""
from __future__ import annotations
import json, math, hashlib
from collections import defaultdict
from shapely import affinity
from shapely.geometry import box, Polygon, LineString, MultiPolygon, GeometryCollection, Point
from shapely.ops import unary_union, linemerge
REGIONS=['REGION_CAMP','REGION_FOREST','REGION_BEACH','REGION_SWAMP','REGION_JUNGLE','REGION_ARCTIC','REGION_VOLCANO','REGION_GLITCH']
NAMES={'Camp':'REGION_CAMP','Forest':'REGION_FOREST','Beach':'REGION_BEACH','Swamp':'REGION_SWAMP','Jungle':'REGION_JUNGLE','Arctic':'REGION_ARCTIC','Volcano':'REGION_VOLCANO','Glitch Zone':'REGION_GLITCH','GlitchZone':'REGION_GLITCH','Glitch':'REGION_GLITCH'}
TOL=.01

def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)
def sha(value): return hashlib.sha256(canonical(value).encode()).hexdigest()
def unpack(value):
    if isinstance(value,dict) and 'type' in value:
        return None if value['type']=='nil' else value.get('value')
    return value

def frame(x,y,z,yaw=0):
    assert yaw%90==0
    c=round(math.cos(math.radians(yaw)));s=round(math.sin(math.radians(yaw)))
    return [x,y,z,c,0,s,0,1,0,-s,0,c]
def cfpoint(cf,p): return [cf[i]+sum(cf[3+i*3+j]*p[j] for j in range(3)) for i in range(3)]
def cfcompose(a,b):return cfpoint(a,b[:3])+[sum(a[3+i*3+k]*b[3+k*3+j]for k in range(3))for i in range(3)for j in range(3)]
def box_corners(cf,size):
    return [cfpoint(cf,[a*size[0]/2,b*size[1]/2,c*size[2]/2]) for a in [-1,1] for b in [-1,1] for c in [-1,1]]
def bounds3(cf,size):
    points=box_corners(cf,size)
    return {'minX':min(p[0]for p in points),'maxX':max(p[0]for p in points),'minY':min(p[1]for p in points),'maxY':max(p[1]for p in points),'minZ':min(p[2]for p in points),'maxZ':max(p[2]for p in points)}
def part_projection(cf,size):
    points=box_corners(cf,size)
    from shapely.geometry import MultiPoint
    return MultiPoint([(p[0],p[2])for p in points]).convex_hull

def polygons(g):
    if g.is_empty:return []
    if isinstance(g,Polygon):return [g]
    if isinstance(g,(MultiPolygon,GeometryCollection)):return [p for q in g.geoms for p in polygons(q)]
    raise TypeError(g.geom_type)
def encode_geometry(g):
    return [{'exterior':[[float(x),float(z)]for x,z in p.exterior.coords], 'holes':[[[float(x),float(z)]for x,z in r.coords]for r in p.interiors]} for p in sorted(polygons(g),key=lambda p:(p.bounds,p.area))]
def decode_geometry(rows):return unary_union([Polygon(r['exterior'],r.get('holes',[])) for r in rows])
def lines(g):
    if g.is_empty:return []
    if g.geom_type=='LineString':return [g]
    if hasattr(g,'geoms'):return [p for q in g.geoms for p in lines(q)]
    return []

def axis_runs(g):
    """Merge true collinear edge spans; explicit region unions, never region AABB walls."""
    grouped=defaultdict(list)
    for line in lines(g):
        coords=list(line.coords)
        for a,b in zip(coords,coords[1:]):
            if abs(a[0]-b[0])<=1e-6:axis='Z';fixed=(a[0]+b[0])/2;low,high=sorted([a[1],b[1]])
            elif abs(a[1]-b[1])<=1e-6:axis='X';fixed=(a[1]+b[1])/2;low,high=sorted([a[0],b[0]])
            else:raise ValueError('Floor union contains a nonaxis boundary')
            if high-low>1e-6:grouped[(axis,round(fixed,6))].append((low,high))
    out=[]
    for (axis,fixed),spans in sorted(grouped.items()):
        spans.sort();merged=[]
        for low,high in spans:
            if merged and low<=merged[-1][1]+1e-6:merged[-1][1]=max(merged[-1][1],high)
            else:merged.append([low,high])
        for low,high in merged:out.append({'axis':axis,'fixed':fixed,'first':low,'last':high})
    return sorted(out,key=lambda r:((r['first'],r['fixed'])if r['axis']=='X' else(r['fixed'],r['first']),r['axis'],r['last']))
def true_boundaries(regions):
    out=[]
    for i,a in enumerate(REGIONS):
        for b in REGIONS[i+1:]:
            for r in axis_runs(regions[a].boundary.intersection(regions[b].boundary)):
                out.append({**r,'regionPair':[a,b],'kind':'Shared'})
    world=unary_union(list(regions.values()))
    for r in axis_runs(world.boundary):out.append({**r,'regionPair':[],'kind':'Outer'})
    out.sort(key=lambda r:(r['kind'],r['axis'],r['fixed'],r['first'],r['last'],r['regionPair']))
    for i,r in enumerate(out,1):r['id']=f'EV2_Run_{i:02d}'
    return out

def run_strip(r,depth,first=None,last=None):
    lo=r['first']if first is None else first;hi=r['last']if last is None else last
    if r['axis']=='X':return box(lo,r['fixed']-depth/2,hi,r['fixed']+depth/2)
    return box(r['fixed']-depth/2,lo,r['fixed']+depth/2,hi)
def prism_intervals(r,depth,geometry):
    """Project a protected polygon only after clipping through the complete candidate thickness."""
    hit=run_strip(r,depth).intersection(geometry)
    intervals=[]
    for p in polygons(hit):
        if p.area<=1e-8:continue
        b=p.bounds;intervals.append((b[0],b[2])if r['axis']=='X' else(b[1],b[3]))
    return merge_intervals(intervals)
def merge_intervals(rows):
    out=[]
    for a,b in sorted(rows):
        if b-a<=1e-7:continue
        if out and a<=out[-1][1]+1e-6:out[-1][1]=max(out[-1][1],b)
        else:out.append([a,b])
    return out

def subtract_intervals(first,last,cuts):
    rows=[];cursor=first
    for a,b in merge_intervals(cuts):
        a=max(first,a);b=min(last,b)
        if b<=first or a>=last:continue
        if a>cursor+1e-6:rows.append([cursor,a])
        cursor=max(cursor,b)
    if cursor<last-1e-6:rows.append([cursor,last])
    return rows

def local_shape(proto,axis_scale=(1,1,1)):
    sx,sy,sz=axis_scale
    return unary_union([box((c['centre'][0]-c['size'][0]/2)*sx,(c['centre'][2]-c['size'][2]/2)*sz,(c['centre'][0]+c['size'][0]/2)*sx,(c['centre'][2]+c['size'][2]/2)*sz)for c in proto['components']])
def placed_shape(local,x,z,yaw):return affinity.translate(affinity.rotate(local,-yaw,origin=(0,0)),xoff=x,yoff=z)
def placed_object(proto,id,region,role,x,y,z,yaw=0,axis_scale=(1,1,1),palette=None):
    root=frame(x,y,z,yaw);solids=[];colliders=[]
    for c in proto['components']:
        centre=[a*s for a,s in zip(c['centre'],axis_scale)];size=[a*s for a,s in zip(c['size'],axis_scale)];cf=cfcompose(root,frame(*centre))
        solids.append({'id':c['id'],'cframe':cf,'size':size,'tintGroup':c['group']})
    for c in proto['colliders']:
        centre=[a*s for a,s in zip(c['centre'],axis_scale)];size=[a*s for a,s in zip(c['size'],axis_scale)];cf=cfcompose(root,frame(*centre))
        colliders.append({'id':id+'_'+c['id'],'cframe':cf,'size':size,**bounds3(cf,size),'sourceComponents':c['components']})
    pts=[p for c in solids for p in box_corners(c['cframe'],c['size'])]
    bounds={'minX':min(p[0]for p in pts),'maxX':max(p[0]for p in pts),'minY':min(p[1]for p in pts),'maxY':max(p[1]for p in pts),'minZ':min(p[2]for p in pts),'maxZ':max(p[2]for p in pts)}
    return {'id':id,'prototypeId':proto['id'],'regionId':region,'role':role,'rootCFrame':root,'yaw':yaw,'axisScale':list(axis_scale),'bounds':bounds,'componentSolids':solids,'colliders':colliders,'meshGroups':[g['id']for g in proto['groups']],'palette':palette,'clearanceEvidence':{},'sourcePrototypeHash':sha(proto)}

def object_geometry(row):return unary_union([part_projection(c['cframe'],c['size'])for c in row['componentSolids']])
def collision_geometry(row,max_height=None):
    return unary_union([part_projection(c['cframe'],c['size'])for c in row['colliders']if max_height is None or c['minY']<max_height])
def grid_candidates(region,preference,origin=(-19,-46),step=4,yaws=(0,90,180,270)):
    minx,minz,maxx,maxz=region.bounds
    points=[]
    for ix in range(math.ceil((minx-origin[0])/step),math.floor((maxx-origin[0])/step)+1):
        x=origin[0]+ix*step
        for iz in range(math.ceil((minz-origin[1])/step),math.floor((maxz-origin[1])/step)+1):
            z=origin[1]+iz*step
            if region.covers(Point(x,z)):
                d=math.hypot(x-preference[0],z-preference[1]);tier=0 if d<=64 else 1 if d<=128 else 2
                points.extend((tier,d,x,z,yaw)for yaw in yaws)
    return sorted(points)


def open_grid_metrics(region,fixed,solid,origin=(-19,-46),step=4):
    """All usable area stays in denominator, including fractional edge/reservation cells.
    Any positive obstacle area conservatively blocks that cell's usable weight.
    """
    usable=region.difference(fixed);denominator=blocked=0.;full=partial=n=bn=0
    a,b,c,d=region.bounds
    from shapely.prepared import prep
    up=prep(usable);sp=prep(solid)
    for ix in range(math.floor((a-origin[0])/step),math.ceil((c-origin[0])/step)):
        for iz in range(math.floor((b-origin[1])/step),math.ceil((d-origin[1])/step)):
            cell=box(origin[0]+ix*step,origin[1]+iz*step,origin[0]+(ix+1)*step,origin[1]+(iz+1)*step)
            if not up.intersects(cell):continue
            use=cell if up.covers(cell)else cell.intersection(usable);weight=use.area
            if weight<=1e-8:continue
            n+=1;denominator+=weight
            if abs(weight-step*step)<1e-8:full+=1
            else:partial+=1
            if sp.intersects(use)and use.intersection(solid).area>1e-8:blocked+=weight;bn+=1
    assert abs(denominator-usable.area)<1e-4
    return{'evaluationCellSize':step,'usableWeightedCellsArea':denominator,'usableCells':n,'fullUsableCells':full,'partialUsableCells':partial,'blockedCells':bn,'blockedWeightedCellsArea':blocked,'openWeightedCellsArea':denominator-blocked,'openFraction':(denominator-blocked)/denominator if denominator else 0,'denominatorIncludesPartialCells':True}
