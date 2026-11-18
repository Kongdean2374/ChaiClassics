#!/usr/bin/env ruby
# Query only the exact build just uploaded; never upload again or mutate Apple data.
require 'json'
require_relative 'testflight_status'

module ChaiUploadedBuild
  ROOT = File.expand_path('..', __dir__)

  def self.check(env = ENV, root: ROOT, runner: ChaiTestFlightStatus.method(:main),
                 sleeper: ->(seconds) { sleep(seconds) }, attempts: 6, interval: 30)
    ChaiTestFlightStatus.check(attempts.between?(1, 6) && interval.between?(0, 30), 'POLL_CONFIG')
    provenance = File.join(root, 'build/release/provenance.txt')
    ChaiTestFlightStatus.check(File.file?(provenance) && File.size(provenance) <= 256, 'PROVENANCE')
    entries = File.readlines(provenance, chomp: true).map { |line| line.split('=', 2) }
    ChaiTestFlightStatus.check(entries.all? { |pair| pair.length == 2 } && entries.map(&:first).sort == %w[build commit version], 'PROVENANCE')
    values = entries.to_h
    ChaiTestFlightStatus.check(values['version'] == env['RELEASE_VERSION'] && values['commit'] == env['GITHUB_SHA'] &&
      values['version'].match?(/\A\d+\.\d+\.\d+\z/) && values['build'].match?(/\A\d+(?:\.\d+){0,2}\z/) &&
      values['commit'].match?(/\A[0-9a-f]{40}\z/), 'PROVENANCE')
    status_env = env.to_h.merge('TESTED_BUILD_NUMBER' => values['build'], 'TESTED_COMMIT' => values['commit'])
    report = nil
    attempts.times do |index|
      code = runner.call(status_env)
      return 1 unless [0, 2].include?(code)
      report = JSON.parse(File.read(File.join(root, 'build/testflight-status.json')))
      ChaiTestFlightStatus.check(report.values_at('version', 'build_number', 'source_commit') == values.values_at('version', 'build', 'commit'), 'PROVENANCE')
      break if report['upload_received'] == true
      sleeper.call(interval) if index + 1 < attempts
    end
    if env['GITHUB_STEP_SUMMARY']
      state = report.fetch('processing_state')
      ChaiTestFlightStatus.check((ChaiTestFlightStatus::PROCESSING + %w[NOT_FOUND UNKNOWN]).include?(state), 'RESPONSE_SCHEMA')
      File.open(env['GITHUB_STEP_SUMMARY'], 'a') do |file|
        file.puts "### TestFlight build #{values['version']} (#{values['build']})"
        file.puts "Apple receipt: #{report['upload_received'] == true ? 'confirmed' : 'not yet visible'}; processing: #{state}."
        file.puts 'Processing and external Beta review are separate from upload; no App Store submission was performed.'
      end
    end
    return 1 if %w[FAILED INVALID].include?(report['processing_state'])
    # A visible PROCESSING build is an Apple receipt, not an install-ready claim.
    # NOT_FOUND remains explicitly pending in the report, never a fabricated pass.
    report['upload_received'] == true ? 0 : 2
  rescue ChaiTestFlightStatus::Failure, JSON::ParserError, IOError, SystemCallError, KeyError, TypeError, NoMethodError
    warn 'Uploaded build status check failed [STATUS_CHECK]; credentials and response suppressed.'
    1
  end
end

exit ChaiUploadedBuild.check if $PROGRAM_NAME == __FILE__
