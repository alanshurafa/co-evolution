"""Offline build, archive preservation and injection-boundary checks."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

SITE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('observatory', SITE / 'build-observatory.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ObservatoryTests(unittest.TestCase):
    def setUp(self):
        self.catalog = builder.load_catalog(SITE / 'observatory-catalog.json', SITE / 'public')

    def test_build_preserves_export_exactly(self):
        page = builder.render(self.catalog)
        embedded = json.loads(re.search(r'<script id="observatory-data" type="application/json">(.*?)</script>', page, re.S).group(1))
        source = json.loads((SITE / 'public/current-results.json').read_text(encoding='utf-8'))
        self.assertEqual(embedded['suites'][0]['results'], source)

    def test_original_site_is_byte_identical(self):
        manifest = json.loads((SITE / 'archive-manifest.json').read_text())
        for filename, expected in manifest['files'].items():
            with self.subTest(filename=filename):
                self.assertEqual(hashlib.sha256((SITE / 'public' / filename).read_bytes()).hexdigest(), expected)

    def test_untrusted_data_cannot_break_out_of_script(self):
        catalog = copy.deepcopy(self.catalog)
        attack = '__FALLBACK__</script><script>alert("bad")</script>'
        catalog['suites'][0]['results']['title'] = attack
        page = builder.render(catalog)
        self.assertNotIn(attack, page)
        embedded = json.loads(re.search(r'<script id="observatory-data" type="application/json">(.*?)</script>', page, re.S).group(1))
        self.assertEqual(embedded['suites'][0]['results']['title'], attack)

    def test_new_suite_can_be_registered_without_ui_changes(self):
        catalog = json.loads((SITE / 'observatory-catalog.json').read_text())
        entry = copy.deepcopy(catalog['suites'][0])
        entry.update(id='future-standardized-subset', name='Future subset', data='future.json', methodology='future-methodology.html')
        catalog['suites'].append(entry)
        catalog['default_suite'] = entry['id']
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for current in catalog['suites']:
                data = copy.deepcopy(self.catalog['suites'][0]['results'])
                data['suite']['id'] = current['id']
                (root/current['data']).write_text(json.dumps(data), encoding='utf-8')
                (root/current['methodology']).write_text('<html></html>')
            for archive in catalog['archives']:
                (root/archive['href']).write_text('<html></html>')
            path = root/'catalog.json'
            path.write_text(json.dumps(catalog), encoding='utf-8')
            loaded = builder.load_catalog(path,root)
            self.assertEqual(len(loaded['suites']),2)
            self.assertIn('future-standardized-subset', builder.render(loaded))
            catalog['suites'][1]['id'] = catalog['suites'][0]['id']
            path.write_text(json.dumps(catalog), encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'Duplicate suite'):
                builder.load_catalog(path,root)

    def test_catalog_paths_cannot_escape_public_directory(self):
        with self.assertRaises(ValueError):
            builder.local_file(SITE/'public','../observatory.js')

    def test_built_page_is_current(self):
        self.assertEqual((SITE/'public/index.html').read_text(encoding='utf-8'),builder.render(self.catalog))


if __name__ == '__main__':
    unittest.main()
