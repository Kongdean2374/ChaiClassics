require_relative 'support/release_fixture'
require 'gym/generators/package_command_generator_xcode7'

abort 'FAIL: real Xcode export configuration test requires macOS' unless RUBY_PLATFORM.include?('darwin')
begin
  version, _, ok = Open3.capture3('xcodebuild','-version')
  ReleaseFixture.check(ok.success? && version.match?(/\AXcode 26\./))
  stdout, stderr, status = Open3.capture3('xcodebuild','-help')
  help = stdout + stderr
  # Require the actual Xcode help to list both the modern spelling and legacy
  # app-store alias; matching app-store as a substring of app-store-connect fails.
  ReleaseFixture.check(status.success? && help.include?('app-store-connect') && help.match?(/\bapp-store\b(?!-connect)/))
  params = ChaiRelease.export_options(ReleaseFixture.options)
  Gym.config = ReleaseFixture.silence { ChaiRelease.validate_options!(params) }
  xml = ReleaseFixture.silence { Gym::PackageCommandGeneratorXcode7.config_content }
  plist = Plist.parse_xml(xml)
  ReleaseFixture.check(plist['method'] == 'app-store' && plist['destination'] == 'export')
  ReleaseFixture.check(plist['signingCertificate'] == params[:export_options][:signingCertificate])
  ReleaseFixture.check(plist['provisioningProfiles'] == params[:export_options][:provisioningProfiles])
  ReleaseFixture.check(plist['signingStyle'] == 'manual' && plist['manageAppVersionAndBuildNumber'] == false)
  puts 'PASS: selected Xcode 26 documents the legacy app-store alias; locked Gym accepts complete production options and generates the expected export plist with exact certificate/profile binding.'
  puts 'LIMIT: no signed IPA export or upload was performed; real signing assets are excluded from CI.'
rescue StandardError
  abort 'FAIL: pinned Gym/Xcode export configuration regression; raw values, tool output and paths suppressed.'
end
