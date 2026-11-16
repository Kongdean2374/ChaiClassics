require_relative 'support/release_fixture'
require 'gym/generators/package_command_generator_xcode7'

abort 'FAIL: real Xcode export configuration test requires macOS' unless RUBY_PLATFORM.include?('darwin')
stage = 'XCODE_VERSION'
begin
  version, _, ok = Open3.capture3('xcodebuild','-version')
  ReleaseFixture.check(ok.success? && version.match?(/\AXcode 26\./))
  stage = 'GYM_OPTIONS'
  params = ChaiRelease.export_options(ReleaseFixture.options)
  Gym.config = ReleaseFixture.silence { ChaiRelease.validate_options!(params) }
  stage = 'EXPORT_PLIST'
  xml = ReleaseFixture.silence { Gym::PackageCommandGeneratorXcode7.config_content }
  plist = Plist.parse_xml(xml)
  ReleaseFixture.check(plist['method'] == 'app-store' && plist['destination'] == 'export')
  ReleaseFixture.check(plist['signingCertificate'] == params[:export_options][:signingCertificate])
  ReleaseFixture.check(plist['provisioningProfiles'] == params[:export_options][:provisioningProfiles])
  ReleaseFixture.check(plist['signingStyle'] == 'manual' && plist['manageAppVersionAndBuildNumber'] == false)
  puts 'PASS: real locked Gym generates the production export plist with exact certificate/profile binding.'

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
rescue StandardError
  # stage is assigned only fixed literals, never dynamic tool/error data.
  abort "FAIL: pinned Gym/Xcode export regression [#{stage}]; raw values, tool output and paths suppressed."
end
