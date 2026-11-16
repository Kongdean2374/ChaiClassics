require 'jwt'
require 'json'
require 'openssl'

module ChaiAppleJWT
  CHECKS = %w[structure alg kid iss aud iat exp signature].freeze

  # This is a local consistency/signature check, not proof Apple recognizes the
  # configured key/issuer. Return booleans only; never claims, IDs or token text.
  def self.check(token:, key_id:, issuer_id:, verification_key:, now: Time.now.to_i)
    checks = CHECKS.to_h { |name| [name, false] }
    return checks unless token.is_a?(String) && token.bytesize <= 16_384 && token.split('.', -1).length == 3
    return checks unless token.split('.').all? { |segment| segment.match?(/\A[A-Za-z0-9_-]+\z/) }
    payload, header = JWT.decode(token, nil, false)
    return checks unless header.is_a?(Hash) && payload.is_a?(Hash)
    checks['structure'] = true
    checks['alg'] = header['alg'] == 'ES256'
    checks['kid'] = header['kid'].is_a?(String) && header['kid'].match?(/\A[A-Z0-9]{10}\z/) && header['kid'] == key_id
    checks['iss'] = payload['iss'].is_a?(String) && payload['iss'].match?(/\A[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z/) && payload['iss'] == issuer_id
    checks['aud'] = payload['aud'] == 'appstoreconnect-v1'
    iat = payload['iat']; exp = payload['exp']
    checks['iat'] = iat.is_a?(Integer) && iat.positive? && iat <= now
    checks['exp'] = exp.is_a?(Integer) && iat.is_a?(Integer) && exp > now && exp > iat && exp - iat <= 1200 && exp - now <= 1200
    if checks['alg'] && verification_key.is_a?(OpenSSL::PKey::EC) && verification_key.group.curve_name == 'prime256v1'
      public_key = OpenSSL::PKey.read(verification_key.public_to_pem)
      JWT.decode(token, public_key, true, algorithms: ['ES256'], verify_expiration: false, verify_iat: false,
                 verify_not_before: false, verify_aud: false, verify_iss: false, verify_sub: false)
      checks['signature'] = true
    end
    checks
  rescue StandardError
    # JWT/OpenSSL exceptions can contain decoded claims or sensitive input.
    # Retain already completed booleans, mark signature failure, never expose text.
    checks['signature'] = false
    checks
  end
end
