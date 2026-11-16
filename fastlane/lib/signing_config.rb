require 'base64'
require 'openssl'

module ChaiSigning
  APP_IDENTIFIER = 'cc.chaihome.chaiclassics'.freeze
  GIT_URL = 'https://github.com/Kongdean2374/ChaiClassics-Signing.git'.freeze
  GIT_BRANCH = 'main'.freeze

  def self.api_key_options(env)
    pem = env.fetch('ASC_API_KEY_P8').gsub("\r\n", "\n").strip
    key = OpenSSL::PKey.read(pem)
    raise ArgumentError, 'APPLE_KEY' unless key.is_a?(OpenSSL::PKey::EC) && key.private? && key.group.curve_name == 'prime256v1'
    { key_id: env.fetch('ASC_KEY_ID'), issuer_id: env.fetch('ASC_ISSUER_ID'),
      key_content: pem, is_key_content_base64: false, in_house: false }
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    raise ArgumentError, 'APPLE_KEY'
  end

  def self.match_options(env, api_key:, keychain:, password:, readonly: true)
    raise ArgumentError, 'ASSET_READONLY_REQUIRED' unless readonly == true
    {
      type: 'appstore', platform: 'ios', app_identifier: [APP_IDENTIFIER],
      api_key: api_key, team_id: env.fetch('APPLE_TEAM_ID'),
      storage_mode: 'git', git_url: GIT_URL, git_branch: GIT_BRANCH,
      git_basic_authorization: Base64.strict_encode64('x-access-token:' + env.fetch('SIGNING_REPO_PAT')),
      git_full_name: 'ChaiClassics Signing CI', git_user_email: 'actions@users.noreply.github.com',
      clone_branch_directly: true, readonly: readonly,
      generate_apple_certs: true, force: false, force_for_new_devices: false,
      skip_certificate_matching: false, skip_docs: true,
      keychain_name: keychain, keychain_password: password, verbose: false
    }
  end
end
