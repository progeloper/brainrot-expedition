#!/usr/bin/env python3
"""Exercise binary import axes/corners/closure and rejection of damaged exports."""
import copy,json,struct,tempfile,unittest
from pathlib import Path
from CompactNativeGeometry import encode,read_glb,decoded_groups,validate_binary,canonical,cross,sub,dot
from CompactBuildNativeAssets import unit_cube
class NativePackingTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.path=Path(self.tmp.name)/'mesh.glb';self.source=[unit_cube()]
 def tearDown(self):self.tmp.cleanup()
 def put(self,raw):self.path.write_bytes(raw)
 def corrupt_accessor(self,semantic,value,corner=0):
  raw=bytearray(encode(self.source));doc,_,_=read_glb_bytes(raw);index=doc['meshes'][0]['primitives'][0]['attributes'][semantic];a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];jsonlen=struct.unpack_from('<I',raw,12)[0];start=12+8+jsonlen+8+v['byteOffset']+a.get('byteOffset',0)+corner*{'POSITION':12,'NORMAL':12,'TEXCOORD_0':8}[semantic];struct.pack_into('<f',raw,start,value);return raw
 def test_both_coordinate_exports_preserve_all36_corners(self):
  for comp in [False,True]:self.put(encode(self.source,comp));r=validate_binary(self.path,self.source,comp);self.assertEqual(r['checkedCorners'],36);self.assertEqual(r['triangles'],12)
 def test_native_compensation_flips_positions_normals_and_translation(self):
  g=copy.deepcopy(self.source);g[0]['centre']=[123,7,-89];self.put(encode(g,True));d,b,_=read_glb(self.path);r=decoded_groups(d,b)['CompactWallCube_Unit'];self.assertEqual(r['translation'],[-123,7,89]);self.assertEqual(r['positions'][0],[-.5,-.5,.5]);self.assertEqual(r['normals'][0],[-1,0,0])
 def test_wrong_compensation_is_rejected(self):
  self.put(encode(self.source,True))
  with self.assertRaises(AssertionError):validate_binary(self.path,self.source,False)
 def test_damaged_position_is_rejected(self):
  self.put(self.corrupt_accessor('POSITION',.49))
  with self.assertRaises(AssertionError):validate_binary(self.path,self.source)
 def test_damaged_uv_is_rejected(self):
  self.put(self.corrupt_accessor('TEXCOORD_0',.1))
  with self.assertRaises(AssertionError):validate_binary(self.path,self.source)
 def test_damaged_hardnormal_is_rejected(self):
  self.put(self.corrupt_accessor('NORMAL',.9))
  with self.assertRaises(AssertionError):validate_binary(self.path,self.source)
 def test_invalid_glb_length_is_rejected(self):
  raw=bytearray(encode(self.source));struct.pack_into('<I',raw,8,len(raw)+4);self.put(raw)
  with self.assertRaises(AssertionError):read_glb(self.path)
 def test_closed_cube_edges_and_unit_volume(self):
  g=self.source[0];p=g['positions'];edges={};volume=0
  for i in range(0,len(p),3):
   t=[tuple(v) for v in p[i:i+3]];volume+=dot(t[0],cross(t[1],t[2]))/6
   for a,b in zip(t,t[1:]+t[:1]):edges.setdefault(tuple(sorted([a,b])),[]).append((a,b))
  self.assertEqual(len(edges),18);self.assertAlmostEqual(volume,1)
  for pair in edges.values():self.assertEqual(len(pair),2);self.assertEqual(pair[0],tuple(reversed(pair[1])))
 def test_writer_preserves_source_values(self):
  frozen=canonical(self.source);encode(self.source);encode(self.source,True);self.assertEqual(canonical(self.source),frozen)
def read_glb_bytes(raw):
 # Reuse public parser through a temporary file; no mocked decoding assumptions.
 with tempfile.TemporaryDirectory() as d:
  p=Path(d)/'read.glb';p.write_bytes(raw);return read_glb(p)
if __name__=='__main__':unittest.main(verbosity=2)
