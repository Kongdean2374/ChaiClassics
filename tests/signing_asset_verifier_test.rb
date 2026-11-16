require 'fastlane'
require 'match'
require 'stringio'
require_relative '../fastlane/lib/signing_config'
require_relative '../fastlane/lib/signing_asset_verifier'

TEAM = 'T123456789'.freeze
UUID = '01234567-0123-4567-89ab-0123456789ab'.freeze

def assert_asset(value, message)
  raise "Asset verifier assertion failed: #{message}" unless value
end

def fixture_certificate(team: TEAM, name: 'Apple Distribution: Fixture', expired: false, future: false)
  key = OpenSSL::PKey::EC.generate('prime256v1')
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2; cert.serial = 1
  cert.subject = OpenSSL::X509::Name.new([['CN', name], ['OU', team]])
  cert.issuer = cert.subject; cert.public_key = key
  cert.not_before = Time.now + (future ? 3600 : -3600)
  cert.not_after = Time.now + (expired ? -1 : 7200)
  cert.sign(key, OpenSSL::Digest::SHA256.new)
  cert
end

def fixture_profile(certificate)
  {
    'UUID' => UUID, 'Name' => 'match AppStore Fixture', 'TeamIdentifier' => [TEAM], 'Platform' => ['iOS'],
    'ApplicationIdentifierPrefix' => [TEAM], 'ExpirationDate' => Time.now + 3600,
    'Entitlements' => { 'application-identifier' => TEAM + '.' + ChaiSigning::APP_IDENTIFIER,
                        'com.apple.developer.team-identifier' => TEAM, 'get-task-allow' => false },
    'DeveloperCertificates' => [StringIO.new(certificate.to_der)]
  }
end

class FixtureCommands
  attr_reader :calls
  attr_accessor :profiles, :certificate, :identity, :failure, :embedded
  def initialize(profiles, certificate)
    @profiles = profiles; @certificate = certificate
    @identity = Digest::SHA1.hexdigest(certificate.to_der).upcase
    @calls = []; @embedded = certificate
  end
  def run(*argv, input: nil)
    @calls << argv
    if argv[0,3] == ['security','cms','-D']
      return ['',false] if failure == 'decode'
      value = profiles[argv[4]]
      return ['',false] unless value
      Array(value['DeveloperCertificates']).each { |blob| blob.rewind if blob.respond_to?(:rewind) } if value.is_a?(Hash)
      return [value.is_a?(String) ? value : Plist::Emit.dump(value), true]
    end
    return [certificate.to_pem, failure != 'keychain'] if argv[0,2] == ['security','find-certificate']
    if argv[0,2] == ['security','find-identity']
      return [identity ? "  1) #{identity} \"fixture identity\"\n  1 valid identities found\n" : '0 valid identities found', true]
    end
    return ['',failure != 'build'] if argv[0] == 'xcrun'
    if argv[0,2] == ['codesign','--force']
      return ['',failure != 'sign']
    end
    return ['',failure != 'verify'] if argv[0,2] == ['codesign','--verify']
    if argv[0,3] == ['codesign','-d','--extract-certificates']
      File.binwrite(argv[3] + '0', embedded.to_der) unless failure == 'extract'
      return ['',true]
    end
    raise 'Unexpected mocked command; no real Apple, keychain or signing operation is permitted in this test'
  end
end

count = 0
Dir.mktmpdir('asset-tests-') do |dir|
  modern = File.join(dir, 'modern'); legacy = File.join(dir, 'legacy')
  FileUtils.mkdir_p([modern,legacy])
  path = File.join(modern, UUID + '.mobileprovision')
  File.binwrite(path, 'fixture-cms-no-private-data')
  cert = fixture_certificate
  data = fixture_profile(cert)
  commands = FixtureCommands.new({path => data},cert)
  report = nil
  hints = {path: nil, uuid: nil, name: nil}
  make = lambda do |local_hints = hints|
    ChaiSigningAssets::Verifier.new(team_id: TEAM,keychain: '/tmp/fixture-keychain',hints: local_hints,
      roots: [modern,legacy],commands: commands,reporter: ->(value) { report = value })
  end
  verify = lambda do |verifier, expected = nil|
    report = nil
    begin
      result = verifier.check!
      assert_asset(expected.nil?, 'expected a stage-specific failure')
      assert_asset(result[:certificate].to_der == cert.to_der, 'correct profile/keychain certificate')
      assert_asset(verifier.stages.include?('PRIVATE_KEY_SIGNED') && verifier.stages.include?('SIGNATURE_VERIFIED') && verifier.stages.include?('SIGNED_CERTIFICATE_MATCH'), 'no signing-stage bypass')
      verifier.mark_xcode_ready!
      assert_asset(report['stages'] == ChaiSigningAssets::STAGES, 'all local stages completed')
    rescue ChaiSigningAssets::Failure => error
      assert_asset(error.code == expected, 'correct fixed stage-specific code')
      assert_asset(report['failure'] == expected, 'safe failure report matches exception')
    end
    serialized = JSON.generate(report)
    assert_asset(!serialized.include?(dir) && !serialized.include?(TEAM) && !serialized.include?(UUID) && !serialized.include?('BEGIN CERTIFICATE'), 'reports expose no paths/IDs/certificate data')
  end

  # Missing env does not invalidate an actually installed modern profile.
  verify.call(make.call); count += 1
  assert_asset(report['profile_source'] == 'installed_scan' && report['path_hint'] == 'missing', 'missing hint fallback')
  verify.call(make.call(path: File.join(dir,'missing'), uuid: UUID, name: nil)); count += 1
  assert_asset(report['profile_source'] == 'match_metadata' && report['path_hint'] == 'stale', 'stale hint uses matching UUID')

  # Match Utils names must agree with the pinned SDK, without revealing values.
  prefix = Match::Utils.environment_variable_name(app_identifier: ChaiSigning::APP_IDENTIFIER,type: :appstore,platform: :ios)
  env = {prefix => UUID, prefix + '_profile-path' => path, prefix + '_profile-name' => data['Name']}
  names = ChaiSigningAssets.hints(env: env)
  assert_asset(names[:path] == path && names[:uuid] == UUID && names[:name] == data['Name'], 'SDK env path naming')
  verify.call(make.call(names)); count += 1

  # Legacy directory and identical duplicates are valid too.
  old = File.join(legacy, UUID + '.mobileprovision'); FileUtils.cp(path,old)
  commands.profiles[old] = data
  verify.call(make.call); count += 1
  FileUtils.rm_f(path)
  verify.call(make.call); count += 1
  FileUtils.cp(old,path); commands.profiles.delete(old); FileUtils.rm_f(old)

  # Actual local copies use both Xcode roots and refuse occupied/different bytes.
  ChaiSigningAssets.prepare_xcode_profile!({path: path, profile: data}, roots: [modern,legacy])
  assert_asset(File.binread(File.join(legacy,UUID + '.mobileprovision')) == File.binread(path), 'legacy/modern installation compatibility')
  count += 1
  collision = File.join(legacy,UUID + '.mobileprovision')
  File.binwrite(collision,'other-app-profile-must-not-be-overwritten')
  begin
    ChaiSigningAssets.prepare_xcode_profile!({path: path, profile: data}, roots: [legacy])
    raise 'Expected profile collision refusal'
  rescue ChaiSigningAssets::Failure => error
    assert_asset(error.code == 'ASSET_PROFILE_INSTALL' && File.binread(collision) == 'other-app-profile-must-not-be-overwritten', 'never overwrite occupied profile filename')
  end
  count += 1
  FileUtils.rm_f(collision)

  # Another app's installed profile must not be selected or changed.
  other = File.join(modern,'other.mobileprovision'); File.binwrite(other,'other-app-untouched')
  other_data = fixture_profile(cert)
  other_data['Entitlements']['application-identifier'] = TEAM + '.cc.chaihome.ChaiPhoto'
  commands.profiles[other] = other_data
  verify.call(make.call); count += 1
  assert_asset(File.binread(other) == 'other-app-untouched', 'other app profile untouched')
  commands.profiles.delete(other); FileUtils.rm_f(other)

  [
    ['ASSET_PROFILE_CONTENT', ->(p) { p['UUID'] = 'invalid' }],
    ['ASSET_BUNDLE_ID', ->(p) { p['Entitlements']['application-identifier'] = TEAM + '.cc.chaihome.ChaiPhoto' }],
    ['ASSET_TEAM_ID', ->(p) { p['TeamIdentifier'] = ['T000000000'] }],
    ['ASSET_PROFILE_EXPIRED', ->(p) { p['ExpirationDate'] = Time.now - 1 }],
    ['ASSET_PROFILE_CONTENT', ->(p) { p['ExpirationDate'] = 'invalid' }],
    ['ASSET_PROFILE_TYPE', ->(p) { p['ProvisionedDevices'] = [] }],
    ['ASSET_PROFILE_TYPE', ->(p) { p['Entitlements']['get-task-allow'] = true }],
    ['ASSET_PROFILE_TYPE', ->(p) { p['Platform'] = ['OSX'] }],
    ['ASSET_CERT_CONTENT', ->(p) { p['DeveloperCertificates'] = [] }],
    ['ASSET_CERT_CONTENT', ->(p) { p['DeveloperCertificates'] = [StringIO.new('invalid')] }]
  ].each do |code,change|
    altered = fixture_profile(cert); change.call(altered); commands.profiles = {path => altered}
    verify.call(make.call(path: path, uuid: nil, name: nil),code); count += 1
  end
  [
    ['ASSET_CERT_EXPIRED', fixture_certificate(expired: true)],
    ['ASSET_CERT_NOT_YET_VALID', fixture_certificate(future: true)],
    ['ASSET_CERT_TEAM', fixture_certificate(team: 'T000000000')],
    ['ASSET_CERT_TYPE', fixture_certificate(name: 'Apple Development: Fixture')]
  ].each do |code, bad_cert|
    commands.profiles = {path => fixture_profile(bad_cert)}
    verify.call(make.call,code); count += 1
  end
  commands.profiles = {path => data}
  commands.identity = nil
  verify.call(make.call,'ASSET_DISTRIBUTION_IDENTITY'); count += 1
  commands.identity = Digest::SHA1.hexdigest(cert.to_der).upcase
  other_cert = fixture_certificate
  commands.certificate = other_cert
  verify.call(make.call,'ASSET_CERT_PROFILE_PAIR'); count += 1
  commands.certificate = cert
  {'decode'=>'ASSET_PROFILE_DECODE','keychain'=>'ASSET_KEYCHAIN_CERT','build'=>'ASSET_PROBE_BUILD','sign'=>'ASSET_PRIVATE_KEY_SIGN','verify'=>'ASSET_SIGNATURE_VERIFY','extract'=>'ASSET_SIGNED_CERT_PAIR'}.each do |failure,code|
    commands.failure = failure
    verify.call(make.call(path: path, uuid: nil, name: nil),code); count += 1
  end
  commands.failure = nil; commands.embedded = other_cert
  verify.call(make.call,'ASSET_SIGNED_CERT_PAIR'); count += 1
  commands.embedded = cert
  FileUtils.rm_f(path)
  verify.call(make.call,'ASSET_PROFILE_PATH'); count += 1
end
puts "PASS: #{count} local signing-asset cases including missing/stale hints, Xcode directories, strict pairing and real-command failure gates (macOS commands mocked; no Apple operations)."
