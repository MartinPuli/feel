import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('chalk_report',Path(__file__).parents[1]/'chalk_report.py')
report=importlib.util.module_from_spec(spec);spec.loader.exec_module(report)

class ChalkReportTests(unittest.TestCase):
    def sample(self):
        return {'cases':1,'rows':[{'case_id':'<script>unsafe</script>','latency_ms':20,'model':'fixture','prompt_version':'fixture','scores':{'correct':False},'error':'timeout'}],'dataset_sha256':'abc','validation':'MOCK_NOT_LIVE'}
    def test_failures_stay_in_denominator_and_no_fabricated_baseline(self):
        text=report.render(self.sample())
        self.assertIn('0/1 correct',text);self.assertIn('1 request errors',text);self.assertIn('No improvement claim',text)
    def test_report_escapes_untrusted_case_names(self):
        text=report.render(self.sample())
        self.assertNotIn('<script>unsafe</script>',text);self.assertIn('&lt;script&gt;',text)
    def test_refuses_different_inputs(self):
        with self.assertRaises(ValueError):report.render(self.sample(),dict(self.sample(),dataset_sha256='different'))
    def test_refuses_mock_as_live_baseline(self):
        with self.assertRaises(ValueError):report.render(dict(self.sample(),validation='LIVE_CHALK_GATEWAY'),self.sample())
