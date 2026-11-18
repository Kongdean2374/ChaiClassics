# Standard-library fixtures only; no Apple requests or real signing credentials.
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../scripts/check_uploaded_build'

def check(condition, detail)
  raise 'Uploaded-build status assertion failed: ' + detail unless condition
end

Dir.mktmpdir('chai-upload-status-') do |root|
  FileUtils.mkdir_p(File.join(root, 'build/release'))
  file = File.join(root, 'build/release/provenance.txt')
  sha = 'a' * 40
  original = "version=0.3.0\nbuild=123.1\ncommit=#{sha}\n"
  File.write(file, original)
  env = {'RELEASE_VERSION' => '0.3.0', 'GITHUB_SHA' => sha,
         'GITHUB_STEP_SUMMARY' => File.join(root, 'summary.txt')}
  report = lambda do |state, received|
    {'version' => '0.3.0', 'build_number' => '123.1', 'source_commit' => sha,
     'processing_state' => state, 'processing_complete' => state == 'VALID',
     'upload_received' => received, 'status' => state == 'VALID' ? 'ready' : 'pending'}
  end
  run = lambda do |states, exit_code = 2|
    calls, waits = [], []
    runner = lambda do |actual|
      calls << actual
      state, received = states[[calls.length - 1, states.length - 1].min]
      File.write(File.join(root, 'build/testflight-status.json'), JSON.generate(report.call(state, received)))
      exit_code
    end
    result = ChaiUploadedBuild.check(env, root: root, runner: runner, sleeper: ->(seconds) { waits << seconds }, interval: 0)
    [result, calls, waits]
  end
  %w[PROCESSING VALID].each do |state|
    result, calls, waits = run.call([[state, true]])
    check(result == 0 && calls.length == 1 && waits.empty?, 'Apple receipt stops polling without pretending processing is complete')
    check(calls[0]['TESTED_BUILD_NUMBER'] == '123.1' && calls[0]['TESTED_COMMIT'] == sha, 'only exact provenance is queried')
    data = JSON.parse(File.read(File.join(root, 'build/testflight-status.json')))
    check(data['processing_complete'] == (state == 'VALID'), 'pending and valid stay distinct')
  end
  %w[FAILED INVALID].each do |state|
    result, calls, waits = run.call([[state, true]])
    check(result == 1 && calls.length == 1 && waits.empty?, 'Apple rejected processing fails without reupload')
  end
  result, calls, waits = run.call([['NOT_FOUND', false], ['NOT_FOUND', false], ['PROCESSING', true]])
  check(result == 0 && calls.length == 3 && waits.length == 2, 'only not-yet-visible records receive bounded read retries')
  result, calls, waits = run.call([['NOT_FOUND', false]])
  check(result == 2 && calls.length == 6 && waits.length == 5, 'missing record remains explicitly pending after a hard bound')
  result, calls, waits = run.call([['PROCESSING', true]], 1)
  check(result == 1 && calls.length == 1 && waits.empty?, 'API/auth failures never trigger retries or trust a stale report')
  [original.sub(sha, 'b' * 40), original + "build=999\n", original + "secret=forbidden\n", 'x' * 257].each do |bad|
    File.write(file, bad)
    calls = []
    previous_stderr = $stderr; $stderr = StringIO.new
    begin
      result = ChaiUploadedBuild.check(env, root: root, runner: ->(actual) { calls << actual }, sleeper: ->(_) { raise 'No sleep allowed' })
      check(result == 1 && calls.empty?, 'invalid/duplicate/mismatched provenance never reaches Apple')
      check(!$stderr.string.include?('forbidden') && !$stderr.string.include?('b' * 40), 'safe fixed diagnostics only')
    ensure
      $stderr = previous_stderr
    end
  end
end
puts 'PASS: exact provenance, Apple receipt/processing distinction, bounded read-only polling and failure isolation.'
