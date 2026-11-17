"""Only an exact private XCTest toolbar correction leaves unrelated classes unchanged."""
import copy
import hashlib
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import verify_candidate as candidate
import verify_scoped_ci as scoped

class PrivateToolbarScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
        cls.base=scoped.historical.git_tree(sha)
        cls.path='UITests/ChaiClassicsV030UITests.swift'
        # Explicit before/after fixture remains valid after committing the fix.
        current=(ROOT/cls.path).read_text()
        before,after,old_block,new_block=scoped.APPROVED_V030_TOOLBAR_HELPER
        cls.old=current.replace(new_block,old_block,1)
        cls.new=current
        cls.base[cls.path]=('100644',cls.old.encode())
        cls.updated=dict(cls.base);cls.updated[cls.path]=('100644',cls.new.encode())
        cls.previous=scoped.fingerprints(cls.base);cls.target=scoped.fingerprints(cls.updated)

    def scaffold(self,source):
        for name,(start,end) in sorted(scoped.historical.functions(source).items(),key=lambda x:x[1][0],reverse=True):
            if name.startswith('test'):source=source[:start]+'{TEST_BODY}'+source[end:]
        return source

    def test_only_seventeen_owner_class_cases_change_and_other_fifty_four_keep_actual_provenance(self):
        self.assertEqual(len(self.previous),71)
        changed={n for n in self.previous if self.previous[n]!=self.target[n]}
        owners={n for n in self.previous if n.startswith('ChaiClassicsV030UITests/')}
        self.assertEqual(len(owners),17);self.assertEqual(changed,owners)
        self.assertEqual(len(self.previous)-len(changed),54)
        old,new,*_=scoped.APPROVED_V030_TOOLBAR_HELPER
        self.assertEqual(hashlib.sha256(self.scaffold(self.old).encode()).hexdigest(),old)
        self.assertEqual(hashlib.sha256(self.scaffold(self.new).encode()).hexdigest(),new)
        self.assertIn('final class ChaiClassicsV030UITests: XCTestCase',self.new)
        self.assertIn('private func reach(',self.new)

    def test_unknown_helper_setup_constant_global_hook_or_mode_invalidates_every_case(self):
        variants=[self.new+'\nextension XCTestCase { func unrelatedGlobalHook() {} }\n',
                  self.new.replace('0..<18','0..<19',1),
                  self.new.replace('executionTimeAllowance = 600','executionTimeAllowance = 900',1),
                  self.new.replace('private let boardGames','private let changedBoardGames',1)]
        for data in variants:
            target=dict(self.updated);target[self.path]=('100644',data.encode())
            fp=scoped.fingerprints(target)
            self.assertTrue(all(self.previous[n]!=fp[n] for n in self.previous))
        target=dict(self.updated);target[self.path]=('100755',self.new.encode())
        fp=scoped.fingerprints(target);self.assertTrue(all(self.previous[n]!=fp[n] for n in self.previous))

    def test_wrong_path_and_allowlist_extension_alone_cannot_bypass_normalized_baseline(self):
        scaffold=self.scaffold(self.new)
        raw=hashlib.sha256(scaffold.encode()).hexdigest()
        self.assertEqual(scoped.external_scaffold_digest('UITests/Other.swift','100644',scaffold),raw)
        changed=scaffold+'\n// unreviewed outside change\n';raw=hashlib.sha256(changed.encode()).hexdigest()
        before,after,old,new=scoped.APPROVED_V030_TOOLBAR_HELPER
        with mock.patch.object(scoped,'APPROVED_V030_TOOLBAR_HELPER',(before,raw,old,new)):
            self.assertEqual(scoped.external_scaffold_digest(self.path,'100644',changed),raw)

    def test_an_owner_test_body_change_is_never_erased_by_private_helper_projection(self):
        source=self.new;start,end=scoped.historical.functions(source)['testNonogramCompleteSessionRestoresAndConfirmsDeletion']
        changed=dict(self.updated);changed[self.path]=('100644',(source[:start+1]+'\nXCTAssertTrue(false)\n'+source[start+1:]).encode())
        fp=scoped.fingerprints(changed)
        self.assertEqual({n for n in fp if fp[n]!=self.target[n]},
                         {'ChaiClassicsV030UITests/testNonogramCompleteSessionRestoresAndConfirmsDeletion'})

    def test_core_app_and_other_test_helpers_keep_their_full_existing_dependencies(self):
        for path in ['Core/SaveStore.swift','App/GameSessionComponents.swift','UITests/ChaiClassicsVisualSmokeTests.swift']:
            changed=dict(self.updated);mode,data=changed[path];changed[path]=(mode,data+b'\n// shared change\n')
            fp=scoped.fingerprints(changed)
            self.assertTrue(all(self.target[n]!=fp[n] for n in self.target))
        for status in ['failed','skipped',None]:
            self.assertFalse(scoped.covered('ChaiClassicsV030UITests/testShogiCompleteSessionRestoresAndConfirmsDeletion',{'status':status}))

if __name__=='__main__':unittest.main()
