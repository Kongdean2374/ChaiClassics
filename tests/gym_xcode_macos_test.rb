require_relative 'support/release_fixture'
require 'gym/generators/package_command_generator_xcode7'

abort 'FAIL: real Xcode export configuration test requires macOS' unless RUBY_PLATFORM.include?('darwin')
stage = 'XCODE_VERSION'
begin
  version, _, ok = Open3.capture3('xcodebuild','-version')
  ReleaseFixture.check(ok.success? && version.match?(/\AXcode 26\./))
  stage = 'GYM_OPTIONS'
  params = ChaiRelease.export_options(ReleaseFixture.options)
  ReleaseFixture.silence { Gym.config = ChaiRelease.validate_options!(params) }
  stage = 'EXPORT_PLIST_GENERATOR'
  xml = ReleaseFixture.silence do
    Dir.mktmpdir('gym-export-plist-') do |directory|
      Gym.cache[:config_path] = File.join(directory,'ExportOptions.plist')
      Gym.cache[:temporary_output_path] = File.join(directory,'Export')
      # config_content is private in 2.228.0; exercise the same public generator
      # as Gym::Runner instead of calling an internal implementation method.
      Gym::PackageCommandGeneratorXcode7.generate
      File.read(Gym::PackageCommandGeneratorXcode7.config_path)
    end
  end
  stage = 'EXPORT_PLIST_PARSE'
  plist = Plist.parse_xml(xml)
  stage = 'EXPORT_METHOD_BINDING'
  ReleaseFixture.check(plist['method'] == 'app-store' && plist['destination'] == 'export')
  stage = 'EXPORT_CERT_BINDING'
  ReleaseFixture.check(plist['signingCertificate'] == params[:export_options][:signingCertificate])
  stage = 'EXPORT_PROFILE_BINDING'
  ReleaseFixture.check(plist['provisioningProfiles'] == params[:export_options][:provisioningProfiles])
  stage = 'EXPORT_MANUAL_BINDING'
  ReleaseFixture.check(plist['signingStyle'] == 'manual' && plist['manageAppVersionAndBuildNumber'] == false)
  puts 'PASS: real locked Gym generates the production export plist with exact certificate/profile binding.'

  stage = 'TARGET_SIGNING_SCOPE'
  settings = Shellwords.split(params.fetch(:xcargs)).to_h { |arg| arg.split('=',2) }
  resolved = lambda do |extra|
    out, _, status = Open3.capture3('xcodebuild','-showBuildSettings','-json','-project',params[:project],
      '-alltargets','-configuration','Release','-sdk','iphoneos','CODE_SIGNING_ALLOWED=NO',*extra)
    ReleaseFixture.check(status.success?)
    JSON.parse(out).to_h { |target| [target.fetch('target'),target.fetch('buildSettings')] }
  end
  uuid = settings.fetch('CHAI_SIGNING_PROFILE')
  legacy = resolved.call(["PROVISIONING_PROFILE_SPECIFIER=#{uuid}","DEVELOPMENT_TEAM=#{settings.fetch('CHAI_SIGNING_TEAM')}"])
  scoped = resolved.call(Shellwords.split(params[:xcargs]))
  ReleaseFixture.check(legacy.fetch('ChaiClassicsUITests')['PROVISIONING_PROFILE_SPECIFIER'] == uuid)
  ReleaseFixture.check(scoped.fetch('ChaiClassics')['PROVISIONING_PROFILE_SPECIFIER'] == uuid)
  ReleaseFixture.check(scoped.fetch('ChaiClassics')['DEVELOPMENT_TEAM'] == settings.fetch('CHAI_SIGNING_TEAM'))
  ReleaseFixture.check(scoped.fetch('ChaiClassicsUITests').fetch('PROVISIONING_PROFILE_SPECIFIER','') != uuid)
  puts 'PASS: real Xcode build settings reproduce legacy cross-target profile propagation; app-scoped bindings keep the app profile off the other target.'

  # A real UNSIGNED iOS fixture only tests the local Xcode export parser. No
  # signing Secrets, key imports, provisioning updates or uploads are allowed.
  Dir.mktmpdir('xcode-export-parser-') do |directory|
    archive = File.join(directory,'Fixture.xcarchive')
    stage = 'UNSIGNED_ARCHIVE'
    _, _, built = Open3.capture3('xcodebuild','-quiet','-project',params[:project],'-scheme','ChaiClassics',
      '-configuration','Release','-destination','generic/platform=iOS','-archivePath',archive,
      '-derivedDataPath',File.join(directory,'DerivedData'),'CODE_SIGNING_ALLOWED=NO',
      'CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','archive')
    ReleaseFixture.check(built.success?)
    puts 'PASS: real Xcode created the unsigned iOS fixture archive without signing credentials.'
    export = lambda do |method|
      path = File.join(directory,'options.plist')
      File.write(path,plist.merge('method' => method).to_plist)
      out, err, status = Open3.capture3('xcodebuild','-exportArchive','-archivePath',archive,
        '-exportOptionsPlist',path,'-exportPath',File.join(directory,'Export'))
      [out+err,status.success?]
    end
    stage = 'INVALID_METHOD_CONTROL'
    invalid, invalid_ok = export.call('invalid-release-method')
    ReleaseFixture.check(!invalid_ok && invalid.include?('invalid-release-method'))
    stage = 'LEGACY_METHOD_PARSER'
    legacy, legacy_ok = export.call('app-store')
    method_error = legacy.match?(/exportOptionsPlist error for key ["']method["']/i)
    ReleaseFixture.check(!method_error && (legacy_ok || legacy.match?(/deprecated|signing|provision|certificate|team|account/i)))
    puts 'PASS: real Xcode export parser rejects the invalid method control and accepts legacy app-store; unsigned fixture cannot establish signed production export success.'
  end
  puts 'LIMIT: no production signed IPA export or TestFlight upload was performed; real signing assets are excluded from CI.'
rescue StandardError => error
  # stage is assigned only fixed literals, never dynamic tool/error data.
  classes = %w[NoMethodError NameError ArgumentError TypeError RuntimeError FastlaneCore::Interface::FastlaneError]
  category = classes.include?(error.class.name) ? error.class.name : 'UNKNOWN'
  sources = %w[package_command_generator_xcode7.rb configuration.rb config_item.rb gym_xcode_macos_test.rb helper.rb ui.rb]
  location = error.backtrace_locations&.find { |item| sources.include?(File.basename(item.path)) }
  source = location ? File.basename(location.path) + ':' + location.lineno.to_s : 'unknown'
  abort "FAIL: pinned Gym/Xcode export regression [#{stage}] kind=#{category} source=#{source}; raw values, tool output and sensitive paths suppressed."
end
