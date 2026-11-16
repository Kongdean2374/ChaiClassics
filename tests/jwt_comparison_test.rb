require 'fastlane'
require 'spaceship'
require_relative '../fastlane/lib/signing_config'
require_relative '../fastlane/lib/apple_api_diagnostics'

PairResponse = Struct.new(:code, :body)
def assert_check(value, name)
  raise "JWT comparison assertion failed: #{name}" unless value
end

now = Time.now.to_i
key = OpenSSL::PKey::EC.generate('prime256v1')
key_id = 'A123456789'
issuer = '01234567-0123-4567-89ab-0123456789ab'
header = { 'kid' => key_id, 'typ' => 'JWT' }
claims = { 'iss' => issuer, 'aud' => 'appstoreconnect-v1', 'iat' => now - 60, 'exp' => now + 500 }
token = JWT.encode(claims, key, 'ES256', header)
audit = ->(jwt) { ChaiAppleJWT.check(token: jwt, key_id: key_id, issuer_id: issuer, verification_key: key, now: now) }
assert_check(audit.call(token).values.all?, 'valid Team JWT fields and signature')
count = 1

# Every assertion is boolean: failure logs never dump a fixture token/key/claim.
{
  'iss' => claims.merge('iss' => '11111111-1111-1111-1111-111111111111'),
  'aud' => claims.merge('aud' => 'apple-developer-enterprise-v1'),
  'iat' => claims.merge('iat' => now + 1),
  'exp' => claims.merge('exp' => now - 1)
}.each do |field, payload|
  jwt = JWT.encode(payload, key, 'ES256', header)
  result = audit.call(jwt)
  assert_check(result[field] == false && result.values.all? { |value| value == true || value == false }, 'invalid claim flagged without values')
  count += 1
end
[
  claims.merge('iat' => (now - 60).to_s),
  claims.merge('exp' => (now + 500).to_s),
  claims.merge('exp' => now + 1200), # Fastlane backdates iat, making lifetime 1260.
  claims.merge('iat' => now - 2000, 'exp' => now + 1),
  claims.reject { |name,_| name == 'exp' },
  claims.reject { |name,_| name == 'iss' }
].each do |payload|
  assert_check(!audit.call(JWT.encode(payload, key, 'ES256', header)).values.all?, 'types, lifetime and mandatory claims checked')
  count += 1
end
wrong_kid = JWT.encode(claims, key, 'ES256', header.merge('kid' => 'B123456789'))
assert_check(!audit.call(wrong_kid)['kid'], 'kid matches configured key ID')
count += 1
wrong_alg = JWT.encode(claims, 'fixture-hmac-not-real-' * 4, 'HS256', header)
assert_check(!audit.call(wrong_alg)['alg'] && !audit.call(wrong_alg)['signature'], 'ES256 only; no algorithm confusion')
count += 1
other_key = OpenSSL::PKey::EC.generate('prime256v1')
wrong_signature = JWT.encode(claims, other_key, 'ES256', header)
assert_check(!audit.call(wrong_signature)['signature'], 'signature checked with configured p8 public key')
count += 1
['DO_NOT_PRINT_INVALID_JWT', 'x.y.z', token + '.extra'].each do |invalid|
  result = audit.call(invalid)
  assert_check(!result.values.all? && !JSON.generate(result).include?('DO_NOT_PRINT'), 'invalid structure never echoed')
  count += 1
end

# Use the pinned SDK-generated JWT as the exact same byte string for both GETs.
sdk = Spaceship::ConnectAPI::Token.create(key_id: key_id, issuer_id: issuer, key: key.private_to_pem, in_house: false)
pairs = {
  [200,200] => 'AUTHENTICATED_BOTH',
  [401,401] => 'JWT_AUTHENTICATION_REJECTED',
  [200,401] => 'CERTIFICATES_AUTHENTICATION_REJECTED',
  [200,403] => 'CERTIFICATES_ACCESS_DENIED',
  [200,429] => 'CERTIFICATES_API_FAILED',
  [200,503] => 'CERTIFICATES_API_FAILED',
  [401,200] => 'APPS_AUTHENTICATION_REJECTED',
  [403,200] => 'APPS_ACCESS_DENIED',
  [503,200] => 'APPS_API_FAILED',
  [401,503] => 'INCONCLUSIVE',
  [403,403] => 'INCONCLUSIVE'
}
pairs.each do |statuses, expected|
  requests = []; reports = []
  jwt = sdk.text.dup.freeze
  transport = lambda do |uri, request|
    i = requests.length
    requests << request
    resource = i.zero? ? 'apps' : 'certificates'
    assert_check(uri.host == 'api.appstoreconnect.apple.com' && uri.path == '/v1/' + resource && uri.query == 'limit=1', 'two exact read-only routes')
    assert_check(request.method == 'GET', 'no resource writes')
    status = statuses[i]
    body = status == 200 ? { 'data' => [] } : { 'errors' => [{ 'code' => 'NOT_AUTHORIZED', 'detail' => 'DO_NOT_PRINT' }] }
    PairResponse.new(status.to_s, JSON.generate(body))
  end
  success = ChaiAppleDiagnostics.compare_authentication!(token: jwt, key_id: key_id, issuer_id: issuer, verification_key: key,
    transport: transport, reporter: ->(report) { reports << report })
  assert_check(requests.length == 2, 'first failure never suppresses second API')
  assert_check(requests[0]['Authorization'] == requests[1]['Authorization'] && requests[0]['Authorization'] == 'Bearer ' + jwt, 'identical JWT bytes in both calls')
  report = reports.last
  assert_check(report['schema'] == 2 && report['jwt'].values.all? && report['conclusion'] == expected, 'paired conclusion')
  assert_check(report['results'].map { |result| result['status'] } == statuses, 'both HTTP statuses reported')
  assert_check(success == (expected == 'AUTHENTICATED_BOTH'), 'non-success exits fail closed after collecting both results')
  assert_check(!JSON.generate(report).include?(key_id) && !JSON.generate(report).include?(issuer) && !JSON.generate(report).include?(jwt) && !JSON.generate(report).include?('DO_NOT_PRINT'), 'no token, identifiers, keys or raw response in report')
  count += 1
end

requests = []; reports = []
transport = ->(uri, req) { requests << req; raise Net::ReadTimeout, 'DO_NOT_PRINT' }
ChaiAppleDiagnostics.compare_authentication!(token: token, key_id: key_id, issuer_id: issuer, verification_key: key,
  transport: transport, now: now, reporter: ->(report) { reports << report })
assert_check(requests.length == 2 && reports.last['conclusion'] == 'INCONCLUSIVE', 'network failures are not global JWT rejection')
count += 1
puts "PASS: #{count} JWT field/signature, same-token dual-API, independent status and no-secret comparison cases; no Apple requests."
