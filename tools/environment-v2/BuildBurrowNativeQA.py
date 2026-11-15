from pathlib import Path
import json,hashlib,math,subprocess
ROOT=Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
HERE=ROOT/'tools/environment-v2'
source=json.loads((ROOT/'assets/environment-v2/EnvironmentAssetSource.json').read_text())
plan=json.loads((ROOT/'docs/environment-v2/EnvironmentLayout_V2.json').read_text())
wildpath=ROOT/'docs/environment-v2/ActualWildNativeExtentsSummary.json'
wild=json.loads(wildpath.read_text())
assert wild['status']=='NativeExtentMeasurementPassed' and len(wild['rows'])==35
def convex_cells(poly):
 assert not poly.get('holes'),'Frozen reservation holes require explicit decomposition'
 ring=[list(q) for q in poly['exterior']]
 if ring[0]==ring[-1]:ring.pop()
 def cross(a,b,c):return (b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0])
 changed=True
 while changed and len(ring)>3:
  changed=False
  for j in range(len(ring)):
   if abs(cross(ring[j-1],ring[j],ring[(j+1)%len(ring)]))<1e-9:
    ring.pop(j);changed=True;break
 def area(r):return sum(r[j][0]*r[(j+1)%len(r)][1]-r[(j+1)%len(r)][0]*r[j][1]for j in range(len(r)))/2
 expectedarea=abs(area(ring))
 if area(ring)<0:ring.reverse()
 out=[];remaining=ring[:]
 while len(remaining)>3:
  found=False
  for j,b in enumerate(remaining):
   a=remaining[j-1];c=remaining[(j+1)%len(remaining)]
   if cross(a,b,c)<=1e-9:continue
   if any(all(cross(u,v,q)>=-1e-9for u,v in [(a,b),(b,c),(c,a)])for k,q in enumerate(remaining)if k not in [(j-1)%len(remaining),j,(j+1)%len(remaining)]):continue
   out.append([a,b,c]);remaining.pop(j);found=True;break
  assert found,'Cannot triangulate frozen simple polygon'
 out.append(remaining)
 assert abs(sum(abs(area(r))for r in out)-expectedarea)<1e-6
 poly['convexCells']=out
 poly['decompositionArea']=expectedarea
 return poly
rows=[]
for r in plan['objects']:
 if r['role']=='Burrow':
  rows.append({k:r[k]for k in ['id','regionId','rootCFrame','colliders','apronPolygons']})
  rows[-1]['markers']={m['name']:m['worldCFrame']for m in r['markers']}
  rows[-1]['apronPolygons']=[convex_cells(q)for q in rows[-1]['apronPolygons']]
assert len(rows)==14 and all(len(x['colliders'])==7 and len(x['markers'])==4 for x in rows)
external=[]
for rr in plan['reservations']['clearings'].values():
 for r in rr:
  for i,p in enumerate(r['polygons']):external.append({'id':r['id']+f'/Polygon{i+1}','kind':'HuntingClearing','polygon':convex_cells(p),'groundY':rows[0]['rootCFrame'][1]})
for r in plan['reservations']['connections']:
 for i,p in enumerate(r['polygons']):external.append({'id':r['id']+f'/Polygon{i+1}','kind':'ApproachConnection','polygon':convex_cells(p),'groundY':rows[0]['rootCFrame'][1]})
eyes=[]
for y in [3,7]:
 for x in [-12,0,12]:eyes.append([x,y,0])
 for d in [24,48]:
  for a in [-30,0,30]:eyes.append([math.sin(math.radians(a))*d,y,-math.cos(math.radians(a))*d])
data={'sourceSHA256':source['sourceSHA256'],'planSHA256':plan['planSHA256'],'wildEvidenceSHA256':hashlib.sha256(wildpath.read_bytes()).hexdigest(),'wild':{r['id']:{'min':r['native']['min'],'max':r['native']['max'],'scale':r['canonicalScale'],'groundPivot':r['groundPivot']}for r in wild['rows']},'rooms':rows,'externalReservations':external,'pathOrder':['Art_Hide','Art_Turn','Art_Mouth','Art_Exit'],'occlusionEyes':eyes}
# Preserve the frozen native-tested geometry/query ordering after unrelated
# manifest key sorting; only the expected plan-hash string should change.
colliderkeys=['id','cframe','size','minX','maxX','minY','maxY','minZ','maxZ','sourceComponents']
for room in data['rooms']:room['colliders']=[{k:b[k]for k in colliderkeys}for b in room['colliders']]
prior=json.loads((HERE/'revisions/burrow-qa-plan-7bb49/BurrowNativeFitExpected.json').read_text())
order={r['id']:i for i,r in enumerate(prior['externalReservations'])}
assert set(order)=={r['id']for r in data['externalReservations']}
data['externalReservations'].sort(key=lambda row:order[row['id']])
oldvalues=prior.copy();newvalues=data.copy();oldvalues.pop('planSHA256');newvalues.pop('planSHA256')
assert oldvalues==newvalues,'Burrow/native/reservation geometry changed; explicit new review required'
expected=json.dumps(data,separators=(',',':'))
(HERE/'BurrowNativeFitExpected.json').write_text(json.dumps(data,indent=2)+'\n')
template=(HERE/'VerifyBurrowNativeFit.template.luau').read_text()
mathsource=(HERE/'BurrowFitMath.luau').read_text()
generated=template.replace('__EXPECTED_JSON__',expected).replace('-- __MATH_SOURCE__',mathsource)
generated=subprocess.run(['stylua','-'],input=generated,text=True,capture_output=True,check=True).stdout
current=HERE/'VerifyBurrowNativeFit.luau'
if not current.exists() or current.read_text()!=generated:current.write_text(generated)
print(json.dumps({'rooms':len(rows),'markers':sum(len(r['markers'])for r in rows),'colliders':sum(len(r['colliders'])for r in rows),'external':len(external)+14,'species':35,'sourceSHA':source['sourceSHA256'],'planSHA':plan['planSHA256'],'nativeQA':'NotRun'}))
