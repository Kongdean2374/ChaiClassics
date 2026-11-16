import contextlib
import io
import os
import pathlib
import subprocess
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts'))
import check_release_secrets as checks
import run_signing_lane as runner

class SigningPreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ephemeral fixture, never printed or written into the repository.
        cls.pem = subprocess.check_output(['openssl','genpkey','-algorithm','EC','-pkeyopt','ec_paramgen_curve:P-256'], stderr=subprocess.DEVNULL).decode()

    def env(self):
        return dict(ASC_KEY_ID='A123456789', ASC_ISSUER_ID='01234567-0123-4567-89ab-0123456789ab', ASC_API_KEY_P8=self.pem,
                    APPLE_TEAM_ID='T123456789', SIGNING_REPO_PAT='fixture-token-not-a-real-pat', MATCH_PASSWORD='fixture-pass-not-real')

    def test_original_p8_and_crlf_accepted_without_base64_or_p12(self):
        env = self.env(); checks.validate_environment(env, signing=True)
        env['ASC_API_KEY_P8'] = self.pem.replace('\n','\r\n')
        checks.validate_environment(env, signing=True)

    def test_missing_team_and_rejected_key_formats_do_not_leak(self):
        env = self.env(); del env['APPLE_TEAM_ID']
        with self.assertRaisesRegex(checks.ConfigurationError, 'APPLE_TEAM_ID'): checks.validate_environment(env, signing=True)
        for key in ['base64-private-key', self.pem.replace('\n',r'\n'), '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----']:
            env=self.env(); env['ASC_API_KEY_P8']=key
            with self.assertRaises(checks.ConfigurationError) as error: checks.validate_environment(env)
            self.assertNotIn(key, str(error.exception))

    def test_trusted_manual_main_only(self):
        checks.validate_trusted_dispatch(dict(GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REF='refs/heads/main'))
        for event,ref in [('push','refs/heads/main'),('pull_request','refs/heads/main'),('workflow_dispatch','refs/heads/feature')]:
            with self.assertRaises(checks.ConfigurationError): checks.validate_trusted_dispatch(dict(GITHUB_EVENT_NAME=event, GITHUB_REF=ref))

    def test_private_repository_and_readonly_vs_initialization_permissions(self):
        repo=dict(full_name=checks.REPO, private=True, default_branch='main', permissions=dict(pull=True,push=False))
        def request(path, token):
            self.assertEqual(token,'fixture')
            return dict(ref='refs/heads/main') if '/git/ref/' in path else repo
        checks.validate_signing_repo('fixture', initialize=False, request=request)
        with self.assertRaises(checks.ConfigurationError): checks.validate_signing_repo('fixture',initialize=True,request=request)
        repo['permissions']['push']=True
        checks.validate_signing_repo('fixture',initialize=True,request=request)
        repo['private']=False
        with self.assertRaises(checks.ConfigurationError): checks.validate_signing_repo('fixture',request=request)

    def test_subprocess_output_suppressed_and_failure_is_not_ignored(self):
        for raw,expected in [(b'fixture-private-key\n[CHAI_SIGNING:APPLE_TEAM]', 'APPLE_TEAM'),
                             (b'Authentication failed fixture-token','MATCH_GIT'),(b'bad decrypt fixture-password','MATCH_DECRYPT')]:
            self.assertEqual(runner.diagnostic(raw,'initialize_signing'),expected)
        secret='this-must-never-appear-in-public-log'
        def fake_run(*args,**kwargs):
            kwargs['stdout'].write(secret.encode()+b'\n[CHAI_SIGNING:APPLE_ACCESS]')
            return subprocess.CompletedProcess(args[0],1)
        output=io.StringIO()
        with patch.object(runner,'preflight',return_value=0), patch.object(runner.subprocess,'run',side_effect=fake_run), contextlib.redirect_stdout(output):
            self.assertEqual(runner.main(['initialize_signing']),1)
        self.assertIn('APPLE_ACCESS',output.getvalue()); self.assertNotIn(secret,output.getvalue())

if __name__=='__main__': unittest.main()
