"""An explicit native timeout is failure evidence, never passed coverage."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import verify_candidate as candidate
import verify_incremental_ci as historical


class XCTestTimeoutEvidenceTests(unittest.TestCase):
    timeout = "Test Case '-[ChaiClassicsUITests.Sessions testHistory]' exceeded execution time allowance of 5 minutes. The test may have hung; check Xcode's test report for additional diagnostics."
    passed = "Test Case '-[ChaiClassicsUITests.Sessions testSavedRound]' passed (329.599 seconds)."

    def test_explicit_timeout_and_completed_other_case_match_original_failed_summary(self):
        actual = candidate.parse_test_log(self.timeout + '\n' + self.passed)
        self.assertEqual(actual, {'Sessions/testHistory': 'failed', 'Sessions/testSavedRound': 'passed'})
        historical.summary_matches({'totalTestCount': 2, 'passedTests': 1, 'failedTests': 1,
                                    'skippedTests': 0, 'result': 'Failed'}, actual)
        with self.assertRaises(candidate.CandidateError):
            candidate.validate_execution(actual, list(actual), phone=False)

    def test_retry_or_duplicate_timeout_cannot_replace_the_original_failure(self):
        for following in [self.timeout, self.timeout.replace('exceeded execution time allowance of 5 minutes.', 'passed (6 seconds).'),
                          self.timeout.replace('exceeded execution time allowance of 5 minutes.', 'failed (6 seconds).')]:
            with self.subTest(following=following), self.assertRaises(candidate.CandidateError):
                candidate.parse_test_log(self.timeout + '\n' + following)

    def test_incomplete_or_generic_timeout_message_is_not_a_native_case_result(self):
        for text in ["Test exceeded execution time allowance of 5 minutes", self.timeout.replace("Test Case '-[", "Warning: Test Case '-["),
                     self.timeout.replace('5 minutes.', 'an unknown duration.'), "Test Case '-[Sessions testHistory]' started."]:
            with self.subTest(text=text), self.assertRaises(candidate.CandidateError):
                candidate.parse_test_log(text)

    def test_summary_cannot_turn_timeout_into_success_or_omit_it(self):
        actual = candidate.parse_test_log(self.timeout + '\n' + self.passed)
        for summary in [{'totalTestCount': 2, 'passedTests': 2, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'},
                        {'totalTestCount': 1, 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'result': 'Passed'}]:
            with self.subTest(summary=summary), self.assertRaises(candidate.CandidateError):
                historical.summary_matches(summary, actual)


if __name__ == '__main__':
    unittest.main()
