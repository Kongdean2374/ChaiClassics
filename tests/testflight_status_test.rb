# Standard-library-only tests. Fixtures never contact Apple or use a real key.
require 'stringio'
require_relative '../scripts/testflight_status'

def check(condition, message)
  raise 'TestFlight read-only status assertion failed: ' + message unless condition
end

def failure(code)
  yield
  raise 'Expected safe status failure: ' + code
rescue ChaiTestFlightStatus::Failure => error
  check(error.code == code, 'fixed failure category ' + code)
  check(!error.message.include?('DO_NOT_PRINT'), 'no raw response values')
end

Response = Struct.new(:code, :body)
[200, 301, 401, 403, 429, 500].each do |status|
  transport = lambda do |uri, request|
    check(uri.scheme == 'https' && uri.host == 'api.appstoreconnect.apple.com', 'fixed TLS host')
    check(request.method == 'GET', 'only GET is issued')
    check(request['Authorization'] == 'Bearer fixture-token', 'authorization stays on the fixed Apple request')
    Response.new(status.to_s, status == 200 ? '{"data":[]}' : 'DO_NOT_PRINT')
  end
  client = ChaiTestFlightStatus::Client.new('fixture-token', transport: transport)
  if status == 200
    check(client.read('/v1/apps')['data'] == [], 'safe JSON response')
  else
    failure({401 => 'AUTHENTICATION', 403 => 'FORBIDDEN', 429 => 'RATE_LIMIT'}.fetch(status, 'HTTP_FAILURE')) { client.read('/v1/apps') }
  end
end
failure('REQUEST_PATH') { ChaiTestFlightStatus::Client.new('fixture-token').read('https://other.example/DO_NOT_PRINT') }
failure('RESPONSE_SCHEMA') do
  ChaiTestFlightStatus::Client.new('fixture-token', transport: ->(*) { Response.new('200', '{"links":{"next":"DO_NOT_PRINT"}}') }).read('/v1/apps')
end

key = OpenSSL::PKey::EC.generate('prime256v1')
env = {'ASC_KEY_ID' => 'A123456789', 'ASC_ISSUER_ID' => '12345678-1234-1234-1234-123456789012', 'ASC_API_KEY_P8' => key.private_to_pem}
token = ChaiTestFlightStatus.jwt(env, now: 1_800_000_000)
header, payload, signature = token.split('.')
decode = ->(part) { Base64.urlsafe_decode64(part) }
check(JSON.parse(decode.call(header)) == {'alg' => 'ES256', 'kid' => 'A123456789', 'typ' => 'JWT'}, 'ES256 header')
claims = JSON.parse(decode.call(payload))
check(claims['iat'] == 1_799_999_980 && claims['exp'] == 1_800_000_600 && claims['aud'] == 'appstoreconnect-v1', 'bounded JWT lifetime and Apple audience')
raw = decode.call(signature)
check(raw.bytesize == 64, 'JOSE signature is two 32-byte integers')
integers = [raw.byteslice(0, 32), raw.byteslice(32, 32)].map { |part| OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(part, 2)) }
der = OpenSSL::ASN1::Sequence.new(integers).to_der
check(key.dsa_verify_asn1(OpenSSL::Digest::SHA256.digest(header + '.' + payload), der), 'JWT signature independently verifies')
failure('KEY_CONFIG') { ChaiTestFlightStatus.jwt(env.merge('ASC_API_KEY_P8' => 'DO_NOT_PRINT')) }

class FixtureClient
  attr_reader :calls
  def initialize(processing: 'VALID', internal: 'READY_FOR_BETA_TESTING', external: 'IN_BETA_REVIEW', review: 'IN_REVIEW', expired: false, commit: 'a' * 40, version: '0.2.0', missing: false)
    @calls = []
    @responses = {
      '/v1/apps' => {'data' => [{'id' => '1234', 'attributes' => {'bundleId' => 'cc.chaihome.chaiclassics'}}]},
      '/v1/builds' => {'data' => missing ? [] : [{
        'type' => 'builds', 'id' => 'build-123', 'attributes' => {'version' => '123.0.1', 'processingState' => processing, 'expired' => expired},
        'relationships' => {
          'preReleaseVersion' => {'data' => {'type' => 'preReleaseVersions', 'id' => 'version-123'}},
          'buildBetaDetail' => {'data' => {'type' => 'buildBetaDetails', 'id' => 'beta-123'}},
          'betaAppReviewSubmission' => {'data' => {'type' => 'betaAppReviewSubmissions', 'id' => 'review-123'}}
        }
      }], 'included' => [
        {'type' => 'preReleaseVersions', 'id' => 'version-123', 'attributes' => {'version' => version}},
        {'type' => 'buildBetaDetails', 'id' => 'beta-123', 'attributes' => {'internalBuildState' => internal, 'externalBuildState' => external}},
        {'type' => 'betaAppReviewSubmissions', 'id' => 'review-123', 'attributes' => {'betaReviewState' => review}}
      ]},
      '/v1/builds/build-123/betaBuildLocalizations' => {'data' => [{'attributes' => {'whatsNew' => "Commit #{commit} | run 123456, attempt 1"}}]}
    }
  end
  def read(path, params = {})
    @calls << [path, params]
    Marshal.load(Marshal.dump(@responses.fetch(path)))
  end
end

def inspect_fixture(**options)
  client = FixtureClient.new(**options)
  report = ChaiTestFlightStatus.inspect_build(client: client, version: '0.2.0', number: '123.0.1', commit: 'a' * 40, now: Time.utc(2026, 11, 17))
  check(client.calls[1][1]['filter[version]'] == '123.0.1', 'exact build-number filter')
  report
end

ready = inspect_fixture
check(ready['status'] == 'ready' && ready['upload_received'] && ready['processing_complete'] && ready['internal_ready'], 'received, processed and internal-ready are separately true')
check(ready['external_review_state'] == 'IN_REVIEW' && ready['external_state'] == 'IN_BETA_REVIEW', 'internal readiness does not claim external approval')
check(ready['source_commit_verified'], 'uploaded notes independently match the expected source SHA')
pending = inspect_fixture(processing: 'PROCESSING', internal: 'PROCESSING', external: 'PROCESSING', review: nil)
check(pending['upload_received'] && !pending['processing_complete'] && !pending['internal_ready'] && pending['status'] == 'pending', 'upload received is not processing completion')
check(inspect_fixture(missing: true)['upload_received'] == false, 'missing build is not accepted')
check(inspect_fixture(expired: true)['internal_ready'] == false, 'expired build is not internal-ready')
check(inspect_fixture(commit: 'b' * 40)['status'] == 'pending', 'wrong source SHA never verifies')
check(inspect_fixture(processing: 'FAILED')['processing_complete'] == false, 'failed processing stays unready')
check(inspect_fixture(review: 'DO_NOT_PRINT')['external_review_state'] == 'UNKNOWN', 'unrecognized API values are allowlisted out')
check(inspect_fixture(review: 'APPROVED')['external_review_state'] == 'APPROVED', 'only explicit Apple approval is reported')
failure('VERSION_MISMATCH') { inspect_fixture(version: '0.1.3') }
failure('INPUT') { ChaiTestFlightStatus.inspect_build(client: Object.new, version: '0.2.0', number: 'invalid', commit: 'a' * 40) }
original_stderr = $stderr
begin
  $stderr = StringIO.new
  check(ChaiTestFlightStatus.main({}) == 1, 'non-main or non-dispatch cannot access credentials')
  check(!$stderr.string.include?('DO_NOT_PRINT'), 'all client failure details remain suppressed')
ensure
  $stderr = original_stderr
end
puts 'PASS: read-only Apple status; original-key JWT, exact version/build/SHA, processing vs internal readiness vs external review, safe failures and no upload.'
