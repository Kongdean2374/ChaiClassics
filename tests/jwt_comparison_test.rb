require 'fastlane'
require 'spaceship'
require_relative '../fastlane/lib/signing_config'
require_relative '../fastlane/lib/apple_api_diagnostics'

PairResponse = Struct.new(:code, :body)
def assert_check(value, name)
  raise "JWT comparison assertion failed: #{name}" unless value
end

# Test-only fixture encoder: jwt 2.10.3 correctly rejects non-Numeric iat/exp
# during JWT.encode. Build compact JWS directly so malformed claim types can
# reach the production validator without weakening it or changing valid JWTs.
def negative_claim_fixture(payload, key, header)
  encoded_header = Base64.urlsafe_encode64(JSON.generate(header.merge('alg' => 'ES256')), padding: false)
  encoded_payload = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
  input = encoded_header + '.' + encoded_payload
  der = OpenSSL::ASN1.decode(key.sign('SHA256', input))
  components = der.value.map { |integer| integer.value.to_s(16).rjust(64, '0') }
  assert_check(components.length == 2 && components.all? { |hex| hex.length == 64 }, 'fixture P-256 signature widths')
  raw_signature = components.map { |hex| [hex].pack('H*') }.join
  fixture = input + '.' + Base64.urlsafe_encode64(raw_signature, padding: false)

  # Independently reconstruct DER from the fixture bytes and verify its public
  # signature. A bad-claim test must not pass just because its JWT is malformed
  # or has a broken signature. Assertions never print claims, keys or tokens.
  parts = fixture.split('.')
  signature = Base64.urlsafe_decode64(parts.fetch(2))
  assert_check(signature.bytesize == 64, 'fixture has a complete ES256 signature')
  numbers = [signature.byteslice(0, 32), signature.byteslice(32, 32)].map do |bytes|
    OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(bytes, 2))
  end
  reconstructed_der = OpenSSL::ASN1::Sequence.new(numbers).to_der
  public_key = OpenSSL::PKey.read(key.public_to_pem)
  assert_check(public_key.verify('SHA256', reconstructed_der, parts.first(2).join('.')), 'negative fixture signature is cryptographically valid')
  decoded_payload = JSON.parse(Base64.urlsafe_decode64(parts.fetch(1)))
  assert_check(decoded_payload == payload, 'fixture preserves invalid claim values and types')
  fixture
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
  ['iat', claims.merge('iat' => (now - 60).to_s)],
  ['exp', claims.merge('exp' => (now + 500).to_s)],
  ['exp', claims.merge('exp' => now + 1200)], # Backdated iat makes lifetime 1260.
  ['exp', claims.merge('iat' => now - 2000, 'exp' => now + 1)],
  ['exp', claims.reject { |name,_| name == 'exp' }],
  ['iss', claims.reject { |name,_| name == 'iss' }]
].each do |field, payload|
  fixture = negative_claim_fixture(payload, key, header)
  result = audit.call(fixture)
  assert_check(%w[structure alg kid aud signature].all? { |name| result[name] == true }, 'negative fixture reaches claim validation with valid structure and signature')
  assert_check(result[field] == false && !result.values.all?, 'specific invalid type, lifetime or missing claim is rejected')
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
