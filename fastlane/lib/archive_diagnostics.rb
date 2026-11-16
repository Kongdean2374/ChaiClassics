require_relative 'release_pipeline'

module ChaiArchive
  STAGES = %w[BUILD_SETTINGS_CHECKED BUILD_APP_RETURNED ARCHIVE_FORMAT_VALID ARCHIVE_APP_VALID ARCHIVE_SIGNATURE_VALID ARCHIVE_CERTIFICATE_MATCH ARCHIVE_PROFILE_MATCH SIGNED_ARCHIVE_VERIFIED].freeze
  PHASES = %w[BUILD_SETTINGS BUILD_APP VERIFY_ARCHIVE COMPLETE].freeze
  FAILURES = %w[ARCHIVE_SANDBOX_INVALID GLOBAL_SIGNING_OVERRIDE BUILD_APP_FAILED ARCHIVE_VALIDATION_FAILED].freeze
  VERIFY_CODES = %w[ARCHIVE_CONTENT_INVALID ARCHIVE_APP_INVALID SIGNING_REJECTED ARCHIVE_CERT_EXTRACT ARCHIVE_CERT_MISMATCH ARCHIVE_PROFILE_MISMATCH].freeze
  FORBIDDEN = %w[DEVELOPMENT_TEAM CODE_SIGN_STYLE CODE_SIGN_IDENTITY CODE_SIGNING_ALLOWED CODE_SIGNING_REQUIRED PROVISIONING_PROFILE PROVISIONING_PROFILE_SPECIFIER OTHER_CODE_SIGN_FLAGS].freeze

  class Session
    def initialize(path: ENV['CHAI_ARCHIVE_REPORT_PATH'], workdir: ENV.fetch('CHAI_RELEASE_WORKDIR'))
      @path = path; @workdir = workdir
      @data = {'schema' => 1, 'phase' => 'BUILD_SETTINGS', 'status' => 'running', 'completed' => [], 'failure' => nil, 'verification_code' => nil}
    end

    def run!(options:, assets:)
      phase('BUILD_SETTINGS')
      check_private_paths!(options)
      settings = Shellwords.split(options.fetch(:xcargs)).map { |arg| arg.split('=',2).first }
      if options[:codesigning_identity] || options[:xcconfig] || options[:skip_codesigning] || options[:skip_build_archive] || options[:skip_archive] || !(settings & FORBIDDEN).empty?
        fail!('GLOBAL_SIGNING_OVERRIDE')
      end
      complete('BUILD_SETTINGS_CHECKED')
      phase('BUILD_APP')
      begin
        yield ChaiRelease.archive_options(options)
      rescue StandardError => error
        # Extra fastlane error_info often contains xcodebuild output. It stays
        # under the same 0700 sandbox and is never copied into the safe report.
        File.open(File.join(@workdir,'archive-error.log'), 'w', 0o600) do |file|
          file.write(error.message.to_s)
          detail = error.error_info if error.respond_to?(:error_info)
          file.write("\n" + detail) if detail.is_a?(String)
        end
        fail!('BUILD_APP_FAILED')
      end
      complete('BUILD_APP_RETURNED')
      phase('VERIFY_ARCHIVE')
      begin
        ChaiRelease.verify_archive!(path: options.fetch(:archive_path), assets: assets,
          on_stage: ->(stage) { complete(stage) })
      rescue ChaiRelease::Failure => error
        @data['verification_code'] = VERIFY_CODES.include?(error.reason) ? error.reason : 'ARCHIVE_CONTENT_INVALID'
        fail!('ARCHIVE_VALIDATION_FAILED')
      end
      complete('SIGNED_ARCHIVE_VERIFIED')
      @data.merge!('phase' => 'COMPLETE', 'status' => 'complete')
      write
      true
    end

    private
    def check_private_paths!(options)
      root = File.realpath(@workdir)
      lexical_root = File.expand_path(@workdir)
      stat = File.stat(root)
      fail!('ARCHIVE_SANDBOX_INVALID') unless stat.uid == Process.uid && (stat.mode & 0o077).zero?
      %i[archive_path buildlog_path derived_data_path output_directory].each do |key|
        path = File.expand_path(options.fetch(key))
        fail!('ARCHIVE_SANDBOX_INVALID') unless path.start_with?(lexical_root + File::SEPARATOR)
        # macOS /var resolves to /private/var. Accept an equivalent root alias,
        # but reject any existing child symlink that escapes the private tree.
        ancestor = path
        ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor)
        resolved = File.realpath(ancestor)
        fail!('ARCHIVE_SANDBOX_INVALID') unless resolved == root || resolved.start_with?(root + File::SEPARATOR)
      end
    rescue ChaiRelease::Failure
      raise
    rescue StandardError
      fail!('ARCHIVE_SANDBOX_INVALID')
    end

    def phase(value)
      @data['phase'] = value
      write
    end

    def complete(stage)
      raise ChaiRelease::Failure.new('ARCHIVE', 'ARCHIVE_VERIFY_FAILED') unless STAGES[@data['completed'].length] == stage
      @data['completed'] << stage
      write
    end

    def fail!(code)
      @data.merge!('failure' => code, 'status' => 'failed')
      write
      reason = @data['phase'] == 'VERIFY_ARCHIVE' ? 'ARCHIVE_VERIFY_FAILED' : 'ARCHIVE_BUILD_FAILED'
      raise ChaiRelease::Failure.new('ARCHIVE', reason)
    end

    def write
      return if @path.to_s.empty?
      File.open(@path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(JSON.generate(@data)) }
    end
  end
end
