#!/usr/bin/env ruby
# Read-only App Store Connect status for one exact build. No match or upload API.
require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'
require_relative '../fastlane/lib/signing_config'

module ChaiTestFlightStatus
  PROCESSING = %w[PROCESSING FAILED INVALID VALID].freeze
  INTERNAL = %w[PROCESSING PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE READY_FOR_BETA_TESTING IN_BETA_TESTING EXPIRED IN_EXPORT_COMPLIANCE_REVIEW].freeze
  EXTERNAL = %w[PROCESSING PROCESSING_EXCEPTION MISSING_EXPORT_COMPLIANCE READY_FOR_BETA_SUBMISSION IN_BETA_REVIEW BETA_REJECTED BETA_APPROVED READY_FOR_BETA_TESTING IN_BETA_TESTING EXPIRED IN_EXPORT_COMPLIANCE_REVIEW].freeze
  REVIEW = %w[WAITING_FOR_REVIEW IN_REVIEW REJECTED APPROVED].freeze
  class Failure < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super('Apple read-only status check failed [' + code + ']; response and credentials suppressed.')
    end
  end

  def self.check(condition, code)
    raise Failure.new(code) unless condition
  end

  def self.base64(data)
    Base64.urlsafe_encode64(data, padding: false)
  end

  def self.jwt(env, now: Time.now.to_i)
    options = ChaiSigning.api_key_options(env)
    check(options[:key_id].match?(/\A[A-Z0-9]{10}\z/) && options[:issuer_id].match?(/\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z/), 'KEY_CONFIG')
    header = base64(JSON.generate(alg: 'ES256', kid: options[:key_id], typ: 'JWT'))
    payload = base64(JSON.generate(iss: options[:issuer_id], iat: now - 20, exp: now + 600, aud: 'appstoreconnect-v1'))
    message = header + '.' + payload
    key = OpenSSL::PKey.read(options[:key_content])
    der = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(message))
    integers = OpenSSL::ASN1.decode(der).value
    signature = integers.map { |integer| integer.value.to_s(2).rjust(32, "\x00") }.join
    check(signature.bytesize == 64, 'KEY_CONFIG')
    message + '.' + base64(signature)
  rescue KeyError, ArgumentError, OpenSSL::OpenSSLError
    raise Failure.new('KEY_CONFIG')
  end

  class Client
    def initialize(token, transport: nil)
      @token = token
      @transport = transport || lambda do |uri, request|
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 30) { |http| http.request(request) }
      end
    end

    def read(path, params = {})
      ChaiTestFlightStatus.check(path.match?(/\A\/v1\/[A-Za-z0-9\/-]+\z/), 'REQUEST_PATH')
      uri = URI('https://api.appstoreconnect.apple.com' + path)
      uri.query = URI.encode_www_form(params) unless params.empty?
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = 'Bearer ' + @token
      request['Accept'] = 'application/json'
      response = @transport.call(uri, request)
      code = response.code.to_i
      # Redirects are refused; the JWT is never forwarded to another host.
      ChaiTestFlightStatus.check(code == 200, { 401 => 'AUTHENTICATION', 403 => 'FORBIDDEN', 429 => 'RATE_LIMIT' }.fetch(code, 'HTTP_FAILURE'))
      ChaiTestFlightStatus.check(response.body.bytesize <= 1_048_576, 'RESPONSE_SIZE')
      data = JSON.parse(response.body)
      ChaiTestFlightStatus.check(data.is_a?(Hash) && !data.dig('links', 'next'), 'RESPONSE_SCHEMA')
      data
    rescue JSON::ParserError, TypeError
      raise Failure.new('RESPONSE_SCHEMA')
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
      raise Failure.new('NETWORK')
    end
  end

  def self.related(response, build, relationship, type)
    reference = build.dig('relationships', relationship, 'data')
    return {} unless reference.is_a?(Hash) && reference['type'] == type
    entries = response.fetch('included', [])
    check(entries.is_a?(Array), 'RESPONSE_SCHEMA')
    found = entries.select { |entry| entry.is_a?(Hash) && entry['type'] == type && entry['id'] == reference['id'] }
    check(found.length <= 1, 'RESPONSE_SCHEMA')
    found.first&.fetch('attributes', {}) || {}
  end

  def self.inspect_build(client:, version:, number:, commit:, now: Time.now.utc)
    check(version.match?(/\A\d+\.\d+\.\d+\z/) && number.match?(/\A\d+(?:\.\d+){0,2}\z/) && commit.match?(/\A[0-9a-f]{40}\z/), 'INPUT')
    apps = client.read('/v1/apps', 'filter[bundleId]' => ChaiSigning::APP_IDENTIFIER, 'limit' => '2').fetch('data', [])
    check(apps.is_a?(Array) && apps.length == 1 && apps[0].dig('attributes', 'bundleId') == ChaiSigning::APP_IDENTIFIER, 'APP_RECORD')
    id = apps[0]['id']
    check(id.is_a?(String) && id.match?(/\A[A-Za-z0-9-]+\z/), 'RESPONSE_SCHEMA')
    response = client.read('/v1/builds', 'filter[app]' => id, 'filter[version]' => number,
                           'include' => 'preReleaseVersion,buildBetaDetail,betaAppReviewSubmission', 'limit' => '2')
    builds = response.fetch('data', [])
    check(builds.is_a?(Array) && builds.length <= 1, 'BUILD_RECORD')
    report = { 'schema' => 1, 'version' => version, 'build_number' => number, 'source_commit' => commit,
               'checked_at' => now.iso8601, 'upload_received' => !builds.empty?, 'processing_state' => 'NOT_FOUND',
               'processing_complete' => false, 'internal_state' => 'UNKNOWN', 'internal_ready' => false,
               'external_state' => 'UNKNOWN', 'external_review_state' => 'UNKNOWN',
               'source_commit_verified' => false, 'status' => 'pending' }
    return report if builds.empty?
    build = builds.first
    attrs = build.fetch('attributes', {})
    check(build['type'] == 'builds' && attrs['version'] == number, 'BUILD_RECORD')
    prerelease = related(response, build, 'preReleaseVersion', 'preReleaseVersions')
    check(prerelease['version'] == version, 'VERSION_MISMATCH')
    processing = attrs['processingState']
    report['processing_state'] = PROCESSING.include?(processing) ? processing : 'UNKNOWN'
    report['processing_complete'] = processing == 'VALID'
    beta = related(response, build, 'buildBetaDetail', 'buildBetaDetails')
    internal = beta['internalBuildState']; external = beta['externalBuildState']
    report['internal_state'] = INTERNAL.include?(internal) ? internal : 'UNKNOWN'
    report['external_state'] = EXTERNAL.include?(external) ? external : 'UNKNOWN'
    review = related(response, build, 'betaAppReviewSubmission', 'betaAppReviewSubmissions')['betaReviewState']
    report['external_review_state'] = REVIEW.include?(review) ? review : 'UNKNOWN'
    report['internal_ready'] = processing == 'VALID' && %w[READY_FOR_BETA_TESTING IN_BETA_TESTING].include?(internal) && attrs['expired'] == false
    build_id = build['id']
    check(build_id.is_a?(String) && build_id.match?(/\A[A-Za-z0-9-]+\z/), 'BUILD_RECORD')
    localizations = client.read('/v1/builds/' + build_id + '/betaBuildLocalizations', 'limit' => '50').fetch('data', [])
    check(localizations.is_a?(Array), 'RESPONSE_SCHEMA')
    commits = localizations.flat_map do |entry|
      notes = entry.dig('attributes', 'whatsNew')
      notes.is_a?(String) ? notes.scan(/\bCommit ([0-9a-f]{40}) \| run [0-9]+, attempt [0-9]+\b/).flatten : []
    end.uniq
    report['source_commit_verified'] = commits == [commit]
    report['status'] = 'ready' if report['internal_ready'] && report['source_commit_verified']
    report
  rescue KeyError, NoMethodError, TypeError
    raise Failure.new('RESPONSE_SCHEMA')
  end

  def self.main(env = ENV)
    check(env['GITHUB_EVENT_NAME'] == 'workflow_dispatch' && env['GITHUB_REF'] == 'refs/heads/main', 'TRUSTED_DISPATCH')
    result = inspect_build(client: Client.new(jwt(env)), version: env.fetch('RELEASE_VERSION'),
                           number: env.fetch('TESTED_BUILD_NUMBER'), commit: env.fetch('TESTED_COMMIT'))
    output = File.expand_path('../build/testflight-status.json', __dir__)
    require 'fileutils'
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, JSON.pretty_generate(result) + "\n")
    puts JSON.generate(result)
    result['status'] == 'ready' ? 0 : 2
  rescue Failure => error
    warn error.message
    1
  rescue StandardError
    warn 'Apple read-only status check failed [CLIENT_FAILURE]; response and credentials suppressed.'
    1
  end
end

exit ChaiTestFlightStatus.main if $PROGRAM_NAME == __FILE__
