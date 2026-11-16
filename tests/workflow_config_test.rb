require 'yaml'

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
check(extraction_job['runs-on'] == 'macos-15', 'real codesign regression runs on macOS')
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
