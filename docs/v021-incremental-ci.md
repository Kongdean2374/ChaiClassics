# Dependency-scoped CI evidence

CI on `develop/0.2.1` supports full UI runs, a named game scope, and `affected`.
All modes still execute current puzzle/save verification, all Core tests, and a Simulator build.

For a first pass, dispatch full UI or a game scope. For the next repair, set
`ui_scope=affected`, `full_ui=true`, and `baseline_run` to the previous CI run ID.
Multiple earlier IDs may be comma-separated. A previous partial ledger carries its
underlying run IDs forward, so an A/B success followed by a C failure can retain the
real A/B passes while rerunning C and any genuinely shared dependents.

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
Final iPhone Visual Smoke and iPad 4+5 evidence must still use the target SHA. The
signed TestFlight upload job remains unchanged, behind the complete candidate gate.

The historical v0.2.0 schema-2 helper-only proof is preserved as a separate narrow
verification path. It cannot authorize application changes.
