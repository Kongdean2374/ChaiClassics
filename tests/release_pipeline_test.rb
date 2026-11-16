require_relative 'support/release_fixture'

check = ReleaseFixture.method(:check)
options = ReleaseFixture.options
count = 0

# This calls the installed, locked build_app action's real Gym::Options verifier.
# No mock replaces the library validator and no archive/upload action is run.
check.call(Fastlane::VERSION == '2.228.0')
old_error = nil
ReleaseFixture.silence do
  begin
    FastlaneCore::Configuration.create(Fastlane::Actions::BuildAppAction.available_options,
      options.merge(export_method: 'app-store-connect'))
  rescue StandardError => error
    old_error = error
  end
end
check.call(old_error && old_error.message.include?("Unsupported export_method 'app-store-connect'"))
puts 'PASS: locked fastlane 2.228.0 rejects the original app-store-connect value before archive/upload.'
count += 1

[ChaiRelease.archive_options(options), ChaiRelease.export_options(options)].each do |params|
  config = ReleaseFixture.silence { ChaiRelease.validate_options!(params) }
  check.call(config[:export_method] == 'app-store' && config[:codesigning_identity] == options[:codesigning_identity])
  check.call(config[:export_options][:signingCertificate] == options[:export_options][:signingCertificate])
  count += 1
end
check.call(ChaiRelease.archive_options(options)[:skip_package_ipa] == true)
check.call(ChaiRelease.export_options(options)[:skip_build_archive] == true)
check.call(ChaiRelease.export_options(options)[:skip_package_ipa] == false)
settings = Shellwords.split(options[:xcargs]).to_h { |setting| setting.split('=',2) }
check.call(Shellwords.split(settings.fetch('OTHER_CODE_SIGN_FLAGS')) == ['--keychain', "/tmp/fixture's keychain/isolated.keychain-db"])
check.call(options[:codesigning_identity].start_with?('Apple Distribution:') && !options[:codesigning_identity].match?(/\A[A-F0-9]{40}\z/))
count += 1

[options.merge(export_method: 'app-store-connect'), options.merge(nonexistent_gym_option: true), options.merge(clean: ['invalid'])].each do |bad|
  failed = false
  ReleaseFixture.silence do
    begin
      ChaiRelease.validate_options!(bad)
    rescue ChaiRelease::Failure => error
      failed = error.phase == 'BUILD_CONFIG'
    end
  end
  check.call(failed); count += 1
end

cert = ReleaseFixture.certificate
begin
  ChaiRelease.build_options(root: '.',version: '0.1.0',number: '1.0.1',team: 'T123456789',profile_uuid: 'fixture',
    identity: '0' * 40, certificate: cert, keychain: 'unused')
  raise 'Expected mismatched fingerprint rejection'
rescue ChaiRelease::Failure => error
  check.call(error.reason == 'IDENTITY_BINDING'); count += 1
end

# Validate fixed phase reports, failure propagation, ordering and secret suppression.
Dir.mktmpdir('release-report-test-') do |directory|
  path = File.join(directory,'report.json')
  ChaiRelease::PHASES.each_with_index do |failing,index|
    report = ChaiRelease::Report.new(path: path)
    ChaiRelease::PHASES.first(index).each { |phase| report.run(phase) { true } }
    begin
      report.run(failing) { raise "DO_NOT_PRINT_PRIVATE_TOKEN_PATH_CERT" }
    rescue ChaiRelease::Failure => error
      check.call(error.phase == failing && !error.message.include?('DO_NOT_PRINT'))
    end
    data = JSON.parse(File.read(path))
    check.call(data['phase'] == failing && data['status'] == 'failed' && !File.read(path).include?('DO_NOT_PRINT'))
    count += 1
  end
  [401,403,404,429,500,503].each do |status|
    error = Class.new(StandardError) { attr_accessor :status }.new('DO_NOT_PRINT_BODY_TOKEN')
    error.status = status
    begin
      ChaiRelease::Report.new(path: path).run('UPLOAD_AUTH') { raise error }
    rescue ChaiRelease::Failure => safe
      check.call(safe.http_status == status && safe.reason != 'UNKNOWN')
    end
    count += 1
  end
  report = ChaiRelease::Report.new(path: path)
  ChaiRelease::PHASES.each { |phase| report.run(phase) { true } }
  check.call(JSON.parse(File.read(path))['status'] == 'complete'); count += 1
  before = File.binread(path)
  begin
    ChaiRelease::Report.new(path: path).run('ARCHIVE') { raise 'Must not execute out of order' }
    raise 'Expected phase ordering refusal'
  rescue ChaiRelease::Failure => error
    check.call(error.reason == 'INPUT_REJECTED' && File.binread(path) == before); count += 1
  end

  # Synthetic archive must retain the exact already-verified certificate/profile.
  app = File.join(directory,'archive/Products/Applications/ChaiClassics.app'); FileUtils.mkdir_p(app)
  original = File.join(directory,'profile'); File.binwrite(original,'fixture-cms')
  File.binwrite(File.join(app,'embedded.mobileprovision'),'fixture-cms')
  commands = Object.new
  commands.define_singleton_method(:run) do |*argv, input: nil|
    if argv[1] == '-d'
      prefix = argv[2].delete_prefix('--extract-certificates=')
      File.binwrite(prefix+'0',cert.to_der)
    end
    ['',true]
  end
  assets = {certificate: cert, path: original}
  ChaiRelease.verify_archive!(path: File.join(directory,'archive'),assets: assets,commands: commands); count += 1
  [{certificate: ReleaseFixture.certificate,path: original}, assets].each_with_index do |bad,i|
    File.binwrite(File.join(app,'embedded.mobileprovision'),'other-profile') if i == 1
    begin
      ChaiRelease.verify_archive!(path: File.join(directory,'archive'),assets: bad,commands: commands)
      raise 'Expected archive pairing failure'
    rescue ChaiRelease::Failure => error
      check.call(error.reason == (i == 0 ? 'ARCHIVE_CERT_MISMATCH' : 'ARCHIVE_PROFILE_MISMATCH'))
    end
    count += 1
  end
  ipa = File.join(directory,'fixture.ipa'); File.binwrite(ipa,'fixture-output')
  check.call(ChaiRelease.verify_ipa!(ipa,expected: ipa) == ipa); count += 1
  begin
    ChaiRelease.verify_ipa!(nil,expected: ipa)
    raise 'Expected missing IPA rejection'
  rescue ChaiRelease::Failure => error
    check.call(error.reason == 'IPA_MISSING'); count += 1
  end
end
puts "PASS: #{count} pinned build_app, phase/error, argument quoting and archive/IPA pairing cases; no Apple requests, archive or upload actions executed."
