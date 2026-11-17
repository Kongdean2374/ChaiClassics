import hashlib
import json
import pathlib
import plistlib
import re
import unittest
from urllib.parse import urlsplit
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
        format_pattern=r'%(?:\d+\$)?[-+0# ]*\d*(?:\.\d+)?[df@]'
        for key in zh:
            self.assertTrue(zh[key]);self.assertTrue(en[key])
            self.assertEqual(re.findall(format_pattern,zh[key]),re.findall(format_pattern,en[key]),key)
        for path in (ROOT/'App').glob('*.swift'):
            for key in re.findall(r'\bt\("([a-zA-Z][\w.]+)"',path.read_text()):
                if key.endswith('.'):continue
                self.assertIn(key,zh,str(path))
        for prefix,values in [('game',['sudoku','minesweeper','sliding']),('status',['notStarted','inProgress','completed','failed']),('difficulty',['easy','medium','hard','normal','custom']),('theme',['system','light','dark'])]:
            for value in values:self.assertIn(prefix+'.'+value,zh)
    def test_offline_documents_match_published_website_and_contact(self):
        for language in ['zh-Hant','en']:
            for name in ['Privacy','Terms','Support']:
                text=(ROOT/'App/Resources'/f'{language}.lproj/{name}.md').read_text()
                self.assertGreater(len(text),400);self.assertIn('0.2.1',text)
                self.assertIn('a090825159@icloud.com',text)
                expected_path=('/en' if language=='en' else '')+'/'+name.lower()
                routes={(urlsplit(url).scheme,urlsplit(url).netloc,urlsplit(url).path.rstrip('/'))
                        for url in re.findall(r'https://[A-Za-z0-9./_-]+',text)}
                self.assertIn(('https','classics.chaihome.cc',expected_path),routes)
                self.assertNotIn('https://chaihome.cc',text)
                for obsolete in ['籌備','尚未提供聯絡 email','in preparation','is being prepared','has not yet been built','no contact email']:
                    self.assertNotIn(obsolete,text.lower())
    def test_official_links_and_contact_are_wired_without_embedded_browser(self):
        config=(ROOT/'Core/OfficialWebsite.swift').read_text()
        self.assertIn('"https"',config)
        self.assertIn('"classics.chaihome.cc"',config)
        self.assertIn('a090825159@icloud.com',config)
        self.assertIn('URLComponents',config)
        self.assertIn('mailto',config)
        legal=(ROOT/'App/LegalView.swift').read_text()
        settings=(ROOT/'App/SettingsView.swift').read_text()
        for source in [legal,settings]:
            self.assertIn('OfficialWebsite',source)
            self.assertIn('Link(',source)
            self.assertNotIn('https://github.com/Kongdean2374/ChaiClassics/issues',source)
            self.assertNotIn('https://chaihome.cc',source)
        for identifier in ['legal.online.','support.email','support.email.address']:
            self.assertIn('"'+identifier+'"',legal)
        for identifier in ['settings.website','settings.email','settings.appearance','settings.language','settings.haptics','settings.awake']:
            self.assertIn('"'+identifier+'"',settings)
        contact=(ROOT/'App/SupportLinks.swift').read_text()
        self.assertIn('OfficialWebsite.emailURL(',contact)
        self.assertIn('Link(destination: destination)',contact)
        for source in [legal,settings]:self.assertIn('SupportEmailLink(identifier:',source)
    def test_native_project_resources_and_version_are_wired(self):
        project=(ROOT/'ChaiClassics.xcodeproj/project.pbxproj').read_text()
        self.assertIn('PBXVariantGroup',project)
        for language in ['zh-Hant','en']:
            for file in ['Localizable.strings','InfoPlist.strings','Privacy.md','Terms.md','Support.md']:
                self.assertIn(f'App/Resources/{language}.lproj/{file}',project)
        for file in (ROOT/'App').glob('*.swift'):self.assertIn('App/'+file.name,project)
        self.assertIn('MARKETING_VERSION = 0.2.2',project)
        self.assertIn('CHAI_RELEASE_VERSION = 0.2.2',project)
        info=plistlib.loads((ROOT/'App/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleLocalizations'],['zh-Hant','en'])
        self.assertEqual(info['CFBundleIdentifier'],'$(PRODUCT_BUNDLE_IDENTIFIER)')
        self.assertIs(info['CADisableMinimumFrameDurationOnPhone'], True)
        ET.parse(ROOT/'ChaiClassics.xcodeproj/xcshareddata/xcschemes/ChaiClassics.xcscheme')
    def test_app_icon_is_native_opaque_1024_square(self):
        import struct
        path=ROOT/'App/Assets.xcassets/AppIcon.appiconset/AppIcon.png'
        data=path.read_bytes()
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        width,height,depth,color=struct.unpack('>IIBB',data[16:26])
        self.assertEqual((width,height),(1024,1024))
        self.assertEqual(depth,8)
        self.assertEqual(color,2, 'App Store icon must be opaque RGB')
    def test_privacy_manifest_matches_local_preferences_and_no_collection(self):
        manifest=plistlib.loads((ROOT/'App/Resources/PrivacyInfo.xcprivacy').read_bytes())
        self.assertIs(manifest['NSPrivacyTracking'],False)
        self.assertEqual(manifest['NSPrivacyCollectedDataTypes'],[])
        # Apple's 35F9.1 covers relative in-app timers. Only elapsed durations,
        # not raw system uptime/boot anchors, belong in user-exported game data.
        self.assertCountEqual(manifest['NSPrivacyAccessedAPITypes'],[
            {'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['CA92.1']},
            {'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategorySystemBootTime','NSPrivacyAccessedAPITypeReasons':['35F9.1']},
        ])
        code='\n'.join(p.read_text() for folder in ['App','Core'] for p in (ROOT/folder).glob('*.swift'))
        self.assertIn('ProcessInfo.processInfo.systemUptime',code)
        for prohibited in ['import AdSupport','import AppTrackingTransparency','import CloudKit','import StoreKit','URLSession.shared','WKWebView']:
            self.assertNotIn(prohibited,code)
    def test_v010_rules_saves_and_puzzles_are_unchanged(self):
        # Frozen SHA-256 values from released commit 13961946e203115783ffa68924195240062c0e23.
        # This also runs in release-tooling's shallow checkout, without fetching Git history.
        # App rules/storage and signing implementation remain frozen.
        # TestFlight scheduling is checked separately from its signing job.
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
            '.github/workflows/initialize-signing.yml': 'c3a4ab2713229f4111d94156db9382e4027c48ae006a4b1b58298fe75a0fb93b',
        }
        for path, expected in released.items():
            actual=(ROOT/path).read_bytes()
            self.assertEqual(hashlib.sha256(actual).hexdigest(),expected,path)
    def test_testflight_preserves_manual_header_and_signing_job(self):
        actual=(ROOT/'.github/workflows/testflight.yml').read_bytes()
        header=actual.split(b'jobs:\n',1)[0]
        self.assertEqual(header.count(b"'Version (e.g. 0.2.2)'"),1)
        self.assertEqual(header.count(b"        default: '0.2.2'\n"),1)
        # v0.2.2's reviewed header adds the user-requested Beta/full policy input.
        # The actual signing/upload job below stays byte-frozen to the released
        # pipeline; normalize only the documented current-version label/default.
        stable_header=header.replace(b"'Version (e.g. 0.2.2)'", b"'Version (e.g. 0.2.1)'")
        stable_header=stable_header.replace(b"        default: '0.2.2'\n", b"        default: '0.2.1'\n")
        self.assertEqual(hashlib.sha256(stable_header).hexdigest(),'2defbc7d5d5a431f189b5d6c029bc881b4ba13a67a8e06471367e49f63dd9a82')
        upload=b'  upload:\n'+actual.split(b'  upload:\n',1)[1]
        self.assertEqual(upload.count(b'    needs: preflight\n'),1)
        self.assertEqual(upload.count(b'    runs-on: macos-15-intel\n'),1)
        upload=upload.replace(b'    needs: preflight\n',b'    needs: ci\n')
        upload=upload.replace(b'    runs-on: macos-15-intel\n',b'    runs-on: macos-15\n')
        # Every other signing/upload byte is unchanged from released 1396194.
        self.assertEqual(hashlib.sha256(upload).hexdigest(),'7f1aeb872b190e583642c74ad3bf08b706aac54c941b25df01ccea4e8b92636e')
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

    def test_easy_puzzles_independently_solve_using_only_single_candidates(self):
        # Separate implementation from the generator's grading code; no guessing,
        # hidden-single scan, or access to a stored solution is permitted here.
        puzzles=json.loads((ROOT/'Core/Resources/sudoku-v1.json').read_text())
        easy=[p for p in puzzles if p['difficulty']=='easy']
        self.assertEqual(len(easy),50)
        for puzzle in easy:
            grid=puzzle['givens'][:]
            while 0 in grid:
                forced=[]
                for i,value in enumerate(grid):
                    if value:continue
                    row,column=divmod(i,9)
                    occupied=set(grid[row*9:row*9+9]) | set(grid[column::9])
                    occupied.update(grid[r*9+c] for r in range(row//3*3,row//3*3+3) for c in range(column//3*3,column//3*3+3))
                    candidates=set(range(1,10))-occupied
                    self.assertTrue(candidates,puzzle['id'])
                    if len(candidates)==1:forced.append((i,next(iter(candidates))))
                self.assertTrue(forced,puzzle['id']+' requires a strategy beyond a single candidate')
                i,digit=forced[0];grid[i]=digit
            for row in range(9):self.assertEqual(set(grid[row*9:row*9+9]),set(range(1,10)))

if __name__=='__main__':unittest.main()
