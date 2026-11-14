#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('cache', ROOT / 'scripts/ipa_build_cache.py')
cache = importlib.util.module_from_spec(spec); spec.loader.exec_module(cache)

class CacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name); (self.p / 'input').write_text('source')
    def test_key_uses_content_not_timestamp(self):
        a = cache.digest_files(self.p, ['input'], 'sdk'); (self.p/'input').touch()
        self.assertEqual(a, cache.digest_files(self.p, ['input'], 'sdk'))
    def test_input_and_platform_changes_invalidate(self):
        a = cache.digest_files(self.p, ['input'], 'sdk')
        self.assertNotEqual(a, cache.digest_files(self.p, ['input'], 'other-sdk'))
        (self.p/'input').write_text('changed')
        self.assertNotEqual(a, cache.digest_files(self.p, ['input'], 'sdk'))
    def test_unrelated_app_edits_do_not_invalidate_component(self):
        a = cache.digest_files(self.p, ['input'], 'sdk'); (self.p/'app.swift').write_text('new UI')
        self.assertEqual(a, cache.digest_files(self.p, ['input'], 'sdk'))
    def test_sealed_component_verifies(self):
        cache.seal(self.p, 'key'); self.assertIn('input', cache.validate(self.p, 'key')['files'])
    def test_wrong_key_rejected(self):
        cache.seal(self.p, 'key')
        with self.assertRaises(ValueError): cache.validate(self.p, 'other')
    def test_corruption_rejected(self):
        cache.seal(self.p, 'key'); (self.p/'input').write_text('corrupt')
        with self.assertRaises(ValueError): cache.validate(self.p, 'key')
    def test_extra_file_rejected(self):
        cache.seal(self.p, 'key'); (self.p/'extra').write_text('extra')
        with self.assertRaises(ValueError): cache.validate(self.p, 'key')
    def test_symlink_rejected(self):
        (self.p/'link').symlink_to(self.p/'input')
        with self.assertRaises(ValueError): cache.seal(self.p, 'key')
    def test_project_embedding_idempotent(self):
        p=self.p/'src/app/project.yml';p.parent.mkdir(parents=True)
        p.write_text('      # The PS4 layer: Bachata-S4\n')
        cache.embed_driver(self.p); before=p.read_text();cache.embed_driver(self.p)
        self.assertEqual(before,p.read_text());self.assertIn('HuskMoltenVK.framework',before)

if __name__ == '__main__': unittest.main(verbosity=2)
