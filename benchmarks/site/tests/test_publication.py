"""Publication rejects missing, stale and invisible assessments."""
import hashlib,html,importlib.util,json,tempfile,unittest
from pathlib import Path
SITE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('gate',SITE/'validate-publication.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)

class PublicationTests(unittest.TestCase):
    def fixture(self,root):
        public=root/'public';public.mkdir()
        (root/'archive-manifest.json').write_text('{"files":{}}',encoding='utf-8')
        (public/'result.json').write_text('{"score":80}',encoding='utf-8')
        entry=dict(id='test',data='result.json',data_sha256=gate.digest(public/'result.json'),coverage='50/50',status='complete')
        for key in gate.FIELDS:entry[key]='Evidence assessment for '+key+' with specific recorded observations.'
        (public/'test-evaluations.json').write_text(json.dumps({'schema':'publication-assessments/1.0','studies':[entry]}),encoding='utf-8')
        (public/'evaluations.html').write_text('<article id="test">'+''.join(html.escape(entry[k]) for k in gate.FIELDS)+'</article>',encoding='utf-8')
        (public/'index.html').write_text('<a href="evaluations.html">Assessments</a>',encoding='utf-8')
        return public

    def test_live_publication_contract(self):self.assertEqual(len(gate.validate()),3)
    def test_changed_scores_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=self.fixture(root);(p/'result.json').write_text('{"score":90}')
            with self.assertRaisesRegex(ValueError,'Stale assessment'):gate.validate(root)
    def test_new_unassessed_export_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=self.fixture(root);(p/'new.json').write_text('{"score":60}')
            with self.assertRaisesRegex(ValueError,'without evaluation'):gate.validate(root)
    def test_unpublished_assessment_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=self.fixture(root);(p/'evaluations.html').write_text('<p>No assessment</p>')
            with self.assertRaisesRegex(ValueError,'not published'):gate.validate(root)
    def test_format_only_changes_preserve_data_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);p=self.fixture(root);(p/'result.json').write_text('{\n  "score": 80\n}\n')
            self.assertEqual(len(gate.validate(root)),1)

if __name__=='__main__':unittest.main()
