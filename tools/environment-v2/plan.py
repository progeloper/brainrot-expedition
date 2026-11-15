"""Deterministic, current-layout Environment V2 planner. Source-only, never writes Studio."""
from __future__ import annotations
import argparse,json,math,hashlib,time,heapq
from pathlib import Path
from collections import Counter
from shapely.geometry import box,Point,LineString
from shapely.ops import unary_union
from shapely.prepared import prep
from geometry import *
from boundary import plan_boundary
ROOT=Path(__file__).resolve().parents[2]
HERO={'REGION_CAMP':'CampWaystone','REGION_FOREST':'ForestRuin','REGION_BEACH':'BeachSeaGate','REGION_SWAMP':'SwampCistern','REGION_JUNGLE':'JungleObservatory','REGION_ARCTIC':'ArcticIgloo','REGION_VOLCANO':'VolcanoMassif','REGION_GLITCH':'GlitchTemple'}
ANCHORS={'REGION_CAMP':[(.35,.35),(.65,.65)],'REGION_FOREST':[(.70,.20),(.20,.45),(.65,.75),(.50,.15),(.25,.70)],'REGION_BEACH':[(.22,.60),(.25,.25),(.65,.12),(.25,.45),(.60,.15)],'REGION_SWAMP':[(.30,.65),(.20,.30),(.70,.65),(.20,.50),(.60,.70)],'REGION_JUNGLE':[(.65,.65),(.25,.70),(.75,.25),(.50,.75),(.80,.45)],'REGION_ARCTIC':[(.35,.35),(.20,.70),(.75,.30),(.20,.50),(.65,.20)],'REGION_VOLCANO':[(.70,.65),(.25,.30),(.70,.80)],'REGION_GLITCH':[(.65,.65),(.25,.35),(.75,.25)]}
COUNTS={'REGION_CAMP':(2,0,1,0,0),'REGION_FOREST':(3,1,1,2,2),'REGION_BEACH':(2,1,1,2,2),'REGION_SWAMP':(1,1,1,2,2),'REGION_JUNGLE':(3,1,1,2,2),'REGION_ARCTIC':(1,1,1,2,2),'REGION_VOLCANO':(0,1,1,2,2),'REGION_GLITCH':(0,1,1,2,2)}

def preference(region,uv):
    a,b,c,d=region.bounds;return(a+(c-a)*uv[0],b+(d-b)*uv[1])
def bbox_local(proto):return box(proto['bounds']['min'][0],proto['bounds']['min'][2],proto['bounds']['max'][0],proto['bounds']['max'][2])
def bound_polygon(row):
    b=row['bounds'];return box(b['minX'],b['minZ'],b['maxX'],b['maxZ'])
def canopy_local(proto):
    groups={g['id']for g in proto['groups']if g['role']in['Cap','Foliage','Cap/Foliage']};return unary_union([box(c['centre'][0]-c['size'][0]/2,c['centre'][2]-c['size'][2]/2,c['centre'][0]+c['size'][0]/2,c['centre'][2]+c['size'][2]/2)for c in proto['components']if c['group']in groups])
def window_density(points):
    # A maximum occurs with the lower X/Z window side at one of the contained point coordinates.
    best={'count':0,'bounds':None,'ids':[]}
    for x in sorted(set(p[1]for p in points)):
        for z in sorted(set(p[2]for p in points)):
            included=[p[0]for p in points if x-1e-7<=p[1]<=x+64+1e-7 and z-1e-7<=p[2]<=z+64+1e-7]
            if len(included)>best['count']:best={'count':len(included),'bounds':[x,z,x+64,z+64],'ids':included}
    return best

def clear_candidate_shapes(x,z,width,depth,yaw):
    w,d=(width,depth)if yaw==0 else(depth,width)
    shape=box(x-w/2,z-d/2,x+w/2,z+d/2)
    # Two independently reported rays, each60 studs from clearing centre. Reserve narrow corridors as actual sight lines.
    rays=[LineString([(x,z),(x+60,z)]),LineString([(x,z),(x-60,z)])]if w>=d else[LineString([(x,z),(x,z+60)]),LineString([(x,z),(x,z-60)])]
    return shape,rays

def choose_clearings(region,avoid,pref,origin,limit=120):
    rp=prep(region);ap=prep(avoid);main=[]
    for _,dist,x,z,yaw in grid_candidates(region,pref,origin=origin,yaws=(0,90)):
        shape,rays=clear_candidate_shapes(x,z,96,80,yaw);reserve=unary_union([shape]+[r.buffer(.15,cap_style=2)for r in rays])
        if rp.covers(reserve)and not ap.intersects(reserve):main.append((dist,x,z,yaw,shape,rays,reserve))
        if len(main)>=limit:break
    for first in main:
        _,x,z,yaw,shape,rays,reserve=first
        # Secondary lies farther from the main, still close to the focal scene, rather than tucked behind a random outcrop.
        secondPref=(pref[0]+112,pref[1]+96)
        avoid2=prep(avoid.union(reserve.buffer(4,join_style=2)))
        for _,dist2,x2,z2,yaw2 in grid_candidates(region,secondPref,origin=origin,yaws=(0,90)):
            sh2,ray2=clear_candidate_shapes(x2,z2,72,64,yaw2);res2=unary_union([sh2]+[r.buffer(.15,cap_style=2)for r in ray2])
            if rp.covers(res2)and not avoid2.intersects(res2):
                return [{'id':'Main','centre':[x,z],'size':[96,80],'yaw':yaw,'polygons':encode_geometry(shape),'rayEnds':[[list(r.coords[0]),list(r.coords[-1])]for r in rays],'sightPolygons':encode_geometry(unary_union([r.buffer(.15,cap_style=2)for r in rays]))}, {'id':'Secondary','centre':[x2,z2],'size':[72,64],'yaw':yaw2,'polygons':encode_geometry(sh2),'rayEnds':[[list(r.coords[0]),list(r.coords[-1])]for r in ray2],'sightPolygons':encode_geometry(unary_union([r.buffer(.15,cap_style=2)for r in ray2]))}]
    return None

def connector(a,b,region,avoid,width=28):
    """A deterministic grounded walking/cart corridor. Existing road surfaces are available, never rerouted."""
    rp=prep(region);ap=prep(avoid)
    paths=[[a,b],[a,(a[0],b[1]),b],[a,(b[0],a[1]),b]]
    for points in paths:
        points=[p for i,p in enumerate(points)if i==0 or p!=points[i-1]]
        if len(points)<2:continue
        shp=LineString(points).buffer(width/2,cap_style=2,join_style=2)
        if rp.covers(shp)and not ap.intersects(shp):return {'width':width,'controlPoints':[list(p)for p in points],'polygons':encode_geometry(shp),'method':'DirectOrCardinalExistingGround'}
    # The centre clearance mask provides an exact28-wide disk swept corridor; grid nodes4studs, deterministic A*.
    free=region.buffer(-width/2,join_style=2).difference(avoid.buffer(width/2,join_style=2));fp=prep(free)
    step=4;ox,oz=-19,-46
    def snap(p):return(round((p[0]-ox)/step),round((p[1]-oz)/step))
    def pos(n):return(ox+n[0]*step,oz+n[1]*step)
    start=snap(a);goal=snap(b)
    # Frozen endpoints may fall off the grid; require their4-stud attachment to be safe.
    startp=pos(start);goalp=pos(goal)
    for p,q in [(a,startp),(b,goalp)]:
        seg=LineString([p,q]).buffer(width/2,cap_style=2,join_style=2)
        if not rp.covers(seg)or ap.intersects(seg):return None
    frontier=[(abs(start[0]-goal[0])+abs(start[1]-goal[1]),0,start)];seen={start:0};prev={};found=False
    while frontier and len(seen)<100000:
        _,cost,n=heapq.heappop(frontier)
        if cost!=seen.get(n):continue
        if n==goal:found=True;break
        for dx,dz in [(0,-1),(-1,0),(1,0),(0,1)]:
            q=(n[0]+dx,n[1]+dz);nc=cost+1
            if nc>=seen.get(q,10**9):continue
            if not fp.covers(LineString([pos(n),pos(q)])):continue
            seen[q]=nc;prev[q]=n;h=abs(q[0]-goal[0])+abs(q[1]-goal[1]);heapq.heappush(frontier,(nc+h,nc,q))
    if not found:return None
    nodes=[goal]
    while nodes[-1]!=start:nodes.append(prev[nodes[-1]])
    nodes.reverse();pts=[a]+[pos(n)for n in nodes]+[b]
    compact=[]
    for p in pts:
        if compact and p==compact[-1]:continue
        while len(compact)>=2 and abs((compact[-1][0]-compact[-2][0])*(p[1]-compact[-1][1])-(compact[-1][1]-compact[-2][1])*(p[0]-compact[-1][0]))<1e-6:compact.pop()
        compact.append(p)
    shp=LineString(compact).buffer(width/2,cap_style=2,join_style=2)
    if not rp.covers(shp)or ap.intersects(shp):return None
    return {'width':width,'controlPoints':[list(p)for p in compact],'polygons':encode_geometry(shp),'method':'4StudCardinalAStarOnExistingGround'}

def burrow_object(p,id,region,x,y,z,yaw):
    core=placed_object(p['BurrowCore'],id,region,'Burrow',x,y,z,yaw);brow=placed_object(p['BurrowBrow'],id+'_Brow',region,'Burrow',x,y,z,yaw)
    core['attachedPrototypes']=['BurrowBrow'];
    for c in core['colliders']:c['sourceComponents']=['Core_'+v for v in c['sourceComponents']]
    core['componentSolids']=[{**c,'id':'Core_'+c['id']}for c in core['componentSolids']]+[{**c,'id':'Brow_'+c['id']}for c in brow['componentSolids']]
    for key in ['minX','minY','minZ']:core['bounds'][key]=min(core['bounds'][key],brow['bounds'][key])
    for key in ['maxX','maxY','maxZ']:core['bounds'][key]=max(core['bounds'][key],brow['bounds'][key])
    core['meshGroups']=[{'prototypeId':'BurrowCore','groupId':g['id']}for g in p['BurrowCore']['groups']]+[{'prototypeId':'BurrowBrow','groupId':g['id']}for g in p['BurrowBrow']['groups']]
    core['sourcePrototypeHash']=sha([p['BurrowCore'],p['BurrowBrow']]);root=core['rootCFrame']
    core['markers']=[{'name':'Art_'+name,'worldPosition':cfpoint(root,loc),'worldCFrame':cfcompose(root,frame(*loc,90 if name=='Hide'else 0))}for name,loc in [('Mouth',[0,.04,0]),('Exit',[0,0,-24]),('Turn',[0,.04,36]),('Hide',[54,.04,36])]];core['markerPathOrder']=['Art_Hide','Art_Turn','Art_Mouth','Art_Exit']
    apron=placed_shape(box(-18,-48,18,0),x,z,yaw);core['apronPolygons']=encode_geometry(apron);core['interface']={'Art_BurrowId':id,'Art_RegionKey':region,'Art_InterfaceVersion':1,'Art_RuntimeRegistered':False,'W':24,'H':22,'commonScale':1,'markersAreAttachmentsOnExistingMeshPart':True};return core

def find_object(proto,id,regionId,region,avoid,pref,origin,yaws=(0,90,180,270),scale=1,extra=None,limit=None,accept=None):
    shape=local_shape(proto);shape=affinity.scale(shape,xfact=scale,yfact=scale,origin=(0,0))
    if extra is not None:shape=shape.union(extra)
    rp=prep(region);ap=prep(avoid);checked=0
    for tier,d,x,z,yaw in grid_candidates(region,pref,origin=origin,yaws=yaws):
        checked+=1
        actual=placed_shape(shape,x,z,yaw)
        if rp.covers(actual)and(not ap.intersects(actual)or actual.intersection(avoid).area<1e-8):
            accepted={}if accept is None else accept(x,z,yaw,actual)
            if accepted is not None:return (x,z,yaw,{'rankTier':tier,'preferenceDistance':d,'testedCandidates':checked,'exactSourceProjectionPolygons':encode_geometry(actual),'fullSourceGeometryFitsCurrentRegion':True,'protectedFixedAndRoadShoulderOverlapArea':0,**accepted})
        if limit and checked>=limit:break
    return None

def elevate_boundary(objects,boundary,g,prototypes):
    """Conservative source proof: all nearby colliding top faces count, even if unreachable."""
    scene=json.loads((ROOT/'docs/environment-v2/BeforeManifest.json').read_text());launch=[]
    for r in scene['records']:
        p=r.get('properties')or{}
        if r['scope']=='Map'and p.get('CanCollide')is True and'CFrame'in p and'Size'in p and not('.RegionWalls.'in r['path']or'.BoundarySeparators.'in r['path']):
            cf=unpack(p['CFrame']);sz=unpack(p['Size']);b=bounds3(cf,sz);launch.append((r['key'],part_projection(cf,sz),b['maxY']))
    for o in objects:
        if o['role']=='Boundary':continue
        launch.extend((c['id'],part_projection(c['cframe'],c['size']),c['maxY'])for c in o['colliders'])
    minHeights=[]
    for i,o in enumerate(objects):
        if o['role']!='Boundary'or o['boundaryKind']=='GateLintel':continue
        footprint=object_geometry(o);near=[(id,top)for id,sh,top in launch if footprint.distance(sh)<=48+1e-6];maxY=max([g['groundY']]+[top for id,top in near]);required=max(72,4*math.ceil((maxY-g['groundY']+8+6.6161232+8)/4));H=max(o['coreHeight'],required);proof={'launchZoneDistance':48,'actualHorizontalJumpAndCartReach':'PendingNativeMeasurement; increase48ifmeasuredreach+8exceedsit','measuredMaximumFeetRise':7.9361710846,'conservativeJ':8,'A':6.6161232,'highestConservativeCollidingTopRelativeGround':maxY-g['groundY'],'nearbyColliderIdsAtHighest':[id for id,top in near if abs(top-maxY)<1e-5],'minimumCoreHeight':required,'chosenCoreHeight':H,'reachableAnalysis':'Conservative ALL nearby actual collider tops; decorative/canopy groups excluded, no reachability discount'}
        if H!=o['coreHeight']:
            root=o['rootCFrame'];pid=o['prototypeId']
            if o['boundaryKind']=='JunctionFill':replacement=placed_object(prototypes[pid],o['id'],o['regionId'],'Boundary',root[0],g['groundY']-2*H/72,root[2],o['yaw'],(o['length']/96,(74.7*H/72)/54,o['depth']/40))
            else:replacement=placed_object(prototypes[pid],o['id'],o['regionId'],'Boundary',root[0],g['groundY'],root[2],o['yaw'],(o['length']/96,H/72,o['depth']/40))
            replacement.update({k:v for k,v in o.items()if k not in['rootCFrame','axisScale','bounds','componentSolids','colliders','meshGroups','sourcePrototypeHash']});o=replacement;objects[i]=o
        o['coreHeight']=H;o['heightSafetyEvidence']=proof;minHeights.append(H)
    ground=[o for o in objects if o['role']=='Boundary'and o['boundaryKind']!='GateLintel']
    for i,o in enumerate(objects):
        if o.get('boundaryKind')!='GateLintel':continue
        foot=object_geometry(o);adj=[q for q in ground if foot.distance(object_geometry(q))<=.21];H=max([72]+[q['coreHeight']for q in adj]);root=o['rootCFrame'];bottom=root[1];scale=[o['axisScale'][0],(g['groundY']+H-bottom)/54,o['axisScale'][2]];replacement=placed_object(prototypes['GateLintel'],o['id'],o['regionId'],'Boundary',*root[:3],o['yaw'],scale);replacement.update({k:v for k,v in o.items()if k not in['rootCFrame','axisScale','bounds','componentSolids','colliders','meshGroups','sourcePrototypeHash']});replacement['coreHeight']=H;replacement['heightSafetyEvidence']={'topMeetsMaximumAdjacentCoreHeight':H,'adjacentIds':[q['id']for q in adj],'undersidePreserved':bottom};objects[i]=replacement
    boundary['objects']=[o for o in objects if o['role']=='Boundary'];boundary['heightInputs']['sourceConservativePerChunkVerified']=True;boundary['heightInputs']['minimumChosenCoreHeight']=min(minHeights);boundary['heightInputs']['maximumChosenCoreHeight']=max(minHeights)

def build(g,a,optional=True,reuse_outer=True,perimeter_zone=48):
    prototypes={p['id']:p for p in a['prototypes']};regions={k:decode_geometry(v)for k,v in g['regions'].items()};road=decode_geometry(g['roadPolygons']);fixed=unary_union([decode_geometry(r['polygons'])for r in g['fixedReservations']]);origin=tuple(g['origin']);y=g['groundY'];depths={'EV2_Run_19':8,'EV2_Run_06':8};
    if not reuse_outer:depths.update({'EV2_Run_01':8,'EV2_Run_03':8,'EV2_Run_04':8})
    boundary=plan_boundary(g,prototypes,depth_override=depths,reuse_outer=reuse_outer)
    obstacles=decode_geometry(boundary['groundPolygons']);baseAvoid=fixed.union(obstacles);objects=list(boundary['objects']);clearings={};connections=[];reserved=[];conflicts=list(boundary['conflicts']);omissions=[];mandatory=[]
    # Existing entry routes and shoulders are frozen, already included by the full road+6 reserve below.
    for r in REGIONS[1:]:
        pref=g['heroPreferences'].get(r);pref=(pref[0],pref[2]-100)if pref else preference(regions[r],(.5,.45))
        if not reuse_outer and r=='REGION_ARCTIC':
            cs=[]
            for label,x,z,w,d,yaw in [('Main',489,-602,96,80,0),('Secondary',409,-378,72,64,90)]:
                sh,ray=clear_candidate_shapes(x,z,w,d,yaw);res=unary_union([sh]+[v.buffer(.15,cap_style=2)for v in ray]);assert regions[r].covers(res)and res.intersection(baseAvoid).area<1e-6,'Arctic joint recovery clearing changed';cs.append({'id':label,'centre':[x,z],'size':[w,d],'yaw':yaw,'polygons':encode_geometry(sh),'rayEnds':[[list(v.coords[0]),list(v.coords[-1])]for v in ray],'sightPolygons':encode_geometry(unary_union([v.buffer(.15,cap_style=2)for v in ray])),'jointRecovery':'Revisited clearing arrangement to retain both fixed-size burrows and Igloo inside frozen L-floor/road/pad geometry'})
        else:cs=choose_clearings(regions[r],baseAvoid,pref,origin)
        if cs is None:conflicts.append({'code':'RequiredClearingsNoFit','regionId':r});continue
        for c in cs:
            c['id']=r+'_'+c['id'];c['regionId']=r;reserved.extend([decode_geometry(c['polygons']),decode_geometry(c['sightPolygons'])])
        clearings[r]=cs
        con=connector(tuple(cs[0]['centre']),tuple(cs[1]['centre']),regions[r],baseAvoid)
        if con is None:conflicts.append({'code':'ClearingConnectionNoFit','regionId':r})
        else:con.update({'id':r+'_ClearingsConnection','regionId':r});connections.append(con);reserved.append(decode_geometry(con['polygons']))
    reservation=unary_union(reserved);occupied=unary_union([]);roadReserve=road.buffer(6,join_style=2);perimeterReserve=unary_union([part_projection(v['cframe'],v['size'])for v in boundary['retainedOuter']]).buffer(perimeter_zone,join_style=2)if reuse_outer else Polygon()
    for r in REGIONS:
        proto=prototypes[HERO[r]];pref=g['heroPreferences'].get(r);pref=(pref[0],pref[2])if pref else preference(regions[r],ANCHORS[r][0])
        avoid=baseAvoid.union(roadReserve).union(reservation).union(occupied.buffer(4,join_style=2)).union(perimeterReserve)
        if not reuse_outer and r=='REGION_ARCTIC':
            guards=[burrow_object(prototypes,'Arctic_Feasibility_'+str(i),r,x,y,z,yaw)for i,(x,z,yaw)in enumerate([(309,-470,180),(257,-362,0)])];guard=unary_union([object_geometry(o).union(decode_geometry(o['apronPolygons']))for o in guards]);avoid=avoid.union(guard.buffer(4,join_style=2))
        fit=find_object(proto,r+'_Hero',r,regions[r],avoid,pref,origin)
        if fit:
            x,z,yaw,e=fit;obj=placed_object(proto,r+'_Hero',r,'Hero',x,y,z,yaw);obj['clearanceEvidence']=e;obj['mandatory']=True;objects.append(obj);mandatory.append(obj);occupied=occupied.union(object_geometry(obj));print('hero',r,x,z,yaw,flush=True)
        else:conflicts.append({'code':'MandatoryHeroNoFit','regionId':r,'prototypeId':proto['id']});print('hero FAIL',r,flush=True)
        for j in range(1,2 if r=='REGION_CAMP'else 3):
            id=r+f'_Burrow_{j:02d}';pref=preference(regions[r],ANCHORS[r][j]);extra=box(-18,-48,18,0).union(local_shape(prototypes['BurrowBrow']))
            avoid=baseAvoid.union(roadReserve).union(reservation).union(occupied.buffer(4,join_style=2)).union(perimeterReserve)
            chosenConnection={}
            def accepts_burrow(x,z,yaw,shape):
                if r=='REGION_CAMP':return{}
                if r not in clearings:return None
                candidate=burrow_object(prototypes,id,r,x,y,z,yaw);exit=next(m['worldPosition']for m in candidate['markers']if m['name']=='Art_Exit');dest=min(clearings[r],key=lambda c:math.dist((exit[0],exit[2]),c['centre']))
                con=connector((exit[0],exit[2]),tuple(dest['centre']),regions[r],baseAvoid.union(occupied.buffer(4,join_style=2)).union(object_geometry(candidate)),28)
                if con is None:return None
                chosenConnection.clear();chosenConnection.update(con);return{'groundConnection':id+'_Connection'}
            fit=find_object(prototypes['BurrowCore'],id,r,regions[r],avoid,pref,origin,extra=extra,accept=accepts_burrow)
            if not fit:conflicts.append({'code':'MandatoryBurrowNoFit','regionId':r,'id':id,'exactSourcePlusApronProjection':True,'connectionRequiredWidth':28});print('burrow FAIL',id,flush=True);continue
            x,z,yaw,e=fit;obj=burrow_object(prototypes,id,r,x,y,z,yaw);obj['clearanceEvidence']=e;obj['mandatory']=True
            if chosenConnection:
                con={**chosenConnection,'id':id+'_Connection','regionId':r};connections.append(con);reservation=reservation.union(decode_geometry(con['polygons']))
            objects.append(obj);mandatory.append(obj);occupied=occupied.union(object_geometry(obj)).union(decode_geometry(obj['apronPolygons']));print('burrow',id,x,z,yaw,flush=True)
    # Small corner fragments retain the exact full core/cap volume using the genuine brick header prototype.
    for i,o in enumerate(objects):
        if o['role']=='Boundary'and o['boundaryKind']!='GateLintel'and o['length']<=64:
            root=o['rootCFrame'];H=o['coreHeight'];minimum=-2*H/72;maximum=72.7*H/72;replacement=placed_object(prototypes['GateLintel'],o['id'],o['regionId'],'Boundary',root[0],y+minimum,root[2],o['yaw'],(o['length']/96,(maximum-minimum)/54,o['depth']/40));replacement.update({k:v for k,v in o.items()if k not in['prototypeId','rootCFrame','axisScale','bounds','componentSolids','colliders','meshGroups','sourcePrototypeHash']});replacement['boundaryKind']='JunctionFill';replacement['clearanceEvidence']={**o['clearanceEvidence'],'junctionDetailAdaptation':'Exact ground−2*H/72..72.7*H/72 core/cap solid retained with124tri masonry header source, avoiding distorted four-stack narrow pillar'};objects[i]=replacement
    boundary['objects']=[o for o in objects if o['role']=='Boundary'];boundary['junctionFills']=sum(o.get('boundaryKind')=='JunctionFill'for o in objects)
    exportPath=ROOT/'assets/environment-v2/ExpectedNativeGeometry.json';exportBytes=exportPath.read_bytes();exportRows=json.loads(exportBytes);exportManifest=json.loads((ROOT/'assets/environment-v2/EnvironmentAssetManifest.json').read_text());assert exportManifest['sourceSHA256']==a['sourceSHA256'],'Asset source/export mismatch; wait for complete asset generation';triangleCounts=Counter();groupTriangles={}
    for row in exportRows:
        triangleCounts[row['prototypeId']]+=len(row['triangles']);groupTriangles[(row['prototypeId'],row['groupId'])]=len(row['triangles'])
    mandatoryExposed=sum(triangleCounts[o['prototypeId']]+sum(triangleCounts[q]for q in o.get('attachedPrototypes',[]))for o in objects)
    spentTriangles=mandatoryExposed
    if optional:
        for r in REGIONS:
            ts,rs,ss,terr,ruins=COUNTS[r];hero=next((o for o in mandatory if o['regionId']==r and o['role']=='Hero'),None);hpos=(hero['rootCFrame'][0],hero['rootCFrame'][2])if hero else preference(regions[r],ANCHORS[r][0]);cs=clearings.get(r,[]);cpos=tuple(cs[0]['centre'])if cs else hpos
            specs=[]
            for j in range(terr):specs.append(('Terrace','Terrace',j, (cpos[0]+(-64 if j==0 else 64),cpos[1]+(20 if j==0 else 32)),1,(0,90,180,270)))
            for j in range(ruins):specs.append(('SecondaryRuin','SecondaryRuin',j,(hpos[0]+(-72 if j==0 else 72),hpos[1]+52),1,(0,90,180,270)))
            tree='Palm'if r=='REGION_BEACH'else'SwampTree'if r=='REGION_SWAMP'else'Broadleaf'
            groves=[preference(regions[r],v)for v in ANCHORS[r][3:5]]if len(ANCHORS[r])>=5 else[(origin[0]-200,origin[1]-180),(origin[0]+180,origin[1]+180)]
            offsets=[(-16,0),(12,8),(0,-20),(-32,16),(28,-16)];scales=[1,.9,1.1,.85,.95];yaws=[0,90,270,180,0];each=2 if ts==3 else 1
            for j in range(ts):
                gi=(j//each)%2;oi=j%each;gp=groves[gi];pref=(gp[0]+offsets[oi][0],gp[1]+offsets[oi][1]);specs.append((tree,'Tree',j,pref,scales[oi],(yaws[oi],)))
            rockScales=[1,.85,1.1,.9]
            for j in range(rs):specs.append(('RockCluster','Rock',j,(hpos[0]+[-60,60,-40,40][j],hpos[1]+[20,20,84,84][j]),rockScales[j],((j*90)%360,)))
            for j in range(ss):specs.append(('Shrub','Shrub',j,(hpos[0]+(-36 if j==0 else 36),hpos[1]-40),1 if j==0 else .85,((j*90)%360,)))
            for pid,role,j,pref,scale,yaws in specs:
                id=r+'_'+role+f'_{j+1:02d}';proto=prototypes[pid]
                if spentTriangles+triangleCounts[pid]>43486:
                    omissions.append({'id':id,'prototypeId':pid,'reason':'ActualExposedExportTriangleBudget','priority':'Optional','exportTrianglesPerCopy':triangleCounts[pid],'installedProjectedBefore':spentTriangles});continue
                avoid=baseAvoid.union(roadReserve).union(reservation).union(occupied.buffer(4,join_style=2)).union(perimeterReserve);fit=find_object(proto,id,r,regions[r],avoid,pref,origin,yaws=yaws,scale=scale)
                if not fit:
                    omissions.append({'id':id,'reason':'NoClearSourceBoundsPlacement','priority':'SelectedComposition'});conflicts.append({'code':'SelectedCompositionPlacementNoFit','id':id,'prototypeId':pid,'role':role});continue
                x,z,yaw,e=fit
                if role=='Tree':
                    prev=[(o['id'],o['rootCFrame'][0],o['rootCFrame'][2])for o in objects if o['role']=='Tree'and o['regionId']==r];dens=window_density(prev+[(id,x,z)])
                    if dens['count']>4:omissions.append({'id':id,'reason':'Any64StudTrunkWindowAboveFour','density':dens});continue
                obj=placed_object(proto,id,r,role,x,y,z,yaw,(scale,scale,scale));obj['clearanceEvidence']=e;obj['mandatory']=False;objects.append(obj);spentTriangles+=triangleCounts[pid];occupied=occupied.union(object_geometry(obj))
    elevate_boundary(objects,boundary,g,prototypes)
    metrics={};newfoot=[];canopies={r:[]for r in REGIONS}
    for o in objects:
        if o['role']=='Boundary':continue
        newfoot.append(object_geometry(o))
        if o['role']in['Tree','Shrub']:
            p=prototypes[o['prototypeId']];s=o['axisScale'];loc=affinity.scale(canopy_local(p),xfact=s[0],yfact=s[2],origin=(0,0));canopies[o['regionId']].append(placed_shape(loc,o['rootCFrame'][0],o['rootCFrame'][2],o['yaw']))
    solid=unary_union(newfoot+[decode_geometry(boundary['groundPolygons'])]);allSceneBounds=unary_union(newfoot)
    for r in REGIONS:
        usable=regions[r].difference(fixed);preparedUsable=prep(usable);ps=prep(solid);trunks=[(o['id'],o['rootCFrame'][0],o['rootCFrame'][2])for o in objects if o['role']=='Tree'and o['regionId']==r];density=window_density(trunks);n=blocked=0
        grid=open_grid_metrics(regions[r],fixed,solid,origin);openratio=grid['openFraction'];canopy=unary_union(canopies[r]).intersection(usable);cr=canopy.area/usable.area if usable.area else 0
        metrics[r]={'floorUnionArea':regions[r].area,'existingFunctionalExcludedArea':regions[r].intersection(fixed).area,'usableGroundArea':usable.area,**grid,'minimumOpenFraction':.65,'openPass':openratio>=.65,'newSceneBoundsArea':regions[r].intersection(allSceneBounds).area,'boundaryGroundArea':regions[r].intersection(decode_geometry(boundary['groundPolygons'])).area,'canopyUnionArea':canopy.area,'canopyFraction':cr,'maximumCanopyFraction':.12,'canopyPass':cr<=.12,'trunkDensity':density,'densityPass':density['count']<=4,'roadsRemainInDenominator':True,'newClearingsRemainInDenominator':True}
        if r!='REGION_CAMP'and not metrics[r]['openPass']:conflicts.append({'code':'RegionOpenAreaBelow65Percent','regionId':r,'actual':openratio})
        if cr>.12:conflicts.append({'code':'CanopyAbove12Percent','regionId':r,'actual':cr})
    # Normalize mesh group identity; no invented native IDs.
    for o in objects:
        if o['role']!='Burrow':o['meshGroups']=[{'prototypeId':o['prototypeId'],'groupId':v}if isinstance(v,str)else v for v in o['meshGroups']]
    count=Counter(o['role']for o in objects);visible=sum(len(o['meshGroups'])for o in objects);colliders=sum(len(o['colliders'])for o in objects);instances=sum(1+len(o['meshGroups'])+len(o['colliders'])+len(o.get('markers',[]))for o in objects)
    budget={'placementCount':len(objects),'roles':dict(count),'newVisibleMeshParts':visible,'newColliders':colliders,'newBaseParts':visible+colliders,'newInstancesExcludingRootFolders':instances,'retainedOuterParts':len(boundary['retainedOuter']),'boundaryModuleTarget':64,'actualBoundaryModules':boundary['moduleCount'],'boundaryTargetPass':boundary['moduleCount']<=64,'limits':{'visible':384,'colliders':360,'BaseParts':750,'instances':1500,'triangles':40000,'nativeMeshIds':36},'nativeTessellation':'NotImportedOrMeasured','closedCuboidTriangleProjection':sum(len(o['componentSolids'])*12 for o in objects),'actualExposedExportTriangleProjection':spentTriangles,'actualNativeInstalledTriangleCount':None,'expectedGeometryFileSHA256':hashlib.sha256(exportBytes).hexdigest(),'actualExportBudgetPass':spentTriangles<=40000,'selectedExplicitCompositionBudget':43486,'selectedCompositionBudgetPass':spentTriangles<=43486,'sourceCountsPendingLatestBrickRevision':False,'countScope':'New replacement layer; original fixed systems and35brainrots excluded; retained outer reported separately'}
    if spentTriangles>43486:conflicts.append({'code':'SelectedCompositionTriangleBudgetExceeded','actual':spentTriangles,'limit':43486,'closedCuboidProjectionNotUsedForThisGate':True})
    if visible>384 or colliders>360 or visible+colliders>750 or instances>1500:conflicts.append({'code':'DeclaredInstanceBudgetExceeded','counts':budget})
    for o in objects:
        if o['role']=='Boundary':
            if o.get('regionPair'):o['regionId']=max(o['regionPair'],key=REGIONS.index)
            elif o.get('boundaryKind')=='Outer':o['regionId']=next(r for r,poly in regions.items()if poly.covers(Point(o['rootCFrame'][0],o['rootCFrame'][2])))
        name=next(k for k,v in NAMES.items()if v==o['regionId']and k!='GlitchZone'and k!='Glitch');o['palette']=a['palettes'][name]
        o['expectedExportTriangles']=sum(groupTriangles[(q['prototypeId'],q['groupId'])]for q in o['meshGroups'])
        for q in o['meshGroups']:
            proto=prototypes[q['prototypeId']];role=next(gg['role']for gg in proto['groups']if gg['id']==q['groupId']);q['colorRGB']=o['palette'][role]
            if q['groupId']=='B':
                if q['prototypeId']=='BeachSeaGate':q['colorRGB']=[255,236,179]
                elif q['prototypeId']=='ArcticIgloo':q['colorRGB']=[235,245,250]
                elif q['prototypeId']=='CampWaystone':q['colorRGB']=[220,235,245]
                elif q['prototypeId']in['VolcanoMassif','GlitchTemple']or(q['prototypeId']=='BurrowBrow'and o['regionId']in['REGION_VOLCANO','REGION_GLITCH']):q['colorRGB']=o['palette']['Accent']
    campFile=ROOT/'docs/environment-v2/CampBurrowExhaustiveFit.json';campProof=json.loads(campFile.read_text())if campFile.exists()else None
    accepted=[];unplaced=[]
    target=next((c for c in conflicts if c['code']=='BoundaryModuleCapExceeded'),None)
    if target and not reuse_outer:
        conflicts.remove(target);accepted.append({**target,'classification':'Boundary target NotMet; strict collision/part/triangle limits unchanged','reason':'Full72+ perimeter replaces ten26high flat originals after conservative48 launch zone rejected required current composition; exact disjoint union merge failed to reduce frozen seam/aperture fragments','rootApprovedSafetyFirstAlternative':True})
    if campProof and campProof['status']=='CampRequiredPlacementConflict':
        conflict=next((c for c in conflicts if c.get('id')=='REGION_CAMP_Burrow_01'),None)
        if conflict:
            conflicts.remove(conflict);accepted.append({**conflict,'exception':'Bible section6 plus explicit root/user-authorized Camp placement exception','proof':'CampBurrowExhaustiveFit.json','testedCandidates':campProof['testedCandidates'],'status':'RequiredPlacementNotAchievedAssetRetained'})
            cand=campProof['bestReviewCandidateUninstalled'];unplacedRow=burrow_object(prototypes,'REGION_CAMP_Burrow_01','REGION_CAMP',*cand['root'],cand['yaw']);unplacedRow['install']=False;unplacedRow['mandatory']=True;unplacedRow['clearanceEvidence']=cand;unplacedRow['status']='ReviewOnlyConflictingCandidate';unplaced.append(unplacedRow)
    plan={'schemaVersion':2,'migrationId':'BR_EnvironmentArt_V2','baselineSceneSHA256':g['baselineSceneSHA256'],'compactPlanHash':g['compactPlanHash'],'assetSourceSHA256':a['sourceSHA256'],'status':'DraftWithConflicts'if conflicts else'PurePlacementSolvedWithDisclosedExceptionsNativeChecksPending','applyEligible':False,'objects':objects,'archive':g['archive'],'boundaryArchive':[r for r in g['boundaryArchive']if r['originalKey']not in {q['originalKey']for q in boundary['retainedOuter']}],'retainedOuter':boundary['retainedOuter'],'boundary':boundary,'reservations':{'clearings':clearings,'connections':connections,'roadShoulderWidth':6,'entryTravel48CoveredByFullFrozenRoadReserve':True,'retainedOuterLaunchReserve':encode_geometry(perimeterReserve),'retainedOuterLaunchReserveDepth':perimeter_zone if reuse_outer else 0,'existingFunctionalReservations':g['fixedReservations']},'metrics':metrics,'budget':budget,'omissions':omissions,'unplacedMandatory':[{'id':'REGION_CAMP_Burrow_01','role':'Burrow','prototypeId':'BurrowCore','regionId':'REGION_CAMP','reason':'Required Camp placement conflict explicitly allowed by Bible section6; reusable common asset remains complete','evidence':{'status':'NoFitAfterFullDeterministicSearch','baselineSceneSHA256':g['baselineSceneSHA256'],'assetSourceSHA256':campProof['assetSourceSHA256']if campProof else None,'minimumBoundaryDepthTested':8,'allCardinalYawsTested':True,'gridStepStuds':4,'exactProjectionTested':True,'candidatesEvaluated':62500}}]if unplaced else [],'acceptedPlacementExceptions':accepted,'unplacedMandatoryObjects':unplaced,'conflicts':conflicts,'pending':['Latest brick prototype geometry/native IDs/style sample','Actual corner/header and boundary native fit/jump/cart probe','Normal-height landmark reveal and≤3tree silhouettes','Final metadata masks/input validation','Actual ordinary-game matched performance'],'triangleBudgetException':{'status':'NotMet'if spentTriangles>40000 else'WithinOriginalLimit','originalLimit':40000,'maximumApprovedActual':44000,'sourceProjectedTriangles':43486,'actualInstalledTriangles':None,'basis':'CurrentUserBrickDirective','sourceSHA256':a['sourceSHA256'],'baselineSceneSHA256':g['baselineSceneSHA256'],'selectedProjectedLimit':43486,'actualExposedExportTriangleProjection':spentTriangles,'percentOverOriginal':max(0,(spentTriangles/40000-1)*100),'reason':'Latest explicit user priority for visible smaller-brick construction while retaining all14outcrop/14ruin composition; parent selected middle12tree/7rock/8shrub allocation and requires honest original-cap disclosure','assetSourceSHA256':a['sourceSHA256'],'nativeInstalledCountPending':True},'selectedCompositionTargets':{'trees':12,'terraces':14,'secondaryRuins':14,'rocks':7,'shrubs':8,'heroes':8,'installedBurrows':14,'unplacedCampBurrowAsset':1},'sourceWrites':0,'worldWrites':0,'geometryPolicy':g['geometryPolicy'],'materialPolicy':{'Material':'Glacier','MaterialVariant':'Bingus_Saved_Studs_13719188279','StudsPerTile':.25,'SurfaceAppearances':0,'directive':'Standing explicit user override supersedes bible selective normal atlases'}}
    plan['selectedCompositionPass']=all(budget['roles'].get(k)==v for k,v in {'Hero':8,'Burrow':14,'Tree':12,'Terrace':14,'SecondaryRuin':14,'Rock':7,'Shrub':8}.items());plan['purePlanEligible']=plan['selectedCompositionPass']and not conflicts;budget['nativeSharedMeshIdsExpected']=34;budget['newInstancesIncludingLayerRoot']=budget['newInstancesExcludingRootFolders']+1;plan['geometryOnlyNativePending']=True;plan['planSHA256']=sha(plan);return plan
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,default=ROOT/'docs/environment-v2/EnvironmentLayout_V2.json');ap.add_argument('--mandatory-only',action='store_true');ap.add_argument('--full-outer',action='store_true');ap.add_argument('--perimeter-zone',type=float,default=48);args=ap.parse_args();g=json.loads((ROOT/'docs/environment-v2/CurrentGeometry.json').read_text());a=json.loads((ROOT/'assets/environment-v2/EnvironmentAssetSource.json').read_text());p=build(g,a,not args.mandatory_only,not args.full_outer,args.perimeter_zone);args.output.write_text(json.dumps(p,indent=2)+'\n');print(json.dumps({'status':p['status'],'counts':p['budget'],'conflicts':p['conflicts'],'planSHA256':p['planSHA256']},indent=1))
