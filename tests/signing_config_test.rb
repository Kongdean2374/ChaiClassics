# No extra test gems: executes under the exact deployment bundle on Linux/macOS.
require 'fastlane'
require 'match'
require_relative '../fastlane/lib/signing_config'

def check(condition, message)
  raise "Signing configuration assertion failed: #{message}" unless condition
end

pem = OpenSSL::PKey::EC.generate('prime256v1').private_to_pem
env = { 'ASC_KEY_ID' => 'A123456789', 'ASC_ISSUER_ID' => 'fixture-issuer', 'ASC_API_KEY_P8' => pem,
        'APPLE_TEAM_ID' => 'T123456789', 'SIGNING_REPO_PAT' => 'fixture-not-real' }
options = ChaiSigning.api_key_options(env)
check(options[:key_content] == pem.strip, 'original multiline PEM forwarded unchanged')
check(options[:is_key_content_base64] == false, 'no Base64 decoding')
rejected = false
begin
  ChaiSigning.api_key_options(env.merge('ASC_API_KEY_P8' => Base64.strict_encode64(pem)))
rescue ArgumentError
  rejected = true
end
check(rejected, 'Base64 input rejected')
puts 'PASS: original p8 text and rejected Base64'

options = ChaiSigning.match_options(env, api_key: {}, keychain: '/tmp/fixture', password: 'fixture')
check((options.keys - Match::Options.available_options.map(&:key)).empty?, 'options exist in pinned fastlane')
check(options[:readonly], 'readonly is the safe default')
check(options[:app_identifier] == [ChaiSigning::APP_IDENTIFIER], 'single exact Bundle ID')
check(options[:git_branch] == 'main' && options[:git_url] == ChaiSigning::GIT_URL, 'dedicated signing repository main')
check(!options[:force] && options[:generate_apple_certs], 'no force; Apple Distribution supported')
check(Base64.strict_decode64(options[:git_basic_authorization]) == 'x-access-token:fixture-not-real', 'in-memory PAT authorization')
initialization = ChaiSigning.match_options(env, api_key: {}, keychain: '/tmp/fixture', password: 'fixture', readonly: false)
check(initialization[:readonly] == false, 'explicit initialization only')
puts 'PASS: match scope, safe readonly and explicit initialization'
puts '2 signing configuration cases passed; no Apple credentials used.'
