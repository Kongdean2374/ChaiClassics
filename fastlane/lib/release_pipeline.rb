require 'json'
require 'shellwords'
require 'digest'
require_relative 'signing_config'
require_relative 'signing_asset_verifier'

module ChaiRelease
  FASTLANE_VERSION = '2.228.0'.freeze
  PHASES = %w[UPLOAD_AUTH BUILD_CONFIG ARCHIVE EXPORT_IPA UPLOAD_TRANSFER].freeze
  REASONS = %w[TOOL_VERSION EXPORT_METHOD_UNSUPPORTED GYM_OPTIONS_REJECTED IDENTITY_BINDING KEY_CONFIG APP_RECORD_MISSING BUILD_NUMBER_CONFLICT AUTH_REJECTED ACCESS_REJECTED RESOURCE_MISSING RATE_LIMITED APPLE_SERVER INPUT_REJECTED SIGNING_REJECTED COMMAND_FAILED ARCHIVE_BUILD_FAILED ARCHIVE_VERIFY_FAILED ARCHIVE_CONTENT_INVALID ARCHIVE_APP_INVALID ARCHIVE_CERT_EXTRACT ARCHIVE_CERT_MISMATCH ARCHIVE_PROFILE_MISMATCH IPA_MISSING TRANSFER_FAILED UNKNOWN PROCESS_INTERRUPTED].freeze
  HTTP_STATUSES = [400,401,403,404,409,422,429,500,501,502,503,504].freeze

  class Failure < StandardError
    attr_reader :phase, :reason, :http_status
    def initialize(phase, reason, http_status = nil)
      @phase = PHASES.include?(phase) ? phase : 'BUILD_CONFIG'
      @reason = REASONS.include?(reason) ? reason : 'UNKNOWN'
      @http_status = HTTP_STATUSES.include?(http_status) ? http_status : nil
      super("[CHAI_SIGNING:#{@phase}] #{@reason}")
    end
  end

  class Report
    def initialize(path: ENV['CHAI_RELEASE_REPORT_PATH'])
      @path = path
      @data = { 'schema' => 1, 'fastlane' => FASTLANE_VERSION, 'completed' => [],
                'phase' => nil, 'status' => 'running', 'reason' => nil, 'http_status' => nil }
    end

    def run(phase)
      raise Failure.new('BUILD_CONFIG', 'INPUT_REJECTED') unless PHASES[@data['completed'].length] == phase
      begin
        @data.merge!('phase' => phase, 'status' => 'running', 'reason' => nil, 'http_status' => nil)
        write
        result = yield
        @data['completed'] << phase
        @data['phase'] = nil
        @data['status'] = 'complete' if @data['completed'] == PHASES
        write
        result
      rescue StandardError => error
        safe = error.is_a?(Failure) ? Failure.new(phase, error.reason, error.http_status) : classify(phase, error)
        @data.merge!('phase' => safe.phase, 'status' => 'failed', 'reason' => safe.reason, 'http_status' => safe.http_status)
        write
        raise safe
      end
    end

    private
    def write
      return if @path.to_s.empty?
      File.open(@path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(JSON.generate(@data)) }
    end

    def classify(phase, error)
      # Inspect only scalar status fields and compare private text to fixed tokens.
      # No exception class, body, path, identifier or dynamic text leaves this file.
      status = error.status if error.respond_to?(:status)
      if status.nil? && error.respond_to?(:response)
        response = error.response
        status = response.status if response.respond_to?(:status)
        status ||= response[:status] if response.is_a?(Hash)
      end
      status = status.to_i if status.is_a?(String) && status.match?(/\A\d{3}\z/)
      status = nil unless status.is_a?(Integer)
      reason = {401 => 'AUTH_REJECTED', 403 => 'ACCESS_REJECTED', 404 => 'RESOURCE_MISSING', 429 => 'RATE_LIMITED'}[status]
      reason ||= 'APPLE_SERVER' if status.is_a?(Integer) && (500..599).cover?(status)
      text = error.message.to_s.downcase
      reason ||= if text.include?('[chai_signing:apple_key]')
                   'KEY_CONFIG'
                 elsif text.include?('create app store connect app record first')
                   'APP_RECORD_MISSING'
                 elsif text.include?('build number') || text.include?('build counter')
                   'BUILD_NUMBER_CONFLICT'
                 elsif text.include?('unsupported export_method')
                   'EXPORT_METHOD_UNSUPPORTED'
                 elsif text.include?('no profiles for') || text.include?('no signing certificate')
                   'SIGNING_REJECTED'
                 else
                   {'UPLOAD_AUTH' => 'UNKNOWN', 'BUILD_CONFIG' => 'GYM_OPTIONS_REJECTED', 'ARCHIVE' => 'COMMAND_FAILED', 'EXPORT_IPA' => 'COMMAND_FAILED', 'UPLOAD_TRANSFER' => 'TRANSFER_FAILED'}[phase]
                 end
      Failure.new(phase, reason, status)
    rescue StandardError
      Failure.new(phase, 'UNKNOWN')
    end
  end

  def self.build_options(root:, version:, number:, team:, profile_uuid:, identity:, certificate:, keychain:, workdir: ENV.fetch('CHAI_RELEASE_WORKDIR'))
    names = certificate.subject.to_a.select { |part| part[0] == 'CN' }.map { |part| part[1] }
    valid = names.length == 1 && names.first.match?(/\A(?:Apple Distribution|iPhone Distribution):/) &&
            identity.match?(/\A[A-Fa-f0-9]{40}\z/) && Digest::SHA1.hexdigest(certificate.to_der).casecmp?(identity)
    raise Failure.new('BUILD_CONFIG', 'IDENTITY_BINDING') unless valid
    flags = ['--keychain', keychain].shelljoin
    settings = { 'CHAI_SIGNING_TEAM' => team, 'CHAI_SIGNING_IDENTITY' => names.first,
                 'CHAI_SIGNING_PROFILE' => profile_uuid, 'CHAI_RELEASE_VERSION' => version,
                 'CHAI_BUILD_NUMBER' => number, 'CHAI_SIGNING_FLAGS' => flags }
    {
      project: File.join(root, 'ChaiClassics.xcodeproj'), scheme: 'ChaiClassics', configuration: 'Release',
      clean: true, archive_path: File.join(workdir, 'archive/ChaiClassics.xcarchive'),
      output_directory: File.join(workdir, 'export'), output_name: 'ChaiClassics.ipa',
      buildlog_path: File.join(workdir, 'logs'), derived_data_path: File.join(workdir, 'DerivedData'),
      export_method: 'app-store', skip_profile_detection: true, destination: 'generic/platform=iOS',
      xcargs: settings.map { |key,value| "#{key}=#{value}".shellescape }.join(' '),
      export_options: { method: 'app-store', destination: 'export', signingStyle: 'manual',
                        signingCertificate: identity, teamID: team, manageAppVersionAndBuildNumber: false,
                        provisioningProfiles: { ChaiSigning::APP_IDENTIFIER => profile_uuid } }
    }
  end

  def self.archive_options(options)
    options.merge(skip_package_ipa: true)
  end

  def self.export_options(options)
    options.merge(clean: false, skip_build_archive: true, skip_package_ipa: false)
  end

  def self.validate_options!(options)
    require 'gym'
    require 'fastlane/actions/build_app'
    raise Failure.new('BUILD_CONFIG', 'TOOL_VERSION') unless Fastlane::VERSION == FASTLANE_VERSION
    FastlaneCore::Configuration.create(Fastlane::Actions::BuildAppAction.available_options, options)
  rescue Failure
    raise
  rescue StandardError
    reason = options[:export_method] == 'app-store-connect' ? 'EXPORT_METHOD_UNSUPPORTED' : 'GYM_OPTIONS_REJECTED'
    raise Failure.new('BUILD_CONFIG', reason)
  end

  def self.read_archive_plist!(file, commands: ChaiSigningAssets::Commands.new)
    # xcarchive metadata contains Date values; native plist XML preserves types
    # which a JSON conversion cannot reliably represent.
    text, ok = commands.run('plutil', '-convert', 'xml1', '-o', '-', file)
    raise Failure.new('ARCHIVE', 'ARCHIVE_CONTENT_INVALID') unless ok
    data = Plist.parse_xml(text)
    raise Failure.new('ARCHIVE', 'ARCHIVE_CONTENT_INVALID') unless data.is_a?(Hash)
    data
  rescue Failure
    raise
  rescue StandardError
    raise Failure.new('ARCHIVE', 'ARCHIVE_CONTENT_INVALID')
  end

  def self.verify_archive!(path:, assets:, commands: ChaiSigningAssets::Commands.new, on_stage: ->(_) {})
    app = File.join(path, 'Products/Applications/ChaiClassics.app')
    raise Failure.new('ARCHIVE', 'ARCHIVE_CONTENT_INVALID') unless File.directory?(app)
    info = read_archive_plist!(File.join(path, 'Info.plist'), commands: commands)
    unless info['ArchiveVersion'] == 2 && info.dig('ApplicationProperties', 'ApplicationPath') == 'Applications/ChaiClassics.app'
      raise Failure.new('ARCHIVE', 'ARCHIVE_CONTENT_INVALID')
    end
    on_stage.call('ARCHIVE_FORMAT_VALID')
    app_info = read_archive_plist!(File.join(app, 'Info.plist'), commands: commands)
    unless app_info['CFBundleIdentifier'] == ChaiSigning::APP_IDENTIFIER && app_info['CFBundleSupportedPlatforms'].is_a?(Array) && app_info['CFBundleSupportedPlatforms'].include?('iPhoneOS')
      raise Failure.new('ARCHIVE', 'ARCHIVE_APP_INVALID')
    end
    on_stage.call('ARCHIVE_APP_VALID')
    _, ok = commands.run('codesign', '--verify', '--strict', '--verbose=0', app)
    raise Failure.new('ARCHIVE', 'SIGNING_REJECTED') unless ok
    on_stage.call('ARCHIVE_SIGNATURE_VALID')
    Dir.mktmpdir('chai-archive-certificate-') do |directory|
      embedded = ChaiSigningAssets.extract_signing_certificate!(app, directory, commands: commands)
      raise Failure.new('ARCHIVE', 'ARCHIVE_CERT_MISMATCH') unless embedded.to_der == assets.fetch(:certificate).to_der
    end
    on_stage.call('ARCHIVE_CERTIFICATE_MATCH')
    embedded_profile = File.join(app, 'embedded.mobileprovision')
    unless File.binread(embedded_profile) == File.binread(assets.fetch(:path))
      raise Failure.new('ARCHIVE', 'ARCHIVE_PROFILE_MISMATCH')
    end
    on_stage.call('ARCHIVE_PROFILE_MATCH')
  rescue Failure
    raise
  rescue ChaiSigningAssets::Failure
    raise Failure.new('ARCHIVE', 'ARCHIVE_CERT_EXTRACT')
  rescue StandardError
    raise Failure.new('ARCHIVE', 'ARCHIVE_CONTENT_INVALID')
  end

  def self.verify_ipa!(ipa, expected:)
    valid = ipa.is_a?(String) && File.file?(ipa) && File.size(ipa) > 0 && File.realpath(ipa) == File.realpath(expected)
    raise Failure.new('EXPORT_IPA', 'IPA_MISSING') unless valid
    ipa
  rescue Failure
    raise
  rescue StandardError
    raise Failure.new('EXPORT_IPA', 'IPA_MISSING')
  end
end
