import hashlib
import json
import pathlib
import plistlib
import re
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
        # Frozen SHA-256 values from released commit 13961946e203115783ffa68924195240062c0e23.
        # This also runs in release-tooling's shallow checkout, without fetching Git history.
        # Signing code/workflows remain outside this App redesign.
        released={
            'Core/Sudoku.swift': '25c829a99f7e70d5e4a11f1f92329727371bc3d9aa7837a88ee088675e5fc4cb',
            'Core/Minesweeper.swift': '9be7abf2be3c5762fc837148f73cd23049ddefbce5eef5cb490673163a40437d',
            'Core/SlidingPuzzle.swift': 'e0c61ffdb8d9053e99417fa9b00c0d15fd87a9b07ba94b2cb64d63983958c6b5',
            'Core/SaveStore.swift': 'f1644676af3589d4e3bbdafb19b5e95f7154222ec3cda6ced750bf8c548def28',
            'Core/Resources/sudoku-v1.json': '585b1423a7d7e283e074954d21c34171101bf02d26138cf6fc6ba319f64269db',
            'docs/sudoku-manifest-v1.json': '944fb7a709c0420e43c5420b9421da416c0d659d20899489ef8924a48b0065b9',
            'fastlane/Fastfile': 'e1a3d994921f19861b0f2f068b7a1dd392ae5cd1901b4d6fcac9970f28a0bc1a',
            'fastlane/lib/signing_config.rb': '21435e215b7464f4e2ef9a2951a09f12dfebb6fce97beaf061b0e9afde2c40b8',
            'fastlane/lib/release_pipeline.rb': '48657a233ac4227691ac62e2f693aa04e4a196792c5903b404eb456a9950d2a6',
            '.github/workflows/testflight.yml': '410a678adae10d0f9b2149c60adb865d3c564d9e2c7f99d26f617763cb2d93a8',
            '.github/workflows/initialize-signing.yml': 'c3a4ab2713229f4111d94156db9382e4027c48ae006a4b1b58298fe75a0fb93b',
        }
        for path, expected in released.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),expected,path)
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
