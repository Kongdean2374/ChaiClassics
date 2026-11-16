require_relative 'support/release_fixture'
require_relative '../fastlane/lib/archive_diagnostics'

check = ReleaseFixture.method(:check)
count = 0
Dir.mktmpdir('archive-session-fixture-') do |root|
  cert = ReleaseFixture.certificate
  options = ReleaseFixture.options(certificate: cert,workdir: root)
  report_path = File.join(root,'report.json')
  profile = File.join(root,'source-profile');File.binwrite(profile,'fixture-profile')
  assets = {certificate: cert,path: profile}
  commands = Object.new
  commands.define_singleton_method(:run) do |*argv, input: nil|
    if argv.first == 'plutil'
      return [File.read(argv.last),argv[2]=='xml1']
    elsif argv[1] == '-d'
      File.binwrite(argv[2].delete_prefix('--extract-certificates=')+'0',cert.to_der)
    end
    ['',true]
  end
  # Inject the macOS command adapter, not the production archive verifier.
  original = ChaiRelease.method(:verify_archive!)
  ChaiRelease.define_singleton_method(:verify_archive!) do |**args|
    original.call(**args,commands: commands)
  end
  begin
    attempt = lambda do |params,expected,&builder|
      begin
        ChaiArchive::Session.new(path: report_path,workdir: root).run!(options: params,assets: assets,&builder)
        check.call(expected.nil?)
      rescue ChaiRelease::Failure => error
        check.call(error.reason == expected)
      end
      data = JSON.parse(File.read(report_path))
      check.call(!File.read(report_path).include?('DO_NOT_PRINT') && (File.stat(report_path).mode & 0o077).zero?)
      data
    end
    data=attempt.call(options,'ARCHIVE_BUILD_FAILED') { raise 'DO_NOT_PRINT_PRIVATE_TOKEN_PATH' }
    check.call(data['phase']=='BUILD_APP' && data['failure']=='BUILD_APP_FAILED' && data['completed']==['BUILD_SETTINGS_CHECKED']);count+=1
    check.call((File.stat(File.join(root,'archive-error.log')).mode&0o077).zero?);count+=1
    data=attempt.call(options,'ARCHIVE_VERIFY_FAILED') { true }
    check.call(data['phase']=='VERIFY_ARCHIVE' && data['verification_code']=='ARCHIVE_CONTENT_INVALID');count+=1
    [options.merge(codesigning_identity:'fixture'),options.merge(xcargs:'PROVISIONING_PROFILE_SPECIFIER=fixture'),options.merge(skip_codesigning:true),options.merge(skip_build_archive:true),options.merge(skip_archive:true)].each do |bad|
      data=attempt.call(bad,'ARCHIVE_BUILD_FAILED') { raise 'Builder must not be called' }
      check.call(data['failure']=='GLOBAL_SIGNING_OVERRIDE');count+=1
    end
    bad=options.merge(buildlog_path:File.join(Dir.tmpdir,'outside-sandbox'))
    data=attempt.call(bad,'ARCHIVE_BUILD_FAILED') { raise 'Builder must not be called' }
    check.call(data['failure']=='ARCHIVE_SANDBOX_INVALID');count+=1
    app=File.join(options[:archive_path],'Products/Applications/ChaiClassics.app');FileUtils.mkdir_p(app)
    info={'ArchiveVersion'=>2,'CreationDate'=>Time.now,'ApplicationProperties'=>{'ApplicationPath'=>'Applications/ChaiClassics.app'}}
    File.write(File.join(options[:archive_path],'Info.plist'),info.to_plist)
    app_info={'CFBundleIdentifier'=>ChaiSigning::APP_IDENTIFIER,'CFBundleSupportedPlatforms'=>['iPhoneOS']}
    File.write(File.join(app,'Info.plist'),app_info.to_plist)
    File.binwrite(File.join(app,'embedded.mobileprovision'),'fixture-profile')
    data=attempt.call(options,nil) do |params|
      check.call(params[:skip_package_ipa]==true && !params[:skip_codesigning] && !params[:skip_build_archive])
      true
    end
    check.call(data['completed']==ChaiArchive::STAGES && data['status']=='complete');count+=1
    Dir.mktmpdir('archive-path-alias-') do |parent|
      link=File.join(parent,'private-root-alias');File.symlink(root,link)
      aliased=ReleaseFixture.options(certificate: cert,workdir: link)
      ChaiArchive::Session.new(path: report_path,workdir: link).run!(options: aliased,assets: assets) { true }
      check.call(JSON.parse(File.read(report_path))['status']=='complete');count+=1
      escape=File.join(root,'escape');File.symlink(parent,escape)
      data=attempt.call(options.merge(buildlog_path:File.join(escape,'logs')),'ARCHIVE_BUILD_FAILED') { raise 'Must not execute' }
      check.call(data['failure']=='ARCHIVE_SANDBOX_INVALID');count+=1
      FileUtils.rm_f(escape)
    end
    File.write(File.join(app,'Info.plist'),app_info.merge('CFBundleSupportedPlatforms'=>['iPhoneSimulator']).to_plist)
    data=attempt.call(options,'ARCHIVE_VERIFY_FAILED') { true }
    check.call(data['verification_code']=='ARCHIVE_APP_INVALID' && !data['completed'].include?('SIGNED_ARCHIVE_VERIFIED'));count+=1
  ensure
    ChaiRelease.define_singleton_method(:verify_archive!,original)
  end
end
puts "PASS: #{count} archive command/postcheck separation, private sandbox, real verifier metadata checks and no-unsigned/no-export guards (macOS commands mocked)."
