"""Case-local XCTest fixes retain the complete original behavioural assertions."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import verify_incremental_ci as source


class NativeJourneyPreservationTests(unittest.TestCase):
    def test_local_journeys_keep_every_original_assertion_and_real_pause_controls(self):
        visual = (ROOT / 'UITests/ChaiClassicsVisualSmokeTests.swift').read_text()
        methods = source.functions(visual)
        def body(name):
            start, end = methods[name]
            return visual[start:end]
        common = source.assertions(body('exerciseSharedSession'))
        for name in ['testMinesweeperCommonSessionLifecycleAndContinueDeletion',
                     'testMemoryCommonSessionLifecycleAndContinueDeletion']:
            self.assertFalse(common - source.assertions(body(name)), name)
            self.assertIn('executionTimeAllowance = 1800', body(name))
        review = source.assertions(body('reviewAndReopenResult'))
        self.assertFalse(review - source.assertions(body('testMinesweeperCommonSessionLifecycleAndContinueDeletion')))
        arcade = (ROOT / 'UITests/ChaiClassicsV030UITests.swift').read_text()
        methods = source.functions(arcade)
        a, b = methods['exercise']; common = source.assertions(arcade[a:b])
        a, b = methods['testSnakeCompleteSessionRestoresAndConfirmsDeletion']; snake = arcade[a:b]
        self.assertFalse(common - source.assertions(snake))
        self.assertLess(snake.index('quickPause.tap()'), snake.index('attach(app,game+(game == "snake"'))
        self.assertIn('app.buttons[game+".session.resume"].waitForExistence', snake)
        self.assertIn('quickPause = app.coordinate', snake)


if __name__ == '__main__':
    unittest.main()
