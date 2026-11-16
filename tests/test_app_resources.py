import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET
ROOT=pathlib.Path(__file__).resolve().parents[1]

class AppResourceTests(unittest.TestCase):
    def strings(self,language):
        source=(ROOT/'App/Resources'/f'{language}.lproj/Localizable.strings').read_text()
        matches=re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;',source)
        result={json.loads(key):json.loads(value) for key,value in matches}
        self.assertEqual(len(matches),len(result),'duplicate localization keys')
        return result
    def test_bilingual_keys_format_arguments_and_all_ui_references(self):
        zh=self.strings('zh-Hant');en=self.strings('en')
        self.assertEqual(set(zh),set(en));self.assertGreater(len(zh),90)
        format_pattern=r'%(?:\d+\$)?0?\d*[d@]'
        for key in zh:
            self.assertTrue(zh[key]);self.assertTrue(en[key])
            self.assertEqual(re.findall(format_pattern,zh[key]),re.findall(format_pattern,en[key]),key)
        for path in (ROOT/'App').glob('*.swift'):
            for key in re.findall(r'\bt\("([a-zA-Z][\w.]+)"',path.read_text()):
                if key.endswith('.'):continue
                self.assertIn(key,zh,str(path))
        for prefix,values in [('game',['sudoku','minesweeper','sliding']),('status',['notStarted','inProgress','completed','failed']),('difficulty',['easy','medium','hard','normal','custom']),('theme',['system','light','dark'])]:
            for value in values:self.assertIn(prefix+'.'+value,zh)
    def test_offline_documents_are_localized_and_planned_routes_not_live(self):
        for language in ['zh-Hant','en']:
            for name in ['Privacy','Terms','Support']:
                text=(ROOT/'App/Resources'/f'{language}.lproj/{name}.md').read_text()
                self.assertGreater(len(text),400);self.assertIn('0.1.1',text)
                self.assertNotIn('https://chaihome.cc',text)
        swift=(ROOT/'App/LegalView.swift').read_text()
        self.assertIn('https://github.com/Kongdean2374/ChaiClassics/issues',swift)
        self.assertNotIn('https://chaihome.cc',swift)
    def test_native_project_resources_and_version_are_wired(self):
        project=(ROOT/'ChaiClassics.xcodeproj/project.pbxproj').read_text()
        self.assertIn('PBXVariantGroup',project)
        for language in ['zh-Hant','en']:
            for file in ['Localizable.strings','InfoPlist.strings','Privacy.md','Terms.md','Support.md']:
                self.assertIn(f'App/Resources/{language}.lproj/{file}',project)
        for file in (ROOT/'App').glob('*.swift'):self.assertIn('App/'+file.name,project)
        self.assertIn('MARKETING_VERSION = 0.1.1',project)
        self.assertIn('CHAI_RELEASE_VERSION = 0.1.1',project)
        info=plistlib.loads((ROOT/'App/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleLocalizations'],['zh-Hant','en'])
        self.assertEqual(info['CFBundleIdentifier'],'$(PRODUCT_BUNDLE_IDENTIFIER)')
        ET.parse(ROOT/'ChaiClassics.xcodeproj/xcshareddata/xcschemes/ChaiClassics.xcscheme')
    def test_privacy_manifest_matches_local_preferences_and_no_collection(self):
        manifest=plistlib.loads((ROOT/'App/Resources/PrivacyInfo.xcprivacy').read_bytes())
        self.assertIs(manifest['NSPrivacyTracking'],False)
        self.assertEqual(manifest['NSPrivacyCollectedDataTypes'],[])
        self.assertEqual(manifest['NSPrivacyAccessedAPITypes'],[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['CA92.1']}])
        code='\n'.join(p.read_text() for folder in ['App','Core'] for p in (ROOT/folder).glob('*.swift'))
        for prohibited in ['import AdSupport','import AppTrackingTransparency','import CloudKit','import StoreKit','URLSession.shared','WKWebView']:
            self.assertNotIn(prohibited,code)
    def test_v010_rules_saves_and_puzzles_are_unchanged(self):
        baseline='13961946e203115783ffa68924195240062c0e23'
        paths=['Core/Sudoku.swift','Core/Minesweeper.swift','Core/SlidingPuzzle.swift','Core/SaveStore.swift','Core/Resources/sudoku-v1.json','docs/sudoku-manifest-v1.json']
        for path in paths:
            previous=subprocess.check_output(['git','show',baseline+':'+path],cwd=ROOT)
            self.assertEqual(hashlib.sha256(previous).digest(),hashlib.sha256((ROOT/path).read_bytes()).digest(),path)
        # Signing code/workflows are deliberately outside this App redesign.
        for path in ['fastlane/Fastfile','fastlane/lib/signing_config.rb','fastlane/lib/release_pipeline.rb','.github/workflows/testflight.yml','.github/workflows/initialize-signing.yml']:
            self.assertEqual(subprocess.check_output(['git','show',baseline+':'+path],cwd=ROOT),(ROOT/path).read_bytes(),path)
    def test_test_sandbox_never_resets_production_storage(self):
        source=(ROOT/'App/UITestBootstrap.swift').read_text()
        self.assertTrue(source.startswith('#if DEBUG && targetEnvironment(simulator)'))
        self.assertIn('ChaiClassicsUITests/',source)
        for path in (ROOT/'Tests/ChaiCoreTests/Fixtures').glob('*.json'):
            self.assertEqual(json.loads(path.read_text())['schemaVersion'],1)
        ui=(ROOT/'UITests/ChaiClassicsUITests.swift').read_text()
        for old in ['testSudokuNavigationAndRestoration','testHomeHasExactlyThreeColumns','testMinesFirstRevealAndRestoration','testSlidingCanStartAndRestore']:
            self.assertIn(old,ui)
        self.assertIn('XCTAssertFalse(app.buttons["提示"].exists)',ui)
        self.assertIn('.reveal(i)',(ROOT/'App/MinesView.swift').read_text())
        self.assertNotIn('$0.tap(i)',(ROOT/'App/MinesView.swift').read_text())

if __name__=='__main__':unittest.main()
