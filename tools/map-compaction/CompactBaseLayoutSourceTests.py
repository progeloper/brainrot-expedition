#!/usr/bin/env python3
"""Meaningful independent geometry/data invariants; no mocked Studio/gameplay pass."""
import importlib.util,json,pathlib,math,unittest,hashlib
ROOT=pathlib.Path('/Users/noahodukoya/development/Roblox/BrainrotExpedition')
spec=importlib.util.spec_from_file_location('author',ROOT/'tools/map-compaction/CompactBaseLayoutAuthor.py');A=importlib.util.module_from_spec(spec);spec.loader.exec_module(A)
class GeometryTests(unittest.TestCase):
 def setUp(self):
  self.all=json.loads((ROOT/'docs/map-compaction/CompactBaseLayoutCandidates.json').read_text());self.c=next(c for c in self.all['candidates']if c['b']==.85);self.g=self.c['geometry'];self.p=json.loads((ROOT/'tools/map-compaction/CompactBaseLayoutShell_085.mesh-data.json').read_text())['CompactShowhouseShell_A']
 def test_preferred_rejected_on_anchored_bounds(self):
  first=self.all['candidates'][0];self.assertFalse(first['analyticalRectangleContainmentPassed']);self.assertTrue(any('minX'in x for x in first['analyticalFailures']));self.assertTrue(any('maxZ'in x for x in first['analyticalFailures']))
 def test_first_candidate_source_only(self):
  self.assertEqual(self.all['firstAnalyticalCandidate'],.85);self.assertTrue(self.c['analyticalRectangleContainmentPassed']);self.assertTrue(self.c['acceptance']['nativeFixturePassed']);self.assertEqual(self.c['nativeFitEvidence']['nativeDisplayPlacements'],768);self.assertFalse(self.all['fullAcceptancePassed'])
 def test_stable_12_uniform_final_slots(self):
  self.assertEqual([s['Index']for s in self.g['slots']],list(range(1,13)))
  for i,s in enumerate(self.g['slots']):self.assertEqual(s['Side'],-1 if i<6 else 1);self.assertAlmostEqual(s['Z'],self.g['zCenters'][i%6]);self.assertAlmostEqual(s['X'],self.g['formationCenterX']+s['Side']*self.g['rowOffsetX'])
  for a,b in zip(self.g['zCenters'],self.g['zCenters'][1:]):self.assertAlmostEqual(b-a,12.18)
 def test_claim_plaques_included_in_aisle(self):
  self.assertAlmostEqual(2*self.g['rowOffsetX']-self.g['padNormalStuds']-2*(.55+2.25),6.02)
 def test_asymmetric_loaded_support_not_span_plus4(self):
  native=json.loads((ROOT/'docs/map-compaction/CompactBaseLayoutNativeCargo.json').read_text());z=native['maximumLoadedEnvelope'];self.assertEqual(native['centredCartPadRequired']['depth'],36);self.assertGreater(36,z['size'][2]+4)
 def test_pad_contains_actual_native_worst_with_margin(self):
  measured=json.loads((ROOT/'docs/map-compaction/RuntimeBaseFitNative_Before.json').read_text());count=0
  for base in measured['bases']:
   for sp in base['measuredSpecies']:
    for side in sp['bySide'].values():
     b=side['platformBounds'];self.assertGreaterEqual(self.g['padTangentialStuds']/2-max(abs(b['min'][0]),abs(b['max'][0])),1);self.assertGreaterEqual(self.g['padNormalStuds']/2-max(abs(b['min'][2]),abs(b['max'][2])),1);count+=1
  self.assertEqual(count,768)
 def test_preserved_loop_and_functional_ramp_connections(self):
  a=self.c['functionalApproachCorrection'];self.assertAlmostEqual(self.c['supportBounds']['minZ']-a['loopNearEdgeZ'],2);self.assertAlmostEqual(self.c['cartSupport']['bounds']['minZ']-a['loopNearEdgeZ'],2)
  for name,width in [('houseRamp',20),('cartRamp',24)]:r=a[name];self.assertEqual(r['width'],width);self.assertEqual(r['depth'],12);self.assertAlmostEqual(r['centreZ']+6-self.c['supportBounds']['minZ'],.2)
  second=self.all['candidates'][1];self.assertFalse(second['analyticalRectangleContainmentPassed']);self.assertTrue(any('maxZ'in x for x in second['analyticalFailures']))
 def test_frozen_topology_y_and_component_identity(self):
  old=json.loads((ROOT/'assets/map-art/redesign/mesh-data.json').read_text())['ShowhouseShell_A'];self.assertEqual(len(self.p['components']),32)
  for a,b in zip(old['components'],self.p['components']):self.assertEqual(a['id'],b['id']);self.assertEqual(a['faces'],b['faces']);self.assertEqual(a['group'],b['group']);self.assertEqual([v[1]for v in a['vertices']],[v[1]for v in b['vertices']])
 def test_post_horizontal_crosssections_and_y(self):
  for c in self.p['components']:
   if c['id'].startswith('corner_buttress'):self.assertEqual(self.p['component_transforms'][c['id']]['scale'],[.85,1,.85])
 def test_flat_unit_normals_winding(self):
  checked=0
  for g in self.p['group_meshes'].values():
   for tri in g['triangles']:
    normals=[g['normals'][corner[2]-1]for corner in tri];self.assertEqual(normals[0],normals[1]);self.assertEqual(normals[1],normals[2]);self.assertAlmostEqual(sum(v*v for v in normals[0]),1,places=10);points=[g['vertices'][corner[0]-1]for corner in tri];geometric=A.normal(*points);self.assertGreater(sum(a*b for a,b in zip(geometric,normals[0])),.999999);checked+=1
  self.assertEqual(checked,1600)
 def test_transformed_proven_convex_cells(self):
  d=json.loads((ROOT/'tools/map-compaction/CompactBaseLayoutShell_085.csg.json').read_text());solids=[s for g in d['prototypes'][0]['groups']for s in g['solids']];self.assertEqual(len(solids),50)
  for s in solids:
   self.assertGreater(s['volume'],0)
   for plane in s['planes']:
    self.assertAlmostEqual(sum(v*v for v in plane['n']),1,places=9)
    for p in s['vertices']:self.assertLessEqual(sum(n*v for n,v in zip(plane['n'],p))-plane['d'],1e-7)
 def test_prepared_runtime_not_authoritative(self):
  r=json.loads((ROOT/'docs/map-compaction/CompactBaseLayoutRuntimeGeometry.Prepared.json').read_text());self.assertFalse(r['runtimeValidated']);self.assertEqual(len(r['bases']),12)
if __name__=='__main__':
 suite=unittest.defaultTestLoader.loadTestsFromTestCase(GeometryTests);result=unittest.TextTestRunner(verbosity=2).run(suite);out={'schemaVersion':1,'status':'Passed'if result.wasSuccessful()else'Failed','testScope':'Pure source geometry and actual saved native measurements; no Studio execution or gameplay assertions','testsRun':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'nativeFitExecution':'Separate root-owned current Studio run'};(ROOT/'docs/map-compaction/CompactBaseLayoutSourceTests.json').write_text(json.dumps(out,indent=2)+'\n');raise SystemExit(not result.wasSuccessful())
