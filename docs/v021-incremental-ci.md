# Dependency-scoped CI evidence

CI on `develop/0.2.1` supports full UI runs, a named game scope, and `affected`.
All modes still execute current puzzle/save verification, all Core tests, and a Simulator build.

For a first pass, dispatch full UI or a game scope. For the next repair, set
`ui_scope=affected`, `full_ui=true`, and `baseline_run` to the previous CI run ID.
Multiple earlier IDs may be comma-separated. A previous partial ledger carries its
underlying run IDs forward. The pre-execution index is also preserved with raw
results when C fails, so using that failed run ID still finds the real A/B passes while rerunning C and any genuinely shared dependents.

Each case is bound to its exact test body, shared UI helpers, runtime/configuration,
resources, preferences, animation clock and project tooling. Known game files only
invalidate their dependent journeys; unknown or shared changes invalidate broadly.
A test-body edit invalidates that case. A helper edit invalidates every affected test.
Deleted required tests, skipped Core/build steps, non-ancestor commits, untrusted runs,
expired/corrupt raw artifacts and mismatched result summaries cannot supply coverage.
A newer matching failure overrides an older pass.

The ledger records actual current case counts separately from retained per-case
run/SHA/fingerprint provenance. Partial coverage is useful successful CI output;
`complete=false` cannot authorize TestFlight. The candidate verifier reloads the real
GitHub jobs and digest-verified original XCTest log/summary and rebuilds every claim.
Final iPhone Visual Smoke and iPad 4+5 evidence must use the target application and
XCTest bytes. A separate narrow exception retains their original source SHA when
the only intervening changes are the two pure evidence readers, documentation or
tooling tests. The verifier checks ancestry and every other file's exact bytes and
mode, including all App/Core/UI tests/helpers, assets, project, execution scripts,
workflows and signing code. The proof records both original source and target SHA;
an App edit cannot use this exception. With an explicit protected-case list,
unexecuted test-method bodies may differ: every selected case body must remain
identical, and all method identities, signatures, shared helpers, setup, constants
and fixtures remain locked. This lets a repair to a different test retain genuine
successful screenshots. The proof records the protected cases and a separate
runtime/scaffold/test-body digest. The repaired case still needs a real current
CI pass. The signed TestFlight upload job remains unchanged, behind the complete
candidate gate.

Mixed-case dependency profiles are bound to their exact test-body SHA-256. An
edited or unknown body falls back to all games. All Core files remain shared,
because AppModel restores all game types at startup. Game-specific view changes
can preserve unrelated passes; shared helpers, preferences, clocks and resources
still invalidate their dependents. Source ledgers are indexes only: their claimed
passes and fingerprints are always rebuilt from actual raw results and Git trees.

The historical v0.2.0 schema-2 helper-only proof is preserved as a separate narrow
verification path. It cannot authorize application changes.
