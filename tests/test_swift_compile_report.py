from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from swift_compile_report import diagnose

class SwiftCompileReportTests(unittest.TestCase):
    def test_only_fixed_sources_lines_and_categories_are_retained(self):
        text = '/private/secret/ArcadeControls.swift:93:20: error: cannot convert private-token to private-type\n'
        self.assertEqual(diagnose(text), [('ARCADE_CONTROLS', 93, 'TYPE_MISMATCH')])
        self.assertNotIn('private', str(diagnose(text)))
    def test_order_and_typecheck_have_distinct_safe_codes(self):
        self.assertEqual(diagnose('App/ExpandedArcadeView.swift:80:3: error: argument width must precede argument height'),
                         [('ARCADE_VIEW',80,'ARGUMENT_ORDER')])
        self.assertEqual(diagnose('App/ExpandedSolitaireView.swift:40:3: error: unable to type-check this expression in reasonable time'),
                         [('SOLITAIRE_VIEW',40,'TYPECHECK_LIMIT')])
    def test_unknown_files_numbers_and_non_errors_cannot_leak_raw_output(self):
        for text in ['private key or JWT is forbidden', 'secret/Filename.swift:9:2: error: hidden',
                     'App/ArcadeControls.swift:99999:2: error: hidden']:
            self.assertTrue(all(source == 'UNKNOWN_SOURCE' for source,_,_ in diagnose(text)))
            self.assertNotIn('hidden', str(diagnose(text)))

if __name__ == '__main__': unittest.main()
