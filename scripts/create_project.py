#!/usr/bin/env python3
"""Deterministic native Xcode project, no generation dependency required in CI."""
import hashlib, pathlib, plistlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"'+s.replace('"','\\"')+'"'
objects={}
def obj(name, body): objects[ident(name)]=body; return ident(name)
app_files=sorted((ROOT/'App').glob('*.swift'))
ui_files=sorted((ROOT/'UITests').glob('*.swift'))
def files(paths):
    refs=[]; builds=[]
    for p in paths:
        rel=str(p.relative_to(ROOT)); ref=obj(rel, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+q(rel)+'; sourceTree = SOURCE_ROOT;}')
        refs.append(ref); builds.append(obj(rel+'build','{isa = PBXBuildFile; fileRef = '+ref+';}'))
    return refs,builds
a_refs,a_build=files(app_files); u_refs,u_build=files(ui_files)
asset=obj('assets','{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT;}')
asset_build=obj('assetsbuild','{isa = PBXBuildFile; fileRef = '+asset+';}')
localized_refs=[]; localized_builds=[]
resource_root=ROOT/'App/Resources'
for name in sorted({p.name for p in resource_root.glob('*.lproj/*')}):
    children=[]
    for path in sorted(resource_root.glob('*.lproj/'+name)):
        locale=path.parent.stem
        kind='text.plist.strings' if path.suffix=='.strings' else 'text'
        children.append(obj('localized:'+locale+':'+name,'{isa = PBXFileReference; lastKnownFileType = '+kind+'; name = '+q(locale)+'; path = '+q(str(path.relative_to(ROOT)))+'; sourceTree = SOURCE_ROOT;}'))
    group=obj('localized:'+name,'{isa = PBXVariantGroup; children = ('+','.join(children)+',); name = '+q(name)+'; sourceTree = "<group>";}')
    localized_refs.append(group)
    localized_builds.append(obj('localized-build:'+name,'{isa = PBXBuildFile; fileRef = '+group+';}'))
privacy=obj('privacy-manifest','{isa = PBXFileReference; lastKnownFileType = text.xml; path = App/Resources/PrivacyInfo.xcprivacy; sourceTree = SOURCE_ROOT;}')
privacy_build=obj('privacy-manifest-build','{isa = PBXBuildFile; fileRef = '+privacy+';}')
fixture_refs=[];fixture_builds=[]
for path in sorted((ROOT/'Tests/ChaiCoreTests/Fixtures').glob('*.json')):
    ref=obj('fixture:'+path.name,'{isa = PBXFileReference; lastKnownFileType = text.json; path = '+q(str(path.relative_to(ROOT)))+'; sourceTree = SOURCE_ROOT;}')
    fixture_refs.append(ref);fixture_builds.append(obj('fixture-build:'+path.name,'{isa = PBXBuildFile; fileRef = '+ref+';}'))
product=obj('appproduct','{isa = PBXFileReference; explicitFileType = wrapper.application; path = ChaiClassics.app; sourceTree = BUILT_PRODUCTS_DIR;}')
ui_product=obj('uiproduct','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ChaiClassicsUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
package=obj('package','{isa = XCLocalSwiftPackageReference; relativePath = .;}')
package_product=obj('core','{isa = XCSwiftPackageProductDependency; package = '+package+'; productName = ChaiCore;}')
core_build=obj('corebuild','{isa = PBXBuildFile; productRef = '+package_product+';}')
def array(xs): return '('+','.join(xs)+',)' if xs else '()'
def phase(name,kind,builds): return obj(name,'{isa = '+kind+'; buildActionMask = 2147483647; files = '+array(builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
a_sources=phase('asources','PBXSourcesBuildPhase',a_build); a_resources=phase('aresources','PBXResourcesBuildPhase',[asset_build,privacy_build]+localized_builds); a_frameworks=phase('aframeworks','PBXFrameworksBuildPhase',[core_build])
u_sources=phase('usources','PBXSourcesBuildPhase',u_build); u_frameworks=phase('uframeworks','PBXFrameworksBuildPhase',[])
u_resources=phase('uresources','PBXResourcesBuildPhase',fixture_builds)
base={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','TARGETED_DEVICE_FAMILY':'"1,2"','SDKROOT':'iphoneos','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
app={**base,'PRODUCT_BUNDLE_IDENTIFIER':'cc.chaihome.chaiclassics','PRODUCT_NAME':'"$(TARGET_NAME)"','INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','MARKETING_VERSION':'0.1.1','CURRENT_PROJECT_VERSION':'1','CODE_SIGN_STYLE':'Manual','SWIFT_EMIT_LOC_STRINGS':'YES','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"'}
ui={**base,'PRODUCT_BUNDLE_IDENTIFIER':'cc.chaihome.chaiclassics.uitests','PRODUCT_NAME':'"$(TARGET_NAME)"','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'ChaiClassics','CODE_SIGN_STYLE':'Automatic'}
def configs(name,settings):
    cs=[]
    for mode in ['Debug','Release']:
        s={**settings,'SWIFT_OPTIMIZATION_LEVEL':q('-Onone' if mode=='Debug' else '-O'),'DEBUG_INFORMATION_FORMAT':q('dwarf' if mode=='Debug' else 'dwarf-with-dsym')}
        if name=='app' and mode=='Release':
            # Only the app consumes these parameters. Passing Apple's signing
            # settings globally also applies its profile to Swift Package targets.
            s.update({'DEVELOPMENT_TEAM':q('$(CHAI_SIGNING_TEAM)'),
                      'CODE_SIGN_IDENTITY[sdk=iphoneos*]':q('$(CHAI_SIGNING_IDENTITY)'),
                      'PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]':q('$(CHAI_SIGNING_PROFILE)'),
                      'OTHER_CODE_SIGN_FLAGS[sdk=iphoneos*]':q('$(inherited) $(CHAI_SIGNING_FLAGS)'),
                      'CHAI_RELEASE_VERSION':'0.1.1','CHAI_BUILD_NUMBER':'1',
                      'MARKETING_VERSION':q('$(CHAI_RELEASE_VERSION)'),
                      'CURRENT_PROJECT_VERSION':q('$(CHAI_BUILD_NUMBER)')})
        if mode=='Debug': s['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'; s['ENABLE_TESTABILITY']='YES'
        cs.append(obj(name+mode,'{isa = XCBuildConfiguration; buildSettings = {'+' '.join((q(k) if '[' in k else k)+' = '+v+';' for k,v in s.items())+'}; name = '+mode+';}'))
    return obj(name+'configs','{isa = XCConfigurationList; buildConfigurations = '+array(cs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
app_config=configs('app',app); ui_config=configs('ui',ui); project_config=configs('project',base)
app_target=ident('appTarget'); ui_target=ident('uiTarget'); project_id=ident('project')
proxy=obj('proxy','{isa = PBXContainerItemProxy; containerPortal = '+project_id+'; proxyType = 1; remoteGlobalIDString = '+app_target+'; remoteInfo = ChaiClassics;}')
dependency=obj('dependency','{isa = PBXTargetDependency; target = '+app_target+'; targetProxy = '+proxy+';}')
obj('appTarget','{isa = PBXNativeTarget; buildConfigurationList = '+app_config+'; buildPhases = '+array([a_sources,a_frameworks,a_resources])+'; buildRules = (); dependencies = (); name = ChaiClassics; packageProductDependencies = '+array([package_product])+'; productName = ChaiClassics; productReference = '+product+'; productType = "com.apple.product-type.application";}')
obj('uiTarget','{isa = PBXNativeTarget; buildConfigurationList = '+ui_config+'; buildPhases = '+array([u_sources,u_frameworks,u_resources])+'; buildRules = (); dependencies = '+array([dependency])+'; name = ChaiClassicsUITests; productName = ChaiClassicsUITests; productReference = '+ui_product+'; productType = "com.apple.product-type.bundle.ui-testing";}')
products=obj('products','{isa = PBXGroup; children = '+array([product,ui_product])+'; name = Products; sourceTree = "<group>";}')
group=obj('rootgroup','{isa = PBXGroup; children = '+array(a_refs+u_refs+localized_refs+fixture_refs+[privacy,asset,products])+'; sourceTree = "<group>";}')
obj('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 2600; TargetAttributes = {'+app_target+' = {CreatedOnToolsVersion = 26.0;}; '+ui_target+' = {CreatedOnToolsVersion = 26.0; TestTargetID = '+app_target+';};};}; buildConfigurationList = '+project_config+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hant"; knownRegions = (en,"zh-Hant",Base); mainGroup = '+group+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; packageReferences = '+array([package])+'; targets = '+array([app_target,ui_target])+';}')
proj=ROOT/'ChaiClassics.xcodeproj'; proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project_id+';}\n')
scheme=proj/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def ref(target,name,filename): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{filename}" BlueprintName="{name}" ReferencedContainer="container:ChaiClassics.xcodeproj"/>'
a=ref(app_target,'ChaiClassics','ChaiClassics.app'); u=ref(ui_target,'ChaiClassicsUITests','ChaiClassicsUITests.xctest')
(scheme/'ChaiClassics.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{a}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{u}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n''')
