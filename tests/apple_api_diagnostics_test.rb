require 'fastlane'
require 'spaceship'
require_relative '../fastlane/lib/signing_config'
require_relative '../fastlane/lib/apple_api_diagnostics'

Response = Struct.new(:code, :body)
def check(value, message)
  raise "Apple diagnostics assertion failed: #{message}" unless value
end

def client_for(resource, status, body, calls = [])
  transport = lambda do |uri, request|
    calls << uri
    check(uri.host == 'api.appstoreconnect.apple.com' && uri.scheme == 'https', 'fixed HTTPS host')
    check(request.method == 'GET', 'all probes must be read only')
    check(uri.path == '/v1/' + resource, 'exact resource route')
    check(URI.decode_www_form(uri.query).to_h['limit'] == '1', 'single-page request')
    Response.new(status.to_s, body)
  end
  ChaiAppleDiagnostics::Client.new(token_provider: -> { 'fixture-token-never-printed' }, app_identifier: ChaiSigning::APP_IDENTIFIER, transport: transport)
end

def failure_of
  yield
  raise 'Expected a safe diagnostic failure'
rescue ChaiAppleDiagnostics::Failure => error
  check(!error.message.include?('DO_NOT_PRINT'), 'no arbitrary response/exception strings')
  check(!JSON.generate(error.to_h).include?('DO_NOT_PRINT'), 'no sensitive structured fields')
  error
end

count = 0
{
  400 => 'INVALID_REQUEST', 401 => 'AUTHENTICATION', 403 => 'FORBIDDEN', 404 => 'NOT_FOUND',
  409 => 'INVALID_REQUEST', 429 => 'RATE_LIMIT', 500 => 'SERVER', 502 => 'SERVER', 503 => 'SERVER', 504 => 'SERVER', 302 => 'REDIRECT'
}.each do |status, category|
  %w[certificates profiles bundleIds].each do |resource|
    calls = []
    body = JSON.generate('errors' => [{ 'code' => 'DO_NOT_PRINT_TOKEN', 'detail' => 'DO_NOT_PRINT_PRIVATE_KEY', 'title' => 'forbidden' }])
    error = failure_of { client_for(resource, status, body, calls).read(resource) }
    check(error.status == status && error.resource == resource && error.category == category, 'status/resource classification')
    check(error.apple_code.nil?, 'unrecognized Apple error code not echoed')
    check(calls.length == 1, 'no automatic retries')
    count += 1
  end
end
body = JSON.generate('errors' => [{ 'code' => 'FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED', 'detail' => 'DO_NOT_PRINT' }])
error = failure_of { client_for('profiles', 403, body).read('profiles') }
check(error.category == 'AGREEMENTS' && error.status == 403, 'agreements distinct from roles')
['DO_NOT_PRINT_HTML', '{}', '{"errors":[{"detail":"DO_NOT_PRINT"}]}', '{"data":{}}', '{"data":[{"type":"wrong","attributes":{}}]}'].each do |body|
  error = failure_of { client_for('certificates', 200, body).read('certificates') }
  check(error.category == 'PROTOCOL' && error.status == 200, 'malformed 200 is not permission denied')
  count += 1
end

# Test the actual pinned fastlane JWT interface, never print the generated token.
pem = OpenSSL::PKey::EC.generate('prime256v1').private_to_pem
token = Spaceship::ConnectAPI::Token.create(key_id: 'A123456789', issuer_id: '01234567-0123-4567-89ab-0123456789ab', key: pem, in_house: false)
calls = []
transport = lambda do |uri, req|
  calls << uri.path
  check(req.method == 'GET' && req['Authorization'] == 'Bearer ' + token.text, 'pinned token interface')
  resource = uri.path.split('/').last
  if resource == 'bundleIds'
    check(URI.decode_www_form(uri.query).to_h['filter[identifier]'] == ChaiSigning::APP_IDENTIFIER, 'exact Bundle ID filter')
  end
  data = resource == 'bundleIds' ? [{ 'type' => resource, 'attributes' => { 'identifier' => ChaiSigning::APP_IDENTIFIER } }] : []
  Response.new('200', JSON.generate('data' => data, 'links' => { 'next' => 'https://example.invalid/DO_NOT_PRINT_TOKEN' }))
end
client = ChaiAppleDiagnostics::Client.new(token_provider: -> { token.text }, app_identifier: ChaiSigning::APP_IDENTIFIER, transport: transport)
reports = []
check(ChaiAppleDiagnostics.verify!(client: client, team_id: 'T123456789', reporter: ->(r) { reports << r }), 'read-only checks succeed')
check(calls == %w[/v1/certificates /v1/profiles /v1/bundleIds], 'exactly one GET per resource; no pagination')
check(reports.last['checks'].length == 3 && reports.last['failure'].nil?, 'safe success report')
count += 1

# Preserve the first failing resource and successful predecessors; stop before match.
calls = []
client = ChaiAppleDiagnostics::Client.new(token_provider: -> { 'fixture' }, app_identifier: ChaiSigning::APP_IDENTIFIER,
  transport: lambda { |uri, _|
    calls << uri.path
    uri.path.end_with?('profiles') ? Response.new('429', 'DO_NOT_PRINT') : Response.new('200', '{"data":[]}')
  })
reports = []
error = failure_of { ChaiAppleDiagnostics.verify!(client: client, team_id: 'T123456789', reporter: ->(r) { reports << r }) }
check(error.resource == 'profiles' && error.status == 429 && reports.last['checks'].length == 1 && calls.length == 2, 'partial report and fail closed')
count += 1

# Legacy SDK exceptions with no preserved status must never become an auth diagnosis.
client = ChaiAppleDiagnostics::Client.new(token_provider: -> { raise Spaceship::UnexpectedResponse, 'forbidden DO_NOT_PRINT' }, app_identifier: ChaiSigning::APP_IDENTIFIER)
error = failure_of { client.read('certificates') }
check(error.status.nil? && error.category == 'UNKNOWN', 'UnexpectedResponse is not automatically a 403')
count += 1

{ SocketError => 'NETWORK', Net::ReadTimeout => 'NETWORK', OpenSSL::SSL::SSLError => 'TLS', NoMethodError => 'CLIENT_COMPATIBILITY' }.each do |klass, category|
  client = ChaiAppleDiagnostics::Client.new(token_provider: -> { 'fixture' }, app_identifier: ChaiSigning::APP_IDENTIFIER,
    transport: ->(_, _) { raise klass, 'DO_NOT_PRINT' })
  error = failure_of { client.read('profiles') }
  check(error.category == category && error.status.nil?, 'transport/client errors not permission errors')
  count += 1
end

# Verify existing team / Bundle ID safety checks remain in force.
%w[missing_bundle wrong_team invalid_certificate].each do |scenario|
  key = OpenSSL::PKey::EC.generate('prime256v1')
  certificate = OpenSSL::X509::Certificate.new
  certificate.version = 2; certificate.serial = 1
  certificate.subject = OpenSSL::X509::Name.parse('/CN=Fixture/OU=T000000000')
  certificate.issuer = certificate.subject
  certificate.public_key = key
  certificate.not_before = Time.now - 60; certificate.not_after = Time.now + 60
  certificate.sign(key, OpenSSL::Digest::SHA256.new)
  transport = lambda do |uri, _|
    resource = uri.path.split('/').last
    data = []
    data = [{ 'type' => 'bundleIds', 'attributes' => { 'identifier' => ChaiSigning::APP_IDENTIFIER } }] if resource == 'bundleIds' && scenario != 'missing_bundle'
    if resource == 'certificates' && scenario != 'missing_bundle'
      content = scenario == 'invalid_certificate' ? 'DO_NOT_PRINT' : Base64.strict_encode64(certificate.to_der)
      data = [{ 'type' => 'certificates', 'attributes' => { 'certificateContent' => content } }]
    end
    Response.new('200', JSON.generate('data' => data))
  end
  client = ChaiAppleDiagnostics::Client.new(token_provider: -> { 'fixture' }, app_identifier: ChaiSigning::APP_IDENTIFIER, transport: transport)
  error = failure_of { ChaiAppleDiagnostics.verify!(client: client, team_id: 'T123456789', reporter: ->(_) {}) }
  expected = { 'missing_bundle' => 'BUNDLE_ID_MISSING', 'wrong_team' => 'TEAM_MISMATCH', 'invalid_certificate' => 'CERTIFICATE_DATA' }[scenario]
  check(error.category == expected && error.status == 200, 'team/Bundle ID/data validation preserved')
  count += 1
end
puts "PASS: #{count} read-only Apple HTTP/resource, pinned-SDK, protocol, transport, legacy-exception and security cases; no Apple requests or real credentials used."
