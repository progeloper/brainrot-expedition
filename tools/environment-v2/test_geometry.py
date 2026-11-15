"""Pure geometric and actual-baseline planner contract tests; no native mutation."""
import unittest,json,math,hashlib,sys
from pathlib import Path
from shapely.geometry import box,Polygon,LineString
from shapely.ops import unary_union
from geometry import *
from boundary import rectangles,plan_boundary
from plan import window_density,burrow_object,canopy_local
ROOT=Path(__file__).resolve().parents[2]
class PureGeometry(unittest.TestCase):
 def test_cardinal_frame_convention_and_componentwise_scaling(self):
  self.assertEqual(cfpoint(frame(10,5,20,90),[1,3,2]),[12,8,19])
  proto={'id':'box','bounds':{'min':[-1,0,-2],'max':[1,2,2]},'groups':[{'id':'A','role':'Stone'}],'components':[{'id':'a','centre':[0,1,0],'size':[2,2,4],'group':'A'}],'colliders':[]}
  obj=placed_object(proto,'a',REGIONS[0],'Hero',10,5,20,90,[2,3,4]);self.assertEqual(obj['rootCFrame'][:3],[10,5,20]);self.assertEqual(obj['bounds'],{'minX':2,'maxX':18,'minY':5,'maxY':11,'minZ':18,'maxZ':22})
 def test_true_l_union_not_aabb(self):
  regions={k:Polygon()for k in REGIONS};regions[REGIONS[0]]=box(0,0,20,10).union(box(0,10,10,20));regions[REGIONS[1]]=box(10,10,20,20)
  rows=[r for r in true_boundaries(regions)if r['kind']=='Shared'];self.assertEqual(len(rows),2);self.assertEqual(sum(r['last']-r['first']for r in rows),20)
 def test_full_thickness_diagonal_prism_clip(self):
  run={'axis':'X','fixed':0,'first':-20,'last':20};shape=Polygon([(-10,-100),(10,100),(12,100)])
  interval=prism_intervals(run,6,shape)[0];self.assertAlmostEqual(interval[0],-.3);self.assertAlmostEqual(interval[1],1.33)
  center=shape.intersection(LineString([(-20,0),(20,0)])).bounds;self.assertLess(interval[0],center[0]);self.assertGreater(interval[1],center[2])
 def test_disjoint_rectangular_corner_partition(self):
  geom=box(0,0,30,6).union(box(12,-10,18,16));rs=rectangles(geom);self.assertAlmostEqual(sum(r.area for r in rs),geom.area)
  self.assertTrue(all(a.intersection(b).area<1e-8 for i,a in enumerate(rs)for b in rs[i+1:]))
 def test_area_grid_keeps_partial_denominator(self):
  result=open_grid_metrics(box(0,0,10,10),box(0,0,1,10),box(8,0,9,10),(0,0));self.assertAlmostEqual(result['usableWeightedCellsArea'],90);self.assertAlmostEqual(result['blockedWeightedCellsArea'],20);self.assertAlmostEqual(result['openFraction'],70/90);self.assertGreater(result['partialUsableCells'],0)
 def test_any_window_not_only_aligned_grid(self):
  points=[('a',3,3),('b',64,64),('c',65,2),('d',66,2),('e',67,2)];result=window_density(points);self.assertEqual(result['count'],5);self.assertIn('a',result['ids'])
 def test_canopy_uses_role_and_union(self):
  proto={'groups':[{'id':'A','role':'Cap'}],'components':[{'group':'A','centre':[0,2,0],'size':[10,2,10]},{'group':'A','centre':[5,2,0],'size':[10,2,10]}]};self.assertEqual(canopy_local(proto).area,150)
class ActualBaseline(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.g=json.loads((ROOT/'docs/environment-v2/CurrentGeometry.json').read_text());cls.plan=json.loads((ROOT/'docs/environment-v2/EnvironmentLayout_V2.json').read_text());cls.a=json.loads((ROOT/'assets/environment-v2/EnvironmentAssetSource.json').read_text())
 def test_fresh_baseline_binding(self):
  raw=(ROOT/'docs/environment-v2/BeforeManifest.json').read_bytes();self.assertEqual(hashlib.sha256(raw).hexdigest(),self.g['baselineSceneSHA256']);self.assertEqual(len(self.g['floors']),25);self.assertEqual(len(self.g['roads']),27);self.assertEqual(sum(r['actualNativeCorners']for r in self.g['roads']),3141)
 def test_current_seams_and_closed_opening_ownership(self):
  b=self.plan['boundary'];self.assertEqual(b['sharedRuns'],18);self.assertEqual(b['outerRuns'],4);self.assertEqual(b['logicalLintels'],7);self.assertEqual(b['moduleCount'],70);self.assertFalse(self.plan['budget']['boundaryTargetPass']);allowed={o['id']for o in self.g['openings']}
  self.assertTrue(all(c['id']in allowed for r in b['runs']for c in r['openingCuts']))
  geom=decode_geometry(b['groundPolygons']);self.assertTrue(all(geom.covers(Point(c['intersection'][0],c['intersection'][2]))for c in self.g['closedAlternates']));self.assertEqual(len(self.g['closedAlternates']),5)
 def test_required_concrete_rows_and_explicit_camp_exception(self):
  rows=self.plan['objects'];self.assertEqual(sum(r['role']=='Hero'for r in rows),8);self.assertEqual(sum(r['role']=='Burrow'for r in rows),14);self.assertEqual(len(self.plan['unplacedMandatoryObjects']),1);self.assertFalse(self.plan['unplacedMandatoryObjects'][0]['install'])
  for region,cs in self.plan['reservations']['clearings'].items():
   self.assertEqual(len(cs),2);self.assertTrue(decode_geometry(cs[0]['polygons']).intersection(decode_geometry(cs[1]['polygons'])).area<1e-6)
   for c in cs:
    self.assertEqual(len(c['rayEnds']),2)
    for a,b in c['rayEnds']:self.assertAlmostEqual(math.dist(a,b),60)
  self.assertEqual(len(self.plan['reservations']['clearings']),7)
 def test_four_grid_and_apron_ownership(self):
  regions={r:decode_geometry(p)for r,p in self.g['regions'].items()}
  for o in self.plan['objects']:
   if o['role']=='Boundary':continue
   self.assertAlmostEqual((o['rootCFrame'][0]-self.g['origin'][0])/4,round((o['rootCFrame'][0]-self.g['origin'][0])/4));self.assertAlmostEqual((o['rootCFrame'][2]-self.g['origin'][1])/4,round((o['rootCFrame'][2]-self.g['origin'][1])/4));self.assertTrue(regions[o['regionId']].covers(object_geometry(o)))
   if o['role']=='Burrow':
    self.assertEqual(len(o['colliders']),7);self.assertEqual(len(o['markers']),4);self.assertTrue(regions[o['regionId']].covers(decode_geometry(o['apronPolygons'])));self.assertFalse(o['interface']['Art_RuntimeRegistered']);self.assertIn('groundConnection',o['clearanceEvidence'])
 def test_per_chunk_conservative_height_formula(self):
  for row in self.plan['objects']:
   if row['role']!='Boundary'or row['boundaryKind']=='GateLintel':continue
   p=row['heightSafetyEvidence'];expected=max(72,4*math.ceil((p['highestConservativeCollidingTopRelativeGround']+8+6.6161232+8)/4));self.assertEqual(p['minimumCoreHeight'],expected);self.assertGreaterEqual(row['coreHeight'],expected);self.assertGreaterEqual(row['colliders'][0]['maxY']-self.g['groundY'],row['coreHeight'])
 def test_no_fake_geometry_security_or_native_count(self):
  self.assertEqual(self.plan['sourceWrites'],0);self.assertEqual(self.plan['worldWrites'],0);self.assertEqual(self.plan['materialPolicy']['StudsPerTile'],.25);self.assertEqual(self.plan['materialPolicy']['SurfaceAppearances'],0);self.assertEqual(self.plan['boundary']['securityStatus']['ClosedPaidThreshold'],'NotAchieved');self.assertIsNone(self.plan['budget']['actualNativeInstalledTriangleCount'])
 def test_exhaustive_camp_conflict_independent_of_scenery(self):
  e=json.loads((ROOT/'docs/environment-v2/CampBurrowExhaustiveFit.json').read_text());self.assertEqual(e['testedCandidates'],62500);self.assertTrue(all(r['withinCampRoadAndFixedClear']==0 for r in e['yawEvidence']));self.assertTrue(all(r['validWithMinimum8StudBoundaryDepth']==0 for r in e['yawEvidence']))
if __name__=='__main__':unittest.main(verbosity=2)
