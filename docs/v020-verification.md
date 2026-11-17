# v0.2.0 verification evidence

The candidate is an exact commit, not the latest successful branch run. Ordinary
`main` and `develop/0.2.0` pushes run unsigned CI and never upload to TestFlight.
The three manually dispatchable validation workflows accept trusted `main` or
`develop/0.2.0`. They contain no Apple credentials.

A final-main proof may reuse all three development runs after a fast-forward
puts the identical tested SHA on main. The three runs must use one common
trusted evidence branch, recorded in `evidence_branch`; main's current tip and
the candidate tag must still match that SHA. A merge that creates a new SHA
requires fresh complete verification. A development-mode proof always records
`release_eligible: false`.

| Workflow | Required work | Evidence |
| --- | --- | --- |
| CI, `full_ui=true` | Puzzle/save compatibility, every Swift test, unsigned Simulator build, every declared UI test, Python/Ruby release regressions, real macOS signing-tool regressions without credentials | `test-results`, `candidate-ci-evidence` |
| Visual Smoke | Every existing visual test on iPhone, with original XCTest attachments | `visual-smoke-results`, `candidate-visual-evidence` |
| iPad Screenshots | Four original gallery captures, plus five separate new-game journeys, using the same built bundle and selected native 13-inch iPad | Original screenshot/report artifact, two separate XCTest artifacts, `candidate-ipad-evidence` |

The full iPhone test list is read from the committed `UITests/*.swift` files.
Currently there are 35 declared cases. Exactly the four existing iPad-only
gallery cases must report `skipped` on iPhone; all other cases must report
`passed`. The four gallery cases and five new-game journeys must all pass on
iPad, in independent result bundles. No new-game journey may be skipped.

`scripts/verify_candidate.py capture` compares both the actual xcresult summary
and actual XCTest completion lines with the required class/method set. Missing,
duplicate, failed, substituted, or unexpectedly skipped methods fail the job.
The bounded evidence artifact contains each actual method and its status; counts
alone cannot establish completion. The full text log and xcresult remain
available for review. The original iPad collector still requires exactly four
unmodified native PNGs with matching XCTest attachment provenance.

| Artifact path | Purpose |
| --- | --- |
| `build/UITests.xcresult`, `build/UITests-summary.json`, `build/UITests.log` | Complete iPhone suite |
| `build/VisualSmoke.xcresult`, `build/VisualSmoke-summary.json`, `build/VisualSmoke.log` | Focused iPhone visual suite |
| `build/ipad-screenshots/IPadScreenshots.xcresult`, `test-summary.json`, `tests.log` | Four original iPad captures |
| `build/ipad-screenshots/IPadGames.xcresult`, `games-summary.json`, `games.log` | Five complete new-game iPad journeys |
| `build/ipad-screenshots/report.json` | Original PNG dimensions, hashes, selected device, source SHA and collector verdict |

The phone selector prefers the newest installed Pro Max/Plus because the layout
suite tests actual widths through 430pt inside its real Simulator window. A
too-small window fails the relevant assertion; it does not skip that case.
The complete CI UI phase has no `-only-testing` filter. Individual case timeouts
remain enabled, with a 420-second default and 600-second maximum; the job has a
90-minute limit. Dedicated iPad gallery and game journeys use separate bounded
steps, preserving available artifacts even when another step fails.

Local checks do not establish Simulator execution, signed archive success,
upload receipt, Apple processing, internal availability, or external approval.
Record actual workflow URLs, source SHA, selected devices, actual case totals,
and the resulting candidate proof when those runs finish.
