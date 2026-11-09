#!/usr/bin/env python3
"""A stale or mismatched cached compiler must never silently reach an IPA."""
import hashlib,importlib.util,json,tempfile,unittest,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('reuse',ROOT/'scripts/reuse_spatial_driver.py');reuse=importlib.util.module_from_spec(spec);spec.loader.exec_module(reuse)
class ReusedDriverTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.p=Path(self.tmp.name)
  self.old=(reuse.ROOT,reuse.ZIP_SHA256);self.addCleanup(lambda:setattr(reuse,'ROOT',self.old[0]));self.addCleanup(lambda:setattr(reuse,'ZIP_SHA256',self.old[1]));reuse.ROOT=self.p
  digest=hashlib.sha256()
  for n in reuse.INPUTS:
   p=self.p/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(n.encode());digest.update(n.encode())
  self.manifest={'upstream_commit':reuse.PIN,'native_archive_abi':2,'native_archive_cache_schema':2,'native_archive_compatibility_id':reuse.COMPAT,'husk_spatial_patch_sha256':digest.hexdigest()}
  project=self.p/'src/app/project.yml';project.parent.mkdir(parents=True,exist_ok=True);project.write_text('dependencies:\n      # The PS4 layer: Bachata-S4\n')
 def archive(self,unsafe=False):
  zpath=self.p/'driver.zip'
  with zipfile.ZipFile(zpath,'w')as z:
   z.writestr('HuskMoltenVK.framework/HuskSpatialBuild.json',json.dumps(self.manifest));z.writestr('HuskMoltenVK.framework/HuskMoltenVK',b'verified-binary-fixture')
   if unsafe:z.writestr('HuskMoltenVK.framework/../../escape',b'bad')
  reuse.ZIP_SHA256=hashlib.sha256(zpath.read_bytes()).hexdigest();return zpath
 def test_matching_source_contract_stages_one_framework_and_preserves_other_dependencies(self):
  reuse.stage(self.archive());self.assertEqual((self.p/'build/ios-arm64/lib/HuskMoltenVK.framework/HuskMoltenVK').read_bytes(),b'verified-binary-fixture');self.assertIn('# The PS4 layer',(self.p/'src/app/project.yml').read_text())
 def test_wrong_archive_checksum_is_rejected(self):
  p=self.archive();reuse.ZIP_SHA256='0'*64
  with self.assertRaises(SystemExit):reuse.stage(p)
  self.assertFalse((self.p/'build').exists())
 def test_changed_compiler_inputs_are_rejected(self):
  p=self.archive();(self.p/reuse.INPUTS[0]).write_text('changed')
  with self.assertRaises(SystemExit):reuse.stage(p)
  self.assertFalse((self.p/'build').exists())
 def test_wrong_archive_compatibility_is_rejected(self):
  self.manifest['native_archive_compatibility_id']='old'
  with self.assertRaises(SystemExit):reuse.stage(self.archive())
 def test_path_traversal_is_rejected_before_extracting(self):
  with self.assertRaises(SystemExit):reuse.stage(self.archive(True))
  self.assertFalse((self.p/'build').exists())
if __name__=='__main__':unittest.main()
