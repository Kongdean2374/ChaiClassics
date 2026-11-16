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
check(job.fetch('steps').all? { |step| !step.fetch('run', '').include?('secrets.') }, 'never interpolate secrets directly into shell')
puts "PASS: #{workflows.length} workflow YAML files parsed; bootstrap Admin mapping, Developer-key isolation, shared secrets, manual main guards and safe runner verified."

fastfile = File.read(File.join(root, 'fastlane/Fastfile'))
bootstrap_lane = fastfile.split('lane :initialize_signing do', 2).last.split('lane :beta do', 2).first
beta_lane = fastfile.split('lane :beta do', 2).last.split('lane :prepare_store do', 2).first
check(bootstrap_lane.include?('verify_apple_access!'), 'Admin bootstrap must verify Apple management permissions')
check(!beta_lane.include?('verify_apple_access!'), 'Developer readonly upload must not require Apple certificate/profile management permissions')
check(beta_lane.include?('with_match_signing(key, readonly: true)'), 'Developer upload must remain match readonly')
puts 'PASS: Admin-only portal permission probe; Developer readonly TestFlight does not require management permissions.'
