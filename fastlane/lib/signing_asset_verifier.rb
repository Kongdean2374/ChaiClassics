require 'openssl'
require 'digest'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'plist'
require 'json'
require 'date'

# Post-match validation of LOCAL assets. This module never calls Apple or Git.
module ChaiSigningAssets
  CODES = %w[ASSET_READONLY_REQUIRED ASSET_KEYCHAIN_SETUP ASSET_MATCH_READ ASSET_PROFILE_PATH ASSET_PROFILE_READ ASSET_PROFILE_DECODE ASSET_PROFILE_CONTENT ASSET_PROFILE_AMBIGUOUS ASSET_PROFILE_METADATA ASSET_BUNDLE_ID ASSET_TEAM_ID ASSET_PROFILE_EXPIRED ASSET_PROFILE_TYPE ASSET_CERT_CONTENT ASSET_CERT_EXPIRED ASSET_CERT_NOT_YET_VALID ASSET_CERT_TEAM ASSET_CERT_TYPE ASSET_KEYCHAIN_CERT ASSET_CERT_PROFILE_PAIR ASSET_DISTRIBUTION_IDENTITY ASSET_IDENTITY_AMBIGUOUS ASSET_PROBE_BUILD ASSET_PRIVATE_KEY_SIGN ASSET_SIGNATURE_VERIFY ASSET_SIGNED_CERT_PAIR ASSET_PROFILE_INSTALL ASSET_INTERNAL].freeze
  STAGES = %w[MATCH_READONLY PROFILE_LOCATED PROFILE_DECODED BUNDLE_ID_VALID TEAM_ID_VALID PROFILE_DATES_VALID APPSTORE_PROFILE_VALID CERTIFICATE_VALID KEYCHAIN_CERTIFICATE_MATCH DISTRIBUTION_IDENTITY_MATCH PRIVATE_KEY_SIGNED SIGNATURE_VERIFIED SIGNED_CERTIFICATE_MATCH XCODE_PROFILE_READY].freeze
  SOURCES = %w[match_env match_metadata installed_scan unknown].freeze
  HINTS = %w[present stale missing].freeze

  class Failure < StandardError
    attr_reader :code
    def initialize(code)
      @code = CODES.include?(code) ? code : 'ASSET_INTERNAL'
      super(@code) # Never include paths, IDs, exception text or certificate bytes.
    end
  end

  class Commands
    def run(*argv, input: nil)
      out, _err, status = Open3.capture3(*argv, stdin_data: input)
      [out, status.success?]
    rescue StandardError
      ['', false]
    end
  end

  def self.roots(home: Dir.home)
    [File.join(home, 'Library/Developer/Xcode/UserData/Provisioning Profiles'),
     File.join(home, 'Library/MobileDevice/Provisioning Profiles')]
  end

  def self.hints(env:, mapping: {})
    # Use pinned fastlane's own naming API instead of duplicating its rules.
    type = Match.profile_type_sym('appstore')
    args = { app_identifier: ChaiSigning::APP_IDENTIFIER, type: type, platform: :ios }
    {
      path: env[Match::Utils.environment_variable_name_profile_path(**args)],
      uuid: env[Match::Utils.environment_variable_name(**args)],
      name: env[Match::Utils.environment_variable_name_profile_name(**args)] || mapping[ChaiSigning::APP_IDENTIFIER]
    }
  end

  def self.write_report(report)
    path = ENV['CHAI_SIGNING_ASSET_REPORT_PATH']
    return unless path && !path.empty?
    File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |f| f.write(JSON.generate(report)) }
  end

  def self.prepare_xcode_profile!(result, roots: ChaiSigningAssets.roots)
    uuid = result.fetch(:profile).fetch('UUID')
    raise Failure.new('ASSET_PROFILE_INSTALL') unless uuid.is_a?(String) && uuid.match?(/\A[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\z/)
    roots.each do |root|
      FileUtils.mkdir_p(root)
      destination = File.join(root, uuid + '.mobileprovision')
      if File.exist?(destination)
        raise Failure.new('ASSET_PROFILE_INSTALL') unless File.binread(destination) == File.binread(result.fetch(:path))
      else
        FileUtils.cp(result.fetch(:path), destination)
      end
    end
  rescue Failure
    raise
  rescue StandardError
    raise Failure.new('ASSET_PROFILE_INSTALL')
  end

  class Verifier
    attr_reader :stages
    def initialize(team_id:, keychain:, hints:, roots: ChaiSigningAssets.roots, commands: Commands.new,
                   now: Time.now, reporter: ChaiSigningAssets.method(:write_report))
      @team = team_id; @keychain = keychain; @hints = hints; @roots = roots
      @commands = commands; @now = now; @reporter = reporter
      @stages = ['MATCH_READONLY']; @source = 'unknown'
      @hint_state = hints[:path].to_s.empty? ? 'missing' : File.file?(hints[:path]) ? 'present' : 'stale'
    end

    def check!
      path, profile = locate_profile
      stages << 'PROFILE_LOCATED' << 'PROFILE_DECODED'
      validate_profile!(profile)
      certificates = profile_certificates!(profile)
      identity, certificate = match_identity!(certificates)
      sign_probe!(identity, certificate)
      # Modern Xcode may not find a profile installed only in the legacy folder.
      # Return validated metadata; the caller performs a scoped temporary copy.
      result = { path: path, profile: profile, identity: identity, certificate: certificate }
      publish(nil)
      result
    rescue Failure => error
      publish(error.code)
      raise
    rescue StandardError
      publish('ASSET_INTERNAL')
      raise Failure.new('ASSET_INTERNAL')
    end

    def mark_xcode_ready!
      stages << 'XCODE_PROFILE_READY'
      publish(nil)
    end

    private
    def publish(failure)
      @reporter.call({ 'schema' => 1, 'readonly' => true, 'stages' => stages.dup,
                      'profile_source' => @source, 'path_hint' => @hint_state, 'failure' => failure })
    end

    def run!(code, *argv, input: nil)
      output, ok = @commands.run(*argv, input: input)
      raise Failure.new(code) unless ok
      output
    end

    def decode(path)
      raise Failure.new('ASSET_PROFILE_PATH') unless File.file?(path)
      raise Failure.new('ASSET_PROFILE_READ') unless File.readable?(path)
      xml = run!('ASSET_PROFILE_DECODE', 'security', 'cms', '-D', '-i', path)
      data = begin Plist.parse_xml(xml); rescue StandardError; nil; end
      raise Failure.new('ASSET_PROFILE_CONTENT') unless data.is_a?(Hash)
      data
    end

    def bundle_matches?(data)
      app = data.dig('Entitlements', 'application-identifier') if data['Entitlements'].is_a?(Hash)
      prefixes = data['ApplicationIdentifierPrefix']
      prefixes.is_a?(Array) && prefixes.any? { |prefix| app == "#{prefix}.#{ChaiSigning::APP_IDENTIFIER}" }
    end

    def locate_profile
      files = @roots.flat_map { |root| Dir.glob(File.join(root, '*.mobileprovision')) }
      files.unshift(@hints[:path]) unless @hints[:path].to_s.empty?
      decoded = []; relevant_error = nil
      files.compact.uniq.each do |path|
        begin
          data = decode(path)
          decoded << [path, data]
        rescue Failure => error
          uuid_file = @hints[:uuid] && File.basename(path, '.mobileprovision').casecmp?(@hints[:uuid])
          relevant_error ||= error if path == @hints[:path] || uuid_file
        end
      end
      candidates = decoded.select { |_, data| bundle_matches?(data) }
      if candidates.empty?
        # Decode a strong explicit candidate fully so bundle/content failures are
        # not mislabeled as path failures. Other apps' scanned files are ignored.
        explicit = decoded.find { |path,_| path == @hints[:path] }
        if explicit
          @source = 'match_env'
          return explicit
        end
        raise relevant_error if relevant_error
        raise Failure.new('ASSET_PROFILE_PATH')
      end
      unless @hints[:uuid].to_s.empty?
        selected = candidates.select { |_, data| data['UUID'].to_s.casecmp?(@hints[:uuid]) }
        raise Failure.new('ASSET_PROFILE_METADATA') if selected.empty?
        candidates = selected
        @source = 'match_metadata'
      end
      unless @hints[:name].to_s.empty?
        named = candidates.select { |_, data| data['Name'] == @hints[:name] }
        unless named.empty?
          candidates = named
          @source = 'match_metadata' if @source == 'unknown'
        end
      end
      direct = candidates.find { |path,_| path == @hints[:path] }
      if direct
        @source = 'match_env'
        return direct
      end
      @hint_state = 'stale' if @hint_state == 'present'
      @source = 'installed_scan' if @source == 'unknown'
      # Same UUID in modern/legacy folders is common; distinct UUIDs require an
      # unambiguous match hint, never silently choose another app or old profile.
      raise Failure.new('ASSET_PROFILE_AMBIGUOUS') if candidates.map { |_, data| data['UUID'] }.uniq.length != 1
      # Require semantically identical profiles if duplicate UUIDs are present.
      raise Failure.new('ASSET_PROFILE_AMBIGUOUS') unless candidates.map { |path,_| Digest::SHA256.file(path).hexdigest }.uniq.length == 1
      candidates.first
    end

    def validate_profile!(data)
      valid = data['UUID'].is_a?(String) && data['UUID'].match?(/\A[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\z/) &&
              data['Name'].is_a?(String) && !data['Name'].empty? && data['Entitlements'].is_a?(Hash) &&
              data['ApplicationIdentifierPrefix'].is_a?(Array) && !data['ApplicationIdentifierPrefix'].empty?
      raise Failure.new('ASSET_PROFILE_CONTENT') unless valid
      raise Failure.new('ASSET_BUNDLE_ID') unless bundle_matches?(data)
      stages << 'BUNDLE_ID_VALID'
      teams = data['TeamIdentifier']; entitlement_team = data['Entitlements']['com.apple.developer.team-identifier']
      raise Failure.new('ASSET_TEAM_ID') unless teams.is_a?(Array) && teams.include?(@team) && (entitlement_team.nil? || entitlement_team == @team)
      stages << 'TEAM_ID_VALID'
      expiry = data['ExpirationDate']
      raise Failure.new('ASSET_PROFILE_CONTENT') unless expiry.is_a?(Time) || expiry.is_a?(DateTime)
      raise Failure.new('ASSET_PROFILE_EXPIRED') unless expiry.to_time > @now
      stages << 'PROFILE_DATES_VALID'
      store = data['Platform'].is_a?(Array) && data['Platform'].include?('iOS') &&
              !data.key?('ProvisionedDevices') && data['ProvisionsAllDevices'] != true && data['Entitlements']['get-task-allow'] == false
      raise Failure.new('ASSET_PROFILE_TYPE') unless store
      stages << 'APPSTORE_PROFILE_VALID'
    end

    def profile_certificates!(profile)
      blobs = profile['DeveloperCertificates']
      raise Failure.new('ASSET_CERT_CONTENT') unless blobs.is_a?(Array) && !blobs.empty?
      certs = blobs.map do |blob|
        raw = blob.respond_to?(:string) ? blob.string : blob
        begin OpenSSL::X509::Certificate.new(raw); rescue StandardError; raise Failure.new('ASSET_CERT_CONTENT'); end
      end
      valid = certs.select { |c| c.not_before <= @now && c.not_after > @now }
      raise Failure.new(certs.any? { |c| c.not_before > @now } ? 'ASSET_CERT_NOT_YET_VALID' : 'ASSET_CERT_EXPIRED') if valid.empty?
      team = valid.select { |c| c.subject.to_a.any? { |part| part[0] == 'OU' && part[1] == @team } }
      raise Failure.new('ASSET_CERT_TEAM') if team.empty?
      distribution = team.select { |c| c.subject.to_a.any? { |part| part[0] == 'CN' && part[1].match?(/\A(?:Apple Distribution|iPhone Distribution):/) } }
      raise Failure.new('ASSET_CERT_TYPE') if distribution.empty?
      stages << 'CERTIFICATE_VALID'
      distribution
    end

    def match_identity!(certificates)
      pem = run!('ASSET_KEYCHAIN_CERT', 'security', 'find-certificate', '-a', '-p', @keychain)
      installed = pem.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).map do |text|
        begin OpenSSL::X509::Certificate.new(text); rescue StandardError; raise Failure.new('ASSET_KEYCHAIN_CERT'); end
      end
      paired = certificates.select { |cert| installed.any? { |candidate| candidate.to_der == cert.to_der } }
      raise Failure.new('ASSET_CERT_PROFILE_PAIR') if paired.empty?
      stages << 'KEYCHAIN_CERTIFICATE_MATCH'
      output = run!('ASSET_DISTRIBUTION_IDENTITY', 'security', 'find-identity', '-v', '-p', 'codesigning', @keychain)
      hashes = output.scan(/^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"/).flatten.map(&:upcase)
      matches = paired.select { |cert| hashes.include?(Digest::SHA1.hexdigest(cert.to_der).upcase) }
      raise Failure.new('ASSET_DISTRIBUTION_IDENTITY') if matches.empty?
      raise Failure.new('ASSET_IDENTITY_AMBIGUOUS') if matches.length != 1
      cert = matches.first
      stages << 'DISTRIBUTION_IDENTITY_MATCH'
      [Digest::SHA1.hexdigest(cert.to_der).upcase, cert]
    end

    def sign_probe!(identity, certificate)
      Dir.mktmpdir('chai-signature-probe-') do |dir|
        binary = File.join(dir, 'probe')
        run!('ASSET_PROBE_BUILD', 'xcrun', '--sdk', 'macosx', 'clang', '-x', 'c', '-', '-o', binary, input: 'int main(void) { return 0; }')
        run!('ASSET_PRIVATE_KEY_SIGN', 'codesign', '--force', '--sign', identity, '--keychain', @keychain, '--timestamp=none', binary)
        stages << 'PRIVATE_KEY_SIGNED'
        run!('ASSET_SIGNATURE_VERIFY', 'codesign', '--verify', '--strict', '--verbose=0', binary)
        stages << 'SIGNATURE_VERIFIED'
        prefix = File.join(dir, 'certificate')
        run!('ASSET_SIGNED_CERT_PAIR', 'codesign', '-d', '--extract-certificates', prefix, binary)
        begin embedded = OpenSSL::X509::Certificate.new(File.binread(prefix + '0')); rescue StandardError; raise Failure.new('ASSET_SIGNED_CERT_PAIR'); end
        raise Failure.new('ASSET_SIGNED_CERT_PAIR') unless embedded.to_der == certificate.to_der
        stages << 'SIGNED_CERTIFICATE_MATCH'
      end
    end
  end
end
