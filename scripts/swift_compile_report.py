#!/usr/bin/env python3
"""Emit only public source codes/line numbers and fixed Swift error categories."""
import argparse
from pathlib import Path
import re

SOURCES = {
    'ArcadeControls.swift': 'ARCADE_CONTROLS',
    'ExpandedArcadeView.swift': 'ARCADE_VIEW',
    'ExpandedSolitaireView.swift': 'SOLITAIRE_VIEW',
    'ExpandedPuzzleView.swift': 'PUZZLE_VIEW',
    'SolitaireInput.swift': 'CARD_INPUT',
    'ArcadeInput.swift': 'ARCADE_INPUT',
}
CATEGORIES = (
    ('TYPECHECK_LIMIT', r'unable to type-check|type-check.*reasonable time'),
    ('NO_MEMBER', r'has no member|no exact matches'),
    ('ARGUMENT_ORDER', r'argument.*must precede|argument.*must follow'),
    ('ARGUMENT_LABEL', r'incorrect argument label|extraneous argument label|missing argument label'),
    ('MISSING_ARGUMENT', r'missing argument|extra argument'),
    ('TYPE_MISMATCH', r'cannot convert|cannot assign|cannot infer|ambiguous|conflicting arguments'),
    ('CONFORMANCE', r'does not conform|requires that'),
    ('ACCESS', r'inaccessible|protection level'),
    ('MUTABILITY', r'immutable|mutating member|cannot assign'),
    ('ACTOR_ISOLATION', r'actor-isolated|main actor'),
)

def diagnose(text):
    findings = set()
    for match in re.finditer(r'(?m)^.*?([A-Za-z][A-Za-z0-9]*\.swift):(\d{1,5}):\d{1,5}: error: ([^\r\n]*)', text):
        file, line, message = match.groups()
        if file not in SOURCES or not 1 <= int(line) <= 20000:
            findings.add(('UNKNOWN_SOURCE', 0, 'SWIFT_COMPILE_ERROR'))
            continue
        category = next((code for code, pattern in CATEGORIES if re.search(pattern, message, re.I)), 'SWIFT_COMPILE_ERROR')
        findings.add((SOURCES[file], int(line), category))
    return sorted(findings) or [('UNKNOWN_SOURCE', 0, 'BUILD_FAILED_NO_SAFE_DETAIL')]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    try:
        log = args.log.read_text(errors='replace')
    except OSError:
        print('Swift diagnostic: source=UNKNOWN_SOURCE line=0 code=LOG_UNAVAILABLE')
        return
    for source, line, code in diagnose(log):
        print(f'Swift diagnostic: source={source} line={line} code={code}')

if __name__ == '__main__':
    main()
