require 'net/http'
require 'uri'
require 'json'
require 'base64'
require 'openssl'

# Deliberately independent of Spaceship's HTTP error formatter, which can discard
# status and put arbitrary Apple response text into UnexpectedResponse.message.
module ChaiAppleDiagnostics
  RESOURCES = %w[certificates profiles bundleIds authentication].freeze
  CATEGORIES = %w[AUTHENTICATION FORBIDDEN AGREEMENTS NOT_FOUND RATE_LIMIT SERVER INVALID_REQUEST REDIRECT PROTOCOL NETWORK TLS CLIENT_COMPATIBILITY TEAM_MISMATCH BUNDLE_ID_MISSING CERTIFICATE_DATA UNKNOWN].freeze
  APPLE_CODES = %w[FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED PARAMETER_ERROR.INVALID PARAMETER_ERROR.UNKNOWN NOT_FOUND NOT_AUTHORIZED RATE_LIMIT_EXCEEDED].freeze

  class Failure < StandardError
    attr_reader :resource, :status, :category, :apple_code
    def initialize(resource:, category:, status: nil, apple_code: nil)
      @resource = RESOURCES.include?(resource) ? resource : 'authentication'
      @category = CATEGORIES.include?(category) ? category : 'UNKNOWN'
      @status = status.is_a?(Integer) && (100..599).cover?(status) ? status : nil
      @apple_code = APPLE_CODES.include?(apple_code) ? apple_code : nil
      super("Apple API check failed: resource=#{@resource} HTTP=#{@status || 'unknown'} category=#{@category}")
    end
    def to_h
      { 'resource' => resource, 'status' => status, 'category' => category, 'apple_code' => apple_code }
    end
  end

  class Client
    HOST = 'api.appstoreconnect.apple.com'.freeze
    def initialize(token_provider:, app_identifier:, transport: nil)
      @token_provider = token_provider
      @app_identifier = app_identifier
      @transport = transport || method(:request)
    end

    # Three fixed GET routes, one page each. Never follow pagination/redirect links,
    # mutate resources, refresh/reissue keys, or retry Apple errors automatically.
    def read(resource)
      raise Failure.new(resource: 'authentication', category: 'CLIENT_COMPATIBILITY') unless %w[certificates profiles bundleIds].include?(resource)
      params = { 'limit' => '1' }
      params['filter[identifier]'] = @app_identifier if resource == 'bundleIds'
      uri = URI::HTTPS.build(host: HOST, path: "/v1/#{resource}", query: URI.encode_www_form(params))
      req = Net::HTTP::Get.new(uri)
      req['Accept'] = 'application/json'
      token = @token_provider.call
      unless token.is_a?(String) && !token.empty? && !token.match?(/[\r\n]/)
        raise Failure.new(resource: 'authentication', category: 'CLIENT_COMPATIBILITY')
      end
      req['Authorization'] = "Bearer #{token}"
      response = @transport.call(uri, req)
      status = response.code.to_s.match?(/\A[1-5][0-9]{2}\z/) ? response.code.to_i : nil
      body = begin JSON.parse(response.body.to_s); rescue JSON::ParserError; nil; end
      error_code = if body.is_a?(Hash) && body['errors'].is_a?(Array)
                     body['errors'].filter_map { |error| error['code'] if error.is_a?(Hash) }.find { |code| APPLE_CODES.include?(code) }
                   end
      if status != 200
        category = case status
                   when 401 then 'AUTHENTICATION'
                   when 403 then error_code == 'FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED' ? 'AGREEMENTS' : 'FORBIDDEN'
                   when 404 then 'NOT_FOUND'
                   when 429 then 'RATE_LIMIT'
                   when 500..599 then 'SERVER'
                   when 400..499 then 'INVALID_REQUEST'
                   when 300..399 then 'REDIRECT'
                   else 'PROTOCOL'
                   end
        raise Failure.new(resource: resource, category: category, status: status, apple_code: error_code)
      end
      unless body.is_a?(Hash) && !body.key?('errors') && body['data'].is_a?(Array) && body['data'].all? { |item| item.is_a?(Hash) && item['type'] == resource && item['attributes'].is_a?(Hash) }
        raise Failure.new(resource: resource, category: 'PROTOCOL', status: status)
      end
      body['data']
    rescue Failure
      raise
    rescue OpenSSL::SSL::SSLError
      raise Failure.new(resource: resource, category: 'TLS')
    rescue Timeout::Error, SocketError, IOError, SystemCallError
      raise Failure.new(resource: resource, category: 'NETWORK')
    rescue NoMethodError, ArgumentError, TypeError
      raise Failure.new(resource: resource, category: 'CLIENT_COMPATIBILITY')
    rescue StandardError
      # Unknown errors are NOT evidence of insufficient Apple privileges.
      raise Failure.new(resource: resource, category: 'UNKNOWN')
    end

    private
    def request(uri, req)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
                     open_timeout: 20, read_timeout: 30) { |http| http.request(req) }
    end
  end

  def self.report(result)
    path = ENV['CHAI_APPLE_DIAGNOSTIC_PATH']
    return unless path && !path.empty?
    # Only our fixed schema/enums are supplied. Never serialize response/request,
    # exception.message, headers, certificate data, JWTs, keys or identifiers.
    File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(JSON.generate(result)) }
  end

  def self.verify!(client:, team_id:, reporter: method(:report))
    checks = []
    certificates = nil
    ids = nil
    %w[certificates profiles bundleIds].each do |resource|
      result = client.read(resource)
      checks << { 'resource' => resource, 'status' => 200 }
      certificates = result if resource == 'certificates'
      ids = result if resource == 'bundleIds'
    end
    unless ids.any? { |item| item.dig('attributes', 'identifier') == ChaiSigning::APP_IDENTIFIER }
      raise Failure.new(resource: 'bundleIds', category: 'BUNDLE_ID_MISSING', status: 200)
    end
    certificates.each do |item|
      content = item.dig('attributes', 'certificateContent')
      next if content.to_s.empty?
      begin
        cert = OpenSSL::X509::Certificate.new(Base64.strict_decode64(content.delete("\r\n")))
      rescue OpenSSL::X509::CertificateError, ArgumentError
        raise Failure.new(resource: 'certificates', category: 'CERTIFICATE_DATA', status: 200)
      end
      team = cert.subject.to_a.find { |part| part[0] == 'OU' }&.at(1)
      if team && team != team_id
        raise Failure.new(resource: 'certificates', category: 'TEAM_MISMATCH', status: 200)
      end
    end
    reporter.call({ 'schema' => 1, 'checks' => checks, 'failure' => nil })
    true
  rescue Failure => error
    reporter.call({ 'schema' => 1, 'checks' => checks, 'failure' => error.to_h })
    raise
  end
end
