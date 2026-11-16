require_relative '../fastlane/lib/signing_asset_verifier'

# Read only an existing Apple system signature. No signing identities, keychain
# writes, Apple API, match repository, credentials or new certificates are used.
abort 'FAIL: this regression test requires real macOS codesign' unless RUBY_PLATFORM.include?('darwin')

begin
  commands = ChaiSigningAssets::Commands.new
  verifier = ChaiSigningAssets::Verifier.new(team_id: 'fixture', keychain: 'unused',
    hints: {}, roots: [], commands: commands, reporter: ->(_) {})
  Dir.mktmpdir('codesign-extraction-test-') do |directory|
    Dir.chdir(directory) do
      binary = '/usr/bin/codesign'
      old_prefix = File.join(directory, 'old-extraction')
      _, old_ok = commands.run('codesign', '-d', '--extract-certificates', old_prefix, binary)
      raise 'legacy argv unexpectedly worked' if old_ok || File.exist?(old_prefix + '0')
      puts 'PASS: real macOS codesign rejects the old split-prefix invocation.'

      # Exercise the production extractor with a real certificate-bearing binary.
      embedded = verifier.send(:extract_signing_certificate!, binary, directory)
      leaf = File.binread(File.join(directory, 'certificate0'))
      raise 'DER extraction failed' unless embedded.is_a?(OpenSSL::X509::Certificate) && embedded.to_der == leaf
      raise 'empty certificate' unless embedded.public_key && !leaf.empty?
    end
  end
  puts 'PASS: real macOS codesign reproduces the split-prefix failure and the production extractor reads the embedded DER with an attached prefix; no credentials or keychain changes.'
rescue ChaiSigningAssets::Failure => error
  abort "FAIL: real macOS codesign extraction regression [#{error.code}]; raw output and paths suppressed."
rescue StandardError
  # Even this credential-free test keeps command output/certificate data private.
  abort 'FAIL: real macOS codesign extraction regression; raw output and paths suppressed.'
end
