require 'yaml'
require 'open3'
require 'tmpdir'
require 'fileutils'

root = File.expand_path('..', __dir__)
def check(condition, message)
  raise "Workflow configuration assertion failed: #{message}" unless condition
end
workflows = Dir.glob(File.join(root, '.github/workflows/*.yml')).to_h do |path|
  [File.basename(path), YAML.safe_load_file(path, aliases: false)]
end
bootstrap = workflows.fetch('initialize-signing.yml')
flight = workflows.fetch('testflight.yml')
store = workflows.fetch('appstore.yml')
# Psych implements YAML 1.1, where unquoted on is a boolean; GitHub uses on.
triggers = bootstrap['on'] || bootstrap[true]
check(triggers.keys == ['workflow_dispatch'], 'bootstrap must remain manual only')
job = bootstrap.fetch('jobs').fetch('initialize')
check(job['environment'] == 'signing-bootstrap', 'bootstrap must use the dedicated Admin environment')
expected = {
  'ASC_KEY_ID' => '${{ secrets.SIGNING_ASC_KEY_ID }}',
  'ASC_ISSUER_ID' => '${{ secrets.SIGNING_ASC_ISSUER_ID }}',
  'ASC_API_KEY_P8' => '${{ secrets.SIGNING_ASC_API_KEY_P8 }}'
}
expected.each { |name, value| check(job.fetch('env')[name] == value, "Admin mapping for #{name}") }
%w[MATCH_PASSWORD SIGNING_REPO_PAT].each do |name|
  check(job.fetch('env')[name] == '${{ secrets.' + name + ' }}', "preserve common #{name}")
end
check(job.fetch('env')['APPLE_TEAM_ID'] == '${{ inputs.apple_team_id || vars.APPLE_TEAM_ID || secrets.APPLE_TEAM_ID }}', 'preserve Team ID input/Variable/Secret')
bootstrap.fetch('jobs').each_value do |entry|
  check(entry.fetch('if').include?("github.ref == 'refs/heads/main'") && entry.fetch('if').include?("github.event_name == 'workflow_dispatch'"), 'main-only manual job guard')
end
%w[ASC_KEY_ID ASC_ISSUER_ID ASC_API_KEY_P8].each do |name|
  check(flight.dig('jobs', 'upload', 'env', name) == '${{ secrets.' + name + ' }}', "TestFlight keeps Developer #{name}")
  check(store.dig('jobs', 'prepare', 'env', name) == '${{ secrets.' + name + ' }}', "App Store keeps Developer #{name}")
end
%w[testflight.yml appstore.yml ci.yml].each do |file|
  check(!File.read(File.join(root, '.github/workflows', file)).include?('SIGNING_ASC_'), 'Admin key must not be referenced outside bootstrap')
end
check(!bootstrap.fetch('jobs').fetch('ci').key?('secrets'), 'Admin keys must not be passed to reusable CI')
check(job.fetch('steps').any? { |step| step['run'] == 'python3 scripts/run_signing_lane.py initialize_signing' }, 'retain credential-safe log wrapper')
check(job.fetch('steps').all? { |step| !step.fetch('run', '').match?(/\$\{\{\s*secrets\./) }, 'never interpolate secrets directly into shell')
puts "PASS: #{workflows.length} workflow YAML files parsed; bootstrap Admin mapping, Developer-key isolation, shared secrets, manual main guards and safe runner verified."

fastfile = File.read(File.join(root, 'fastlane/Fastfile'))
bootstrap_lane = fastfile.split('lane :initialize_signing do', 2).last.split('lane :beta do', 2).first
beta_lane = fastfile.split('lane :beta do', 2).last.split('lane :prepare_store do', 2).first
check(bootstrap_lane.include?('verify_apple_access!'), 'Admin bootstrap must verify Apple management permissions')
check(!beta_lane.include?('verify_apple_access!'), 'Developer readonly upload must not require Apple certificate/profile management permissions')
check(beta_lane.include?('with_match_signing(key, readonly: true)'), 'Developer upload must remain match readonly')
puts 'PASS: Admin-only portal permission probe; Developer readonly TestFlight does not require management permissions.'

diagnostic = workflows.fetch('diagnose-signing.yml')
diagnostic_job = diagnostic.fetch('jobs').fetch('diagnose')
check((diagnostic['on'] || diagnostic[true]).keys == ['workflow_dispatch'], 'read-only diagnosis is manual only')
check(diagnostic_job['environment'] == 'signing-bootstrap', 'read-only diagnosis uses the Admin environment')
check(diagnostic_job['if'].include?("github.ref == 'refs/heads/main'"), 'read-only diagnosis only main')
check(!diagnostic_job.fetch('env').key?('MATCH_PASSWORD') && !diagnostic_job.fetch('env').key?('SIGNING_REPO_PAT'), 'read-only diagnosis receives no match credentials')
check(diagnostic_job.fetch('steps').any? { |step| step['run'] == 'python3 scripts/run_signing_lane.py diagnose_signing' }, 'read-only diagnostic uses safe wrapper')
diagnostic_lane = fastfile.split('lane :diagnose_signing do', 2).last.split('lane :initialize_signing do', 2).first
check(diagnostic_lane.include?('compare_authentication!') && !diagnostic_lane.include?('with_match_signing') && !diagnostic_lane.match?(/\bmatch\(/), 'diagnostic lane compares authentication and never invokes match')
check(diagnostic_lane.scan('Spaceship::ConnectAPI.token.text').length == 1, 'diagnostic takes one JWT snapshot')
check(diagnostic_lane.include?('key_id: ENV.fetch("ASC_KEY_ID")') && diagnostic_lane.include?('issuer_id: ENV.fetch("ASC_ISSUER_ID")'), 'JWT audit matches configured Admin team key')
puts 'PASS: independent manual read-only diagnosis; no signing assets or match credentials.'

expected.each { |name, value| check(diagnostic_job.fetch('env')[name] == value, "diagnostic keeps the same Admin #{name}") }
puts 'PASS: apps/certificates comparison uses the existing Admin Team key mapping.'

assets = workflows.fetch('verify-signing-assets.yml')
asset_job = assets.fetch('jobs').fetch('verify')
check((assets['on'] || assets[true]).keys == ['workflow_dispatch'], 'asset verification is manual only')
check(asset_job['if'].include?("github.ref == 'refs/heads/main'") && asset_job['if'].include?("github.event_name == 'workflow_dispatch'"), 'asset verification main/manual only')
check(asset_job.fetch('env').keys.sort == %w[APPLE_TEAM_ID MATCH_PASSWORD SIGNING_REPO_PAT].sort, 'no ASC key supplied to readonly asset validation')
check(asset_job.fetch('steps').any? { |step| step['run'] == 'python3 scripts/run_signing_lane.py verify_signing_assets' }, 'safe readonly validation wrapper')
asset_lane = fastfile.split('lane :verify_signing_assets do', 2).last.split('lane :beta do', 2).first
check(asset_lane.include?('with_match_signing(nil, readonly: true)') && !asset_lane.include?('api_key') && !asset_lane.include?('upload_to_testflight'), 'no portal or upload in asset validation lane')
check(!fastfile.include?('readonly: false'), 'all post-bootstrap lanes are readonly')
puts 'PASS: existing-asset-only manual verification; no ASC key, certificate creation or upload.'

extraction_job = workflows.fetch('ci.yml').fetch('jobs').fetch('codesign-extraction')
test_job = workflows.fetch('ci.yml').fetch('jobs').fetch('test')
check(test_job['runs-on'] == 'macos-15', 'unsigned Simulator CI uses the standard ARM pool, without paid larger-runner labels')
intel_jobs = [extraction_job, flight.fetch('jobs').fetch('upload')]
intel_jobs.each do |entry|
  check(entry['runs-on'] == 'macos-15-intel', 'real codesign regression and signed TestFlight retain the explicit standard Intel pool')
end
([test_job] + intel_jobs).each do |entry|
  check(entry.fetch('steps').any? { |step| step['run'] == 'bash scripts/select_xcode.sh' }, 'every macOS job explicitly selects installed Xcode 26+')
end
puts 'PASS: unsigned Simulator CI uses standard ARM; real codesign regression and signed TestFlight retain Intel; all select Xcode 26+.'
phase_runs = test_job.fetch('steps').map { |step| step.fetch('run', '') }.select { |run| run.start_with?('bash scripts/ci.sh') }
check(phase_runs == %w[verify unit build ui ui].map { |phase| 'bash scripts/ci.sh ' + phase }, 'full phases remain ordered and a separate selected UI step is available')
ci_workflow = workflows.fetch('ci.yml')
ci_triggers = ci_workflow['on'] || ci_workflow[true]
check(ci_triggers.dig('workflow_dispatch','inputs','full_ui','type') == 'boolean' && ci_triggers.dig('workflow_dispatch','inputs','full_ui','default') == true, 'full UI remains available through explicit manual CI')
check(ci_triggers.dig('workflow_call','inputs','full_ui','default') == false, 'reusable CI defaults to quick checks')
ui_steps = test_job.fetch('steps').select { |step| step['run'] == 'bash scripts/ci.sh ui' }
check(ui_steps.length == 2 && ui_steps.map { |step| step['if'] } == ["inputs.full_ui == true && env.CHAI_UI_SCOPE == 'full'", "inputs.full_ui == true && env.CHAI_UI_SCOPE != 'full'"], 'full and targeted UI are explicit mutually exclusive modes')
test_job.fetch('steps').select { |step| %w[verify unit build].any? { |phase| step['run'] == 'bash scripts/ci.sh ' + phase } }.each do |step|
  check(!step.key?('if'), 'every App scope actually reruns current verification, Core tests and Simulator build')
end
check(test_job.dig('env', 'CHAI_UI_SCOPE') == "${{ inputs.ui_scope || 'full' }}", 'ordinary push, PR and release CI default to full checks')
check(ci_workflow['permissions'] == {'contents' => 'read', 'actions' => 'read'}, 'baseline reads receive only read permission')
scope_inputs = ci_triggers.dig('workflow_dispatch', 'inputs', 'ui_scope')
check(scope_inputs['type'] == 'choice' && scope_inputs['default'] == 'full' && scope_inputs['options'].include?('memory') && scope_inputs['options'].include?('sliding'), 'manual CI exposes explicit game selections')
check(%w[part_a part_b part_c part_d].all? { |scope| scope_inputs['options'].include?(scope) }, 'manual CI exposes all four disjoint source partitions')
check(scope_inputs['options'].include?('beta'), 'manual CI exposes the explicit three-journey Beta scope')
check(ci_workflow['run-name'].include?('inputs.ui_scope') && test_job['name'].nil?, 'CI run title identifies scope without changing verification job identities')
check(test_job['timeout-minutes'] == 90, 'unsigned ARM CI has a bounded total runtime')
ci_script = File.read(File.join(root, 'scripts/ci.sh'))
check(ci_script.include?('-test-timeouts-enabled YES') && ci_script.include?('-default-test-execution-time-allowance 420') && ci_script.include?('-maximum-test-execution-time-allowance 600'), 'complete UI allowance stays enabled and bounded on ARM or Intel')
_, _, invalid_phase = Open3.capture3('bash', File.join(root, 'scripts/ci.sh'), 'unknown-phase')
check(invalid_phase.exitstatus == 64, 'unknown CI phase must fail instead of silently skipping verification')
puts 'PASS: visible ordered CI phases, bounded UI/total runtimes and rejected unknown phase; all tests retained.'
check(flight.fetch('jobs').keys.sort == %w[preflight upload], 'TestFlight has only fast preflight and real signed upload')
preflight = flight.fetch('jobs').fetch('preflight')
check(preflight['runs-on'] == 'ubuntu-24.04' && !preflight.key?('env') && !preflight.key?('environment') && !preflight.key?('secrets'), 'preflight runs without Apple/signing credentials')
candidate_steps = preflight['steps'].reject { |step| ['Verify exact-SHA TestFlight candidate', 'Preserve verified release candidate proof'].include?(step['name']) }
check(candidate_steps.first.dig('with', 'fetch-depth') == 0, 'release proof can independently compare complete git trees')
normalized_steps = candidate_steps.map do |step|
  copy = Marshal.load(Marshal.dump(step))
  copy['with'].delete('fetch-depth') if copy.fetch('uses', '').start_with?('actions/checkout@')
  copy
end
check(normalized_steps == ci_workflow.fetch('jobs').fetch('release-tooling').fetch('steps'), 'TestFlight retains all fast release-tooling security checks')
check(flight.dig('jobs','upload','needs') == 'preflight', 'real signed archive/upload follows successful quick preflight')
flight.fetch('jobs').each_value do |entry|
  check(entry.fetch('if').include?("github.ref == 'refs/heads/main'") && entry.fetch('if').include?("github.event_name == 'workflow_dispatch'"), 'both release jobs remain trusted main/manual only')
end
check((flight['on'] || flight[true]).dig('workflow_dispatch','inputs','version','default') == '0.2.2', 'manual upload defaults to the current app version')
puts 'PASS: fast credential-free preflight, trusted manual/main upload, current version default and opt-in full UI.'
check(!extraction_job.key?('environment') && !extraction_job.key?('env'), 'extraction regression receives no signing environment or secrets')
extraction_runs = extraction_job.fetch('steps').map { |step| step.fetch('run', '') }.join("\n")
check(extraction_runs.include?('bundle exec ruby tests/codesign_extraction_macos_test.rb') && !extraction_runs.include?('secrets.') && !extraction_runs.include?('run_signing_lane'), 'real codesign extraction CI runs without match or Apple operations')
puts 'PASS: credential-free real macOS extraction regression is required by CI.'

check(extraction_runs.include?('bundle exec ruby tests/gym_xcode_macos_test.rb'), 'real Xcode/Gym export configuration regression is required')
tooling_runs = workflows.fetch('ci.yml').fetch('jobs').fetch('release-tooling').fetch('steps').map { |step| step.fetch('run','') }.join("\n")
check(tooling_runs.include?('bundle exec ruby tests/release_pipeline_test.rb'), 'locked build_app validator regression is required')
check(tooling_runs.include?('bundle exec ruby tests/archive_session_test.rb'), 'archive build/postcheck/sandbox regression is required')
check(beta_lane.include?("release.run('ARCHIVE')") && beta_lane.include?("release.run('EXPORT_IPA')") && beta_lane.include?("release.run('UPLOAD_TRANSFER')"), 'archive/export/transfer have independent stages')
check(beta_lane.include?('ChaiRelease.validate_options!') && beta_lane.include?('ChaiArchive::Session.new.run!'), 'validate production options and preserve exact archive asset pairing')
check(!beta_lane.include?('export_method: "app-store-connect"'), 'old unsupported Gym enum removed from beta')
check((flight['on'] || flight[true]).keys == ['workflow_dispatch'], 'TestFlight remains manually dispatched')
puts 'PASS: pinned build_app and Xcode regressions, independent release phases, exact archive pairing and manual TestFlight preserved.'

signed = workflows.fetch('diagnose-signed-archive.yml')
signed_job = signed.fetch('jobs').fetch('archive')
check((signed['on'] || signed[true]).keys == ['workflow_dispatch'] && signed_job.fetch('if').include?("github.ref == 'refs/heads/main'") && signed_job.fetch('if').include?("github.event_name == 'workflow_dispatch'"), 'signed archive diagnosis main/manual only')
check(signed.fetch('jobs').keys == ['archive'] && !signed_job.key?('needs'), 'independent signed diagnosis does not rerun full TestFlight CI')
check(signed_job.fetch('env').keys.sort == %w[APPLE_TEAM_ID MATCH_PASSWORD RELEASE_VERSION SIGNING_REPO_PAT].sort, 'no ASC API credentials supplied to signed archive diagnosis')
check(signed_job.fetch('steps').any? { |step| step['run'] == 'python3 scripts/run_signing_lane.py diagnose_signed_archive' }, 'signed diagnosis uses the private safe wrapper')
check(signed_job.fetch('steps').none? { |step| step.fetch('uses','').include?('upload-artifact') }, 'no signed archive/raw log artifact')
signed_lane = fastfile.split('lane :diagnose_signed_archive do',2).last.split('lane :beta do',2).first
check(signed_lane.include?('with_match_signing(nil, readonly: true)') && signed_lane.include?('ChaiArchive::Session.new.run!'), 'real signed archive reuses the production archive session')
check(!signed_lane.match?(/upload_to_testflight|export_options\(|api_key|next_apple_build|skip_codesigning/), 'no export, upload, Apple API or unsigned fallback in diagnostic lane')
puts 'PASS: independent main/manual real signed archive diagnosis; readonly assets, no API key, export, upload, artifacts or unsigned fallback.'

visual = workflows.fetch('visual-smoke.yml')
visual_job = visual.fetch('jobs').fetch('visual-smoke')
check((visual['on'] || visual[true]).keys == ['workflow_dispatch'], 'visual smoke is manual only')
check(visual_job.fetch('if').include?("github.ref == 'refs/heads/main'") && visual_job.fetch('if').include?("github.event_name == 'workflow_dispatch'"), 'visual smoke only trusted manual branches')
check(visual.fetch('permissions') == {'contents' => 'read'}, 'visual smoke has read-only repository permission')
check(!visual_job.key?('environment') && !visual_job.key?('env') && !visual_job.key?('secrets'), 'visual smoke receives no release environment or credentials')
visual_source = File.read(File.join(root, '.github/workflows/visual-smoke.yml'))
check(!visual_source.include?('secrets.') && !visual_source.include?('run_signing_lane') && !visual_source.include?('fastlane'), 'visual smoke cannot sign or upload an Apple build')
visual_script = File.read(File.join(root, 'scripts/visual_smoke.sh'))
check(visual_script.include?('-only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests') && visual_script.include?('CODE_SIGNING_ALLOWED=NO'), 'visual smoke selects focused Simulator tests without signing')
visual_selections = visual_script.scan(/-only-testing:(\S+)/).flatten
check(visual_selections == %w[testFreshWinCelebratesOnceAndRestoredWinDoesNotReplay testReducedMotionSuppressesCelebrationButStillCompletesGame testLowPowerSuppressesCelebrationButStillCompletesGame testScreenshotGallery].map { |name| 'ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/' + name }, 'Visual executes exactly the four original phone captures; session journeys stay mandatory in CI')
check(visual_script.include?('# CHAI_VISUAL_FOCUS_V1: original-phone-four; all-session-journeys-required-in-ci'), 'Visual focus contract is explicit in the tested source')
check(visual_job.fetch('steps').any? { |step| step['run'] == 'bash scripts/visual_smoke.sh build' } && visual_job.fetch('steps').any? { |step| step['run'] == 'bash scripts/visual_smoke.sh test' }, 'visual build and execution are independently visible')
check(visual_script.include?('build-for-testing') && visual_script.include?('test-without-building') && visual_script.include?('simctl bootstatus'), 'visual tests reuse one build after explicit Simulator startup')
check(visual_job['timeout-minutes'] == 55 && visual_script.include?('-default-test-execution-time-allowance 300') && visual_script.include?('-maximum-test-execution-time-allowance 360'), 'measured 207s Intel case has bounded time for assertions and result finalization')
puts 'PASS: focused visual smoke remains manual, unsigned, credential-free and separate from routine CI and release.'

ipad = workflows.fetch('ipad-screenshots.yml')
ipad_job = ipad.fetch('jobs').fetch('ipad-screenshots')
ipad_triggers = ipad['on'] || ipad[true]
check(ipad['name'] == 'iPad Screenshots' && ipad_triggers.keys == ['workflow_dispatch'], 'iPad screenshots have an independent manual entry point')
check(ipad_job.fetch('if').include?("github.ref == 'refs/heads/main'") && ipad_job.fetch('if').include?("github.event_name == 'workflow_dispatch'"), 'iPad screenshots only trusted manual branches')
check(ipad.fetch('permissions') == {'contents' => 'read'} && !ipad_job.key?('environment') && !ipad_job.key?('secrets'), 'iPad screenshots use no signing environment or repository write permission')
check(ipad_triggers.dig('workflow_dispatch', 'inputs', 'runner', 'options') == %w[macos-15 macos-15-intel], 'iPad runner choices contain only standard hosted pools')
check(ipad_triggers.dig('workflow_dispatch', 'inputs', 'runner', 'default') == 'macos-15', 'iPad screenshots default to the measured faster standard ARM pool')
check(ipad_job['runs-on'] == "${{ inputs.runner == 'macos-15' && 'macos-15' || 'macos-15-intel' }}", 'arbitrary runner inputs cannot select paid labels')
ipad_source = File.read(File.join(root, '.github/workflows/ipad-screenshots.yml'))
check(!ipad_source.match?(/secrets\.|run_signing_lane|fastlane|upload_to_testflight|MATCH_PASSWORD|ASC_API_KEY/), 'iPad screenshots cannot access signing credentials or publish an app')
ipad_steps = ipad_job.fetch('steps')
boot_step = ipad_steps.find { |step| step['id'] == 'boot' }
test_step = ipad_steps.find { |step| step['id'] == 'ui' }
check(boot_step && boot_step['run'] == 'bash scripts/ipad_screenshots.sh boot' && boot_step['timeout-minutes'] == 10, 'cold iPad startup has its own bounded step')
check(test_step && test_step['run'] == 'bash scripts/ipad_screenshots.sh test' && test_step['timeout-minutes'] == 25, 'XCTest keeps a separate timeout for execution and xcresult finalization')
check(ipad_steps.index(boot_step) < ipad_steps.index(test_step), 'the selected iPad boots before XCTest starts')
checkout = ipad_steps.find { |step| step.fetch('uses', '').start_with?('actions/checkout@') }
check(checkout.dig('with', 'persist-credentials') == false, 'iPad checkout does not persist credentials')
%w[export].each { |id| check(ipad_steps.find { |step| step['id'] == id }['if'] == 'always()', 'iPad diagnostics survive test failure') }
artifact = ipad_steps.find { |step| step.dig('with', 'name') == 'ChaiClassics-iPad-AppStore-Screenshots' }
check(artifact['if'] == 'always()' && artifact.dig('with', 'name') == 'ChaiClassics-iPad-AppStore-Screenshots', 'iPad artifact name and partial-failure preservation are fixed')
artifact_paths = artifact.dig('with', 'path').lines.map(&:strip).reject(&:empty?)
check(artifact_paths.include?('build/ipad-screenshots/*.png') && artifact_paths.include?('build/ipad-screenshots/*.json') && artifact_paths.include?('build/ipad-screenshots/*.md'), 'the mobile-download artifact includes native PNGs, device metadata and reports')
check(artifact_paths.all? { |path| path.start_with?('build/ipad-screenshots/') } && artifact_paths.none? { |path| path.include?('xcresult') || path.include?('DerivedData') }, 'the screenshot artifact excludes large XCTest movies, unrelated derived data and signing paths')
result_artifact = ipad_steps.find { |step| step.dig('with', 'name') == 'ChaiClassics-iPad-XCTest-Results' }
check(result_artifact && result_artifact['if'] == 'always()' && result_artifact.dig('with', 'path') == 'build/ipad-screenshots/IPadScreenshots.xcresult', 'the complete xcresult remains available in a separate artifact even after UI failure')
ipad_script = File.read(File.join(root, 'scripts/ipad_screenshots.sh'))
check(ipad_script.include?('-sdk iphonesimulator') && ipad_script.include?('CODE_SIGNING_ALLOWED=NO') && ipad_script.include?('test-without-building'), 'iPad tests execute an unsigned Simulator build')
%w[Home Sudoku Minesweeper SlidingPuzzle].each do |game|
  check(ipad_script.include?('-only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testIPad' + game + 'Screenshot'), "independent #{game} iPad case is selected")
end
check(!ipad_script.match?(/run_signing_lane|fastlane|archivePath|exportArchive/), 'iPad orchestration contains no archive, export IPA or release lane')
_, _, invalid_ipad_phase = Open3.capture3('bash', File.join(root, 'scripts/ipad_screenshots.sh'), 'invalid-phase')
check(invalid_ipad_phase.exitstatus == 64, 'invalid iPad phase fails before invoking Xcode or Simulator')
puts 'PASS: independent iPad screenshot workflow is manual, unsigned, standard-hosted, credential-free and retains partial results.'

# v0.2.0 remains an explicit candidate release, never an ordinary-push upload.
check(ci_triggers.dig('push', 'branches') == %w[main develop/0.2.0 develop/0.2.1 develop/0.2.2 develop/0.3.0], 'isolated development pushes receive ordinary credential-free CI')
check(!ci_script.include?('-only-testing:'), 'the complete CI UI phase cannot silently become a subset')
check(ci_script.include?('Pro Max') && ci_script.include?('Plus'), 'full UI prefers a real phone window wide enough for 430pt coverage')
[visual_job, ipad_job].each do |entry|
  check(entry.fetch('if').include?("github.ref == 'refs/heads/develop/0.2.0'") && entry.fetch('if').include?("github.ref == 'refs/heads/main'"), 'only trusted main/development refs may run manual unsigned validation')
  check(entry.fetch('if').include?("github.ref == 'refs/heads/develop/0.2.1'"), '0.2.1 keeps exact-SHA unsigned visual/iPad evidence')
  check(entry.fetch('if').include?("github.ref == 'refs/heads/develop/0.2.2'"), '0.2.2 supports exact-SHA unsigned visual/iPad evidence')
end
candidate_gate = preflight.fetch('steps').find { |step| step['name'] == 'Verify exact-SHA TestFlight candidate' }
check(candidate_gate && candidate_gate['if'] == "startsWith(inputs.version, '0.2.')", '0.2.x TestFlight signing requires an exact-SHA candidate gate')
check(flight.fetch('permissions') == {'contents' => 'read', 'actions' => 'read'}, 'candidate reads receive no repository or Actions write permission')
check(candidate_gate.dig('env', 'GH_TOKEN') == '${{ github.token }}', 'candidate metadata reads use the short-lived read-only workflow token')
validation_mode = (flight['on'] || flight[true]).dig('workflow_dispatch', 'inputs', 'validation_mode')
check(validation_mode['type'] == 'choice' && validation_mode['options'] == %w[beta full] && validation_mode['default'] == 'beta', 'explicit user-selected TestFlight policy defaults to manual Beta QA and retains optional full regression')
check(candidate_gate.dig('env', 'CHAI_VALIDATION_MODE') == "${{ inputs.validation_mode || 'beta' }}", 'candidate gate receives the explicit Beta/full policy')
gate_run = candidate_gate.fetch('run')
beta_case = gate_run.match(/beta\)\n(.*?)\n\s*;;/m)&.captures&.first
full_case = gate_run.match(/full\)\n(.*?)\n\s*;;/m)&.captures&.first
check(beta_case && beta_case.include?('scripts/verify_beta_candidate.py') && beta_case.include?('--sha "$GITHUB_SHA"') && beta_case.include?('--tag "$CHAI_CANDIDATE_TAG"') && beta_case.include?('--branch main') && beta_case.include?('--manual-qa'), 'manual-QA Beta independently verifies the exact main/tag/source SHA')
check(!beta_case.include?('--ci-run') && !beta_case.include?('--visual-run') && !beta_case.include?('--ipad-run'), 'manual-QA Beta defers UI checks to testers without requiring CI/Visual/iPad run inputs')
check(full_case && full_case.include?('scripts/verify_candidate.py verify') && full_case.include?('--sha "$GITHUB_SHA"') && full_case.include?('--ci-run "$CHAI_CANDIDATE_CI_RUN"') && full_case.include?('--visual-run "$CHAI_CANDIDATE_VISUAL_RUN"') && full_case.include?('--ipad-run "$CHAI_CANDIDATE_IPAD_RUN"') && !full_case.include?('--manual-qa'), 'Full mode retains all three exact-SHA workflow evidence requirements')
check(gate_run.include?('case "$CHAI_VALIDATION_MODE" in') && gate_run.include?("*) echo 'Unknown candidate validation mode.' >&2; exit 64"), 'unknown validation modes fail instead of bypassing verification')
%w[candidate_tag ci_run visual_run ipad_run].each do |input|
  check((flight['on'] || flight[true]).dig('workflow_dispatch', 'inputs', input, 'type') == 'string', 'candidate evidence input is explicit: ' + input)
end
check(!full_case.include?('--branch') && beta_case.scan('--branch main').length == 1, 'both TestFlight proof modes remain main-only')
%w[ci visual ipad].each do |kind|
  workflow = kind == 'ci' ? ci_workflow : kind == 'visual' ? visual : ipad
  steps = workflow.fetch('jobs').values.flat_map { |entry| entry.fetch('steps', []) }
  artifact = steps.find { |step| step.dig('with', 'name') == 'candidate-' + kind + '-evidence' }
  check(artifact && artifact.dig('with', 'if-no-files-found') == 'error', 'candidate ' + kind + ' evidence cannot be missing')
end
games_step = ipad_steps.find { |step| step['id'] == 'games' }
check(games_step && games_step['run'] == 'bash scripts/ipad_screenshots.sh games', 'all five new journeys run on the selected iPad')
check(games_step['if'] == "${{ !cancelled() && steps.build.outcome == 'success' && steps.boot.outcome == 'success' }}" && !games_step.key?('continue-on-error'), 'independent iPad journeys survive gallery failure only after successful build and boot, without ignoring failure')
check(ipad_script.include?('IPadGames.xcresult') && ipad_script.include?('games-summary.json'), 'iPad game journeys retain an independent result and actual summary')
check(ipad_script.scan('-only-testing:ChaiClassicsUITests/ChaiClassicsV020UITests/').length == 5, 'exactly five new game journeys are selected separately from four gallery tests')
check(ipad_steps.any? { |step| step.dig('with', 'path') == 'build/ipad-screenshots/IPadGames.xcresult' }, 'all five iPad journey results remain reviewable')
check(ipad_script.include?('--output-path "$CHAI_IPAD_OUTPUT/game-attachments"'), 'new iPad game result attachments are actually exported')
%w[png json txt].each do |extension|
  check(artifact_paths.include?('build/ipad-screenshots/game-attachments/*.' + extension), 'iPad game ' + extension + ' files are included in the mobile review artifact')
end
check(artifact_paths.none? { |path| path.match?(/\.(mp4|mov)\z/) || path.end_with?('game-attachments/') }, 'mobile review artifact does not upload new-game movies')
ui_export = test_job.fetch('steps').find { |step| step['name'] == 'Export full UI screenshots for visual review' }
check(ui_export && ui_export['if'] == 'always()' && !ui_export.key?('continue-on-error'), 'full UI export always preserves failures rather than ignoring them')
check(ui_export.fetch('run').include?('--path build/UITests.xcresult --output-path build/ui-screenshots'), 'complete UI screenshots come from the actual full-suite result')
ci_results = test_job.fetch('steps').find { |step| step.dig('with', 'name') == 'test-results' }
%w[png json txt].each do |extension|
  check(ci_results.dig('with', 'path').lines.map(&:strip).include?('build/ui-screenshots/*.' + extension), 'full UI ' + extension + ' files remain reviewable without Xcode')
end

# Exercise real shell exit propagation with a synthetic command, never Xcode.
# A failure exporting one bundle must not suppress summary attempts or turn green.
Dir.mktmpdir('chai-attachment-export-') do |directory|
  bin = File.join(directory, 'bin')
  FileUtils.mkdir_p(bin)
  fake = File.join(bin, 'xcrun')
  File.write(fake, <<~'BASH')
    #!/bin/bash
    printf '%s\n' "$*" >> "$CHAI_EXPORT_CALL_LOG"
    if [[ "$*" == *'export attachments'* ]]; then
      if [[ "$*" == *'IPadGames.xcresult'* && "${CHAI_FAIL_GAME_EXPORT:-0}" == 1 ]]; then exit 7; fi
      if [[ "$*" == *'UITests.xcresult'* && "${CHAI_FAIL_UI_EXPORT:-0}" == 1 ]]; then exit 9; fi
    fi
    if [[ "$*" == *'get test-results summary'* ]]; then printf '{}\n'; fi
    exit 0
  BASH
  FileUtils.chmod(0o755, fake)
  FileUtils.mkdir_p(File.join(directory, 'build/ipad-screenshots/IPadScreenshots.xcresult'))
  FileUtils.mkdir_p(File.join(directory, 'build/ipad-screenshots/IPadGames.xcresult'))
  FileUtils.mkdir_p(File.join(directory, 'build/UITests.xcresult'))
  calls_path = File.join(directory, 'calls.txt')
  fixture_env = {'PATH' => bin + File::PATH_SEPARATOR + ENV.fetch('PATH'), 'CHAI_EXPORT_CALL_LOG' => calls_path}
  _, _, success = Open3.capture3(fixture_env, 'bash', File.join(root, 'scripts/ipad_screenshots.sh'), 'export', chdir: directory)
  check(success.success?, 'both iPad attachment exports and summaries may succeed')
  _, _, failure = Open3.capture3(fixture_env.merge('CHAI_FAIL_GAME_EXPORT' => '1'), 'bash', File.join(root, 'scripts/ipad_screenshots.sh'), 'export', chdir: directory)
  check(!failure.success?, 'iPad game attachment export failure remains nonzero')
  calls = File.read(calls_path)
  check(calls.include?('--path build/ipad-screenshots/IPadGames.xcresult --output-path build/ipad-screenshots/game-attachments'), 'game attachment export was invoked')
  check(calls.include?('get test-results summary --path build/ipad-screenshots/IPadGames.xcresult'), 'a failed attachment export still attempts its summary')
  _, _, failure = Open3.capture3(fixture_env.merge('CHAI_FAIL_UI_EXPORT' => '1'), 'bash', '-e', '-o', 'pipefail', '-c', ui_export.fetch('run'), chdir: directory)
  check(!failure.success?, 'full UI attachment export failure remains nonzero')
end
puts 'PASS: original iPad-game and full-UI PNG/manifest/text exports remain reviewable; actual export failures propagate without hiding diagnostics.'
status_workflow = workflows.fetch('testflight-status.yml')
status_job = status_workflow.fetch('jobs').fetch('status')
check((status_workflow['on'] || status_workflow[true]).keys == ['workflow_dispatch'], 'Apple status is separately explicitly dispatched')
check(status_job.fetch('if').include?("github.ref == 'refs/heads/main'") && status_job['environment'] == 'testflight', 'Apple status retains trusted-main and environment protection')
check(status_workflow.fetch('permissions') == {'contents' => 'read'}, 'Apple status has no GitHub write permission')
check(status_job.fetch('env').keys.sort == %w[ASC_API_KEY_P8 ASC_ISSUER_ID ASC_KEY_ID RELEASE_VERSION TESTED_BUILD_NUMBER TESTED_COMMIT].sort, 'status receives only Developer read credentials and the exact expected tuple')
check(status_job.fetch('steps').any? { |step| step['run'] == 'ruby scripts/testflight_status.rb' }, 'Apple status uses its independent read-only checker')
status_source = File.read(File.join(root, 'scripts/testflight_status.rb'))
check(status_source.include?('Net::HTTP::Get.new') && !status_source.match?(/Net::HTTP::(?:Post|Put|Patch|Delete)|upload_to_testflight|match\(/), 'status performs GET only, with no signing or upload')
check(tooling_runs.include?('ruby tests/testflight_status_test.rb'), 'read-only Apple state separation is tested without credentials')
puts 'PASS: explicit exact-SHA manual-QA Beta and optional full CI/Visual/4+5 iPad regression; read-only Apple processing/internal/external status remains separate from upload.'
