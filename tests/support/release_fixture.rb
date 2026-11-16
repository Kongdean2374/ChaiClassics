require 'fastlane'
require 'gym'
require 'fastlane/actions/build_app'
require 'stringio'
require_relative '../../fastlane/lib/release_pipeline'

module ReleaseFixture
  def self.certificate
    key = OpenSSL::PKey::EC.generate('prime256v1')
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2; cert.serial = 1
    cert.subject = OpenSSL::X509::Name.new([['CN', "Apple Distribution: Fixture O'Neil"], ['OU','T123456789']])
    cert.issuer = cert.subject; cert.public_key = key
    cert.not_before = Time.now - 3600; cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    cert
  end

  def self.options(certificate: self.certificate)
    root = File.expand_path('../..', __dir__)
    ChaiRelease.build_options(root: root, version: '0.1.0', number: '1.0.1', team: 'T123456789',
      profile_uuid: '01234567-0123-4567-89ab-0123456789ab', certificate: certificate,
      identity: Digest::SHA1.hexdigest(certificate.to_der).upcase, keychain: "/tmp/fixture's keychain/isolated.keychain-db")
  end

  def self.silence
    old_out = $stdout; old_err = $stderr
    $stdout = StringIO.new; $stderr = StringIO.new
    yield
  ensure
    $stdout = old_out; $stderr = old_err
  end

  def self.check(condition)
    raise 'Release regression assertion failed; fixture values suppressed' unless condition
  end
end
