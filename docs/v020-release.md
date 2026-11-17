# v0.2.0 candidate and TestFlight handoff

The existing signed upload remains `TestFlight`, explicitly dispatched on
`main`, protected by the `testflight` environment. Its upload job, readonly
match behavior, signing assets, build-number policy and fastlane implementation
are unchanged. No App Store submission, public release, or signing initialization
is part of this release path.

The authorized release operator or Codex performs these steps after development
is complete. The user does not need to click Run workflow for ordinary delivery.

1. Fix one exact candidate SHA and explicitly mark it with `v0.2.0-rc.N`.
   Dispatch CI with `full_ui=true`, Visual Smoke, and iPad Screenshots for that
   SHA on the trusted development branch. Monitor every job and inspect the
   original screenshots. A development proof is useful for review and records
   `release_eligible: false`.
2. Integrate the reviewed candidate into `main` without force pushing. A
   fast-forward preserves the SHA, so all three complete development runs can
   be reused once the current main tip and candidate tag point to that exact
   commit. All three runs must come from the same trusted evidence branch,
   either `main` or `develop/0.2.0`; mixing their branches is rejected. The final
   proof records this as `evidence_branch`. If integration creates a different
   merge SHA, mark that resulting commit with a fresh candidate tag and run all
   three workflows again. Evidence from another SHA can never authorize release.
3. Run the read-only gate with the exact three run IDs:

   ```sh
   python3 scripts/verify_candidate.py verify \
     --repo Kongdean2374/ChaiClassics --sha FULL_MAIN_SHA \
     --version 0.2.0 --tag v0.2.0-rc.N \
     --ci-run CI_RUN_ID --visual-run VISUAL_RUN_ID --ipad-run IPAD_RUN_ID \
     --output build/candidate-proof.json
   ```

   The gate checks the current branch tip, candidate tag target, exact source
   SHA, repository, explicit workflow event, workflow paths, recorded actors,
   every required job, the actually executed full-UI step, and bounded unexpired
   case-level evidence artifacts. It also checks both separate iPad suites and
   the original screenshot collector report. It performs GitHub GET requests
   through existing `gh` authentication and makes no write or Apple request.
4. Only a successful final-main proof permits Codex to dispatch the existing
   `testflight.yml` with `version=0.2.0`, `candidate_tag`, `ci_run`, `visual_run`,
   and `ipad_run`. Its credential-free preflight repeats the gate against that
   dispatch's immutable `GITHUB_SHA`, using an automatic token with only
   Contents/Actions read permission. Missing or failed proof stops the signing
   job. The proof is retained as `candidate-release-proof`.
5. Monitor the signed upload and read `testflight-provenance` for the exact
   marketing version, unique build number and commit. Upload success establishes
   transfer only: fastlane uses `skip_waiting_for_build_processing: true`.
6. Dispatch `testflight-status.yml` on main with the exact provenance tuple.
   This independent, protected read-only job uses the existing Developer ASC
   key in memory. It requests only the exact app/build, prerelease version,
   beta states, review state, and build notes. It never receives match secrets,
   creates an Apple resource, changes distribution, or uploads a build.

| Report field | Evidence required |
| --- | --- |
| `upload_received` | Apple lists the exact build number for the exact app |
| `processing_complete` | Apple reports `processingState=VALID` for the exact marketing version |
| `internal_ready` | Processed, not expired, and Apple reports a ready/in-testing internal state |
| `source_commit_verified` | Uploaded beta notes contain the exact source SHA recorded in provenance |
| `external_review_state` | Explicit Apple beta-review state, otherwise `UNKNOWN` |

The status artifact is `testflight-apple-status`, containing only allowlisted
states and the public version/build/commit tuple. Exit 0 means internal readiness
and source verification were both established; exit 2 means the successful read
still finds a pending/unready build; exit 1 means the read or validation failed.
Repeat a later read when Apple is still processing. Internal readiness never
establishes external Beta approval. Report upload, processing, internal
availability and external review as four separate facts.

If Actions dispatch permission, a required environment approval, runner
availability, signing, or Apple access blocks progress, retain the run URL and
state the exact blocked step. Do not bypass failed checks, replace the existing
readonly signing path, or claim that a pending Apple build is ready.
