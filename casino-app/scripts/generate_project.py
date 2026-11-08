"""Deterministically generate a dependency-free, explicit-file Xcode project."""
from pathlib import Path
import hashlib
import json
import plistlib

root = Path(__file__).resolve().parents[1]
objects = {}
def key(label):
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()
def add(label, isa, **fields):
    identifier = key(label)
    objects[identifier] = dict(isa=isa, **fields)
    return identifier
def file(label, path, kind, source_tree="<group>"):
    return add(label,"PBXFileReference",lastKnownFileType=kind,path=path,sourceTree=source_tree)
def buildfile(label, reference):
    return add(label,"PBXBuildFile",fileRef=reference)
def group(label, path, children):
    return add(label,"PBXGroup",children=children,path=path,sourceTree="<group>")

app_files = []
app_sources = []
for source in sorted((root / "AccessHubCasino").glob("*.swift")):
    ref = file("file-app-"+source.name,source.name,"sourcecode.swift")
    app_files.append(ref)
    app_sources.append(buildfile("build-"+source.name,ref))
resources = []
for name, kind in [("Assets.xcassets","folder.assetcatalog"),("LaunchScreen.storyboard","file.storyboard"),("PrivacyInfo.xcprivacy","text.xml")]:
    ref = file("resource-"+name,name,kind); app_files.append(ref); resources.append(buildfile("build-"+name,ref))
app_files.append(file("app-info","Info.plist","text.plist.xml"))
audio_files = []
for source in sorted((root / "AccessHubCasino/Audio").glob("*.wav")):
    ref=file("audio-"+source.name,source.name,"audio.wav"); audio_files.append(ref); resources.append(buildfile("build-"+source.name,ref))
app_files.append(group("audio-group","Audio",audio_files))
app_group = group("app-group","AccessHubCasino",app_files)
config_file = file("config","Config.xcconfig","text.xcconfig")
unit_file = file("unit-source","ClientContractTests.swift","sourcecode.swift")
ui_file = file("ui-source","AccessHubCasinoUITests.swift","sourcecode.swift")
unit_group = group("unit-group","AccessHubCasinoTests",[unit_file])
ui_group = group("ui-group","AccessHubCasinoUITests",[ui_file])
app_product = file("app-product","AccessHubCasino.app","wrapper.application","BUILT_PRODUCTS_DIR")
unit_product = file("unit-product","AccessHubCasinoTests.xctest","wrapper.cfbundle","BUILT_PRODUCTS_DIR")
ui_product = file("ui-product","AccessHubCasinoUITests.xctest","wrapper.cfbundle","BUILT_PRODUCTS_DIR")
products = add("products-group","PBXGroup",children=[app_product,unit_product,ui_product],name="Products",sourceTree="<group>")
main = add("main-group","PBXGroup",children=[app_group,unit_group,ui_group,config_file,products],sourceTree="<group>")

def configs(label, settings, base=None):
    ids=[]
    for name in ("Debug","Release"):
        values=dict(settings)
        if label == "project":
            values.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if name=="Debug" else "-O",DEBUG_INFORMATION_FORMAT="dwarf" if name=="Debug" else "dwarf-with-dsym",ENABLE_TESTABILITY="YES" if name=="Debug" else "NO")
            if name=="Debug": values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]="DEBUG $(inherited)"
        fields=dict(buildSettings=values,name=name)
        if base: fields["baseConfigurationReference"]=base
        ids.append(add(label+"-"+name,"XCBuildConfiguration",**fields))
    return add(label+"-configs","XCConfigurationList",buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName="Release")

project_settings=dict(ALWAYS_SEARCH_USER_PATHS="NO",CLANG_ENABLE_MODULES="YES",CLANG_ENABLE_OBJC_ARC="YES",CLANG_WARN_BOOL_CONVERSION="YES",CLANG_WARN_CONSTANT_CONVERSION="YES",CLANG_WARN_INFINITE_RECURSION="YES",CLANG_WARN_INT_CONVERSION="YES",CLANG_WARN_UNREACHABLE_CODE="YES",COPY_PHASE_STRIP="NO",ENABLE_STRICT_OBJC_MSGSEND="YES",GCC_C_LANGUAGE_STANDARD="gnu17",GCC_NO_COMMON_BLOCKS="YES",GCC_WARN_64_TO_32_BIT_CONVERSION="YES",GCC_WARN_ABOUT_RETURN_TYPE="YES_ERROR",GCC_WARN_UNINITIALIZED_AUTOS="YES_AGGRESSIVE",GCC_WARN_UNUSED_FUNCTION="YES",GCC_WARN_UNUSED_VARIABLE="YES",IPHONEOS_DEPLOYMENT_TARGET="17.0",SDKROOT="iphoneos",SWIFT_VERSION="5.0",TARGETED_DEVICE_FAMILY="1",CODE_SIGN_STYLE="Automatic",SUPPORTED_PLATFORMS="iphoneos iphonesimulator")
project_configs = configs("project",project_settings,config_file)
app_settings=dict(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",CURRENT_PROJECT_VERSION="3",MARKETING_VERSION="2.0",GENERATE_INFOPLIST_FILE="NO",INFOPLIST_FILE="AccessHubCasino/Info.plist",LD_RUNPATH_SEARCH_PATHS=["$(inherited)","@executable_path/Frameworks"],PRODUCT_NAME="$(TARGET_NAME)",SWIFT_EMIT_LOC_STRINGS="YES",SUPPORTS_MACCATALYST="NO",SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD="NO")
app_configs=configs("app",app_settings)
unit_configs=configs("unit",dict(PRODUCT_BUNDLE_IDENTIFIER="app.accesshub.casino.tests",GENERATE_INFOPLIST_FILE="YES",PRODUCT_NAME="$(TARGET_NAME)",BUNDLE_LOADER="$(TEST_HOST)",TEST_HOST="$(BUILT_PRODUCTS_DIR)/AccessHubCasino.app/AccessHubCasino",LD_RUNPATH_SEARCH_PATHS=["$(inherited)","@executable_path/Frameworks","@loader_path/Frameworks"]))
ui_configs=configs("ui",dict(PRODUCT_BUNDLE_IDENTIFIER="app.accesshub.casino.uitests",GENERATE_INFOPLIST_FILE="YES",PRODUCT_NAME="$(TARGET_NAME)",TEST_TARGET_NAME="AccessHubCasino",LD_RUNPATH_SEARCH_PATHS=["$(inherited)","@executable_path/Frameworks","@loader_path/Frameworks"]))

def phases(label,sources,resource_files):
    result=[]
    for kind,files in [("Sources",sources),("Frameworks",[]),("Resources",resource_files)]:
        result.append(add(label+"-phase-"+kind,"PBX"+kind+"BuildPhase",buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0))
    return result
app_target=add("app-target","PBXNativeTarget",buildConfigurationList=app_configs,buildPhases=phases("app",app_sources,resources),buildRules=[],dependencies=[],name="AccessHubCasino",productName="AccessHubCasino",productReference=app_product,productType="com.apple.product-type.application")
def dependency(label):
    proxy=add(label+"-proxy","PBXContainerItemProxy",containerPortal=key("project"),proxyType=1,remoteGlobalIDString=app_target,remoteInfo="AccessHubCasino")
    return add(label+"-dependency","PBXTargetDependency",target=app_target,targetProxy=proxy)
unit_target=add("unit-target","PBXNativeTarget",buildConfigurationList=unit_configs,buildPhases=phases("unit",[buildfile("unit-build",unit_file)],[]),buildRules=[],dependencies=[dependency("unit")],name="AccessHubCasinoTests",productName="AccessHubCasinoTests",productReference=unit_product,productType="com.apple.product-type.bundle.unit-test")
ui_target=add("ui-target","PBXNativeTarget",buildConfigurationList=ui_configs,buildPhases=phases("ui",[buildfile("ui-build",ui_file)],[]),buildRules=[],dependencies=[dependency("ui")],name="AccessHubCasinoUITests",productName="AccessHubCasinoUITests",productReference=ui_product,productType="com.apple.product-type.bundle.ui-testing")
project=add("project","PBXProject",attributes={"BuildIndependentTargetsInParallel":"YES","LastUpgradeCheck":"1600","TargetAttributes":{app_target:{"CreatedOnToolsVersion":"16.0"},unit_target:{"CreatedOnToolsVersion":"16.0","TestTargetID":app_target},ui_target:{"CreatedOnToolsVersion":"16.0","TestTargetID":app_target}}},buildConfigurationList=project_configs,compatibilityVersion="Xcode 14.0",developmentRegion="en",hasScannedForEncodings=0,knownRegions=["en","Base"],mainGroup=main,productRefGroup=products,projectDirPath="",projectRoot="",targets=[app_target,unit_target,ui_target])

def serialize(value,depth=0):
    indent="\t"*depth
    if isinstance(value,dict):
        return "{\n"+"".join(indent+"\t"+json.dumps(k)+" = "+serialize(v,depth+1)+";\n" for k,v in value.items())+indent+"}"
    if isinstance(value,list):
        return "(\n"+"".join(indent+"\t"+serialize(v,depth+1)+",\n" for v in value)+indent+")"
    if isinstance(value,int): return str(value)
    return json.dumps(value)

directory=root/"AccessHubCasino.xcodeproj"
directory.mkdir(exist_ok=True)
(directory/"project.pbxproj").write_text("// !$*UTF8*$!\n"+serialize({"archiveVersion":1,"classes":{},"objectVersion":56,"objects":objects,"rootObject":project})+"\n",encoding="utf-8")
scheme_dir=directory/"xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True,exist_ok=True)
def reference(identifier,name,buildable):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{buildable}" BlueprintName="{name}" ReferencedContainer="container:AccessHubCasino.xcodeproj"/>'
app_ref=reference(app_target,"AccessHubCasino","AccessHubCasino.app")
unit_ref=reference(unit_target,"AccessHubCasinoTests","AccessHubCasinoTests.xctest")
ui_ref=reference(ui_target,"AccessHubCasinoUITests","AccessHubCasinoUITests.xctest")
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{unit_ref}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ui_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="NO"><Testables>
    <TestableReference skipped="NO">{unit_ref}</TestableReference><TestableReference skipped="NO">{ui_ref}</TestableReference>
  </Testables><MacroExpansion>{app_ref}</MacroExpansion><EnvironmentVariables><EnvironmentVariable key="ACCESSHUB_RUN_ONLINE_TESTS" value="$(ACCESSHUB_RUN_ONLINE_TESTS)" isEnabled="YES"/></EnvironmentVariables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_dir/"AccessHubCasino.xcscheme").write_text(scheme,encoding="utf-8")
workspace=directory/"project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace/"contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>')
print(f"Generated Xcode project with {len(app_sources)} Swift source files, {len(resources)} resources and two test targets.")
