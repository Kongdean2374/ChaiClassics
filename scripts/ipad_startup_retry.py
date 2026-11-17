#!/usr/bin/env python3
"""Recognize one specific pre-case Xcode AX startup failure, never a failed UI case."""
import argparse
import json
from pathlib import Path
import re

FAILURE = 'The test runner failed to initialize for UI testing. (Underlying Error: Timed out waiting for AX loaded notification)'


def eligible(log, summary):
    if not isinstance(log,str) or not isinstance(summary,dict):
        return False
    # An assertion, timeout or process failure after a case began must remain
    # a real failure, including when its text also mentions accessibility.
    if re.search(r"(?m)^\s*Test Case ['\"]",log):
        return False
    fields = ('totalTestCount','passedTests','failedTests','skippedTests')
    if (any(type(summary.get(key)) is not int for key in fields)
            or [summary[key] for key in fields] != [1,0,1,0]
            or summary.get('result') != 'Failed'):
        return False
    failures = summary.get('testFailures')
    if not isinstance(failures,list) or len(failures)!=1 or not isinstance(failures[0],dict):
        return False
    failure = failures[0]
    identifier = failure.get('testIdentifierString')
    return (failure.get('failureText') == FAILURE
            and failure.get('targetName') == 'ChaiClassicsUITests'
            and isinstance(identifier,str)
            and re.fullmatch(r'ChaiClassicsUITests-Runner \(\d+\) encountered an error',identifier) is not None
            and 'Failed to initialize for UI testing:' in log
            and 'XCTDaemonErrorDomain Code=18' in log
            and 'Timed out waiting for AX loaded notification' in log
            and '** TEST EXECUTE FAILED **' in log)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log',required=True,type=Path)
    parser.add_argument('--summary',required=True,type=Path)
    args = parser.parse_args()
    try:
        allow = eligible(args.log.read_text(),json.loads(args.summary.read_text()))
    except (OSError,ValueError,TypeError):
        allow = False
    print('IPAD_AX_STARTUP_RETRY_ELIGIBLE' if allow else 'IPAD_STARTUP_RETRY_NOT_ALLOWED')
    return 0 if allow else 1


if __name__ == '__main__':
    raise SystemExit(main())
