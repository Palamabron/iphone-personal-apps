// Isolated development probe. It is never bundled into Focus Tube.
import { mkdir, mkdtemp, readFile, writeFile, cp, readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
if (process.platform !== 'darwin') throw new Error('This iPhone build requires macOS and Xcode.');
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
  if (result.status !== 0) throw new Error(`Command failed: ${command}`);
}

const output = path.join(root, 'build');
await mkdir(output, { recursive: true });
const work = await mkdtemp(path.join(output, 'probe-'));
await writeFile(path.join(work, 'ProbeApp.swift'), await readFile(path.join(root, 'ProbeApp.swift')));
const icons = path.join(work, 'Assets.xcassets', 'AppIcon.appiconset');
await mkdir(icons, { recursive: true });
await cp(path.join(root, '..', '..', 'ios', 'AppIcon.png'), path.join(icons, 'AppIcon.png'));
await writeFile(path.join(icons, 'Contents.json'), JSON.stringify({ images: [{ filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }], info: { author: 'xcode', version: 1 } }));

const project = path.join(work, 'PremiumProbe.xcodeproj');
await mkdir(path.join(project, 'xcshareddata', 'xcschemes'), { recursive: true });
const id = n => 'A' + n.toString(16).toUpperCase().padStart(23, '0');
const common = 'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; TARGETED_DEVICE_FAMILY = 1;';
const target = common + ' PRODUCT_NAME = PremiumProbe; PRODUCT_BUNDLE_IDENTIFIER = dev.palamabron.focustube.premiumprobe; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.1.0; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Premium Probe"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; CODE_SIGN_STYLE = Automatic; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;';
const pbx = `// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
${id(1)} = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = ${id(2)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = ${id(3)}; productRefGroup = ${id(4)}; projectDirPath = ""; projectRoot = ""; targets = (${id(5)});};
${id(2)} = {isa = XCConfigurationList; buildConfigurations = (${id(6)},${id(7)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
${id(3)} = {isa = PBXGroup; children = (${id(8)},${id(9)},${id(4)}); sourceTree = "<group>";};
${id(4)} = {isa = PBXGroup; children = (${id(10)}); name = Products; sourceTree = "<group>";};
${id(5)} = {isa = PBXNativeTarget; buildConfigurationList = ${id(11)}; buildPhases = (${id(12)},${id(13)},${id(14)}); buildRules = (); dependencies = (); name = PremiumProbe; productName = PremiumProbe; productReference = ${id(10)}; productType = "com.apple.product-type.application";};
${id(6)} = {isa = XCBuildConfiguration; buildSettings = {${common}}; name = Debug;};
${id(7)} = {isa = XCBuildConfiguration; buildSettings = {${common}}; name = Release;};
${id(8)} = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProbeApp.swift; sourceTree = "<group>";};
${id(9)} = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";};
${id(10)} = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PremiumProbe.app; sourceTree = BUILT_PRODUCTS_DIR;};
${id(11)} = {isa = XCConfigurationList; buildConfigurations = (${id(15)},${id(16)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
${id(12)} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${id(17)}); runOnlyForDeploymentPostprocessing = 0;};
${id(13)} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
${id(14)} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${id(18)}); runOnlyForDeploymentPostprocessing = 0;};
${id(15)} = {isa = XCBuildConfiguration; buildSettings = {${target} SWIFT_OPTIMIZATION_LEVEL = "-Onone";}; name = Debug;};
${id(16)} = {isa = XCBuildConfiguration; buildSettings = {${target} SWIFT_OPTIMIZATION_LEVEL = "-O";}; name = Release;};
${id(17)} = {isa = PBXBuildFile; fileRef = ${id(8)};};
${id(18)} = {isa = PBXBuildFile; fileRef = ${id(9)};};
}; rootObject = ${id(1)}; }
`;
await writeFile(path.join(project, 'project.pbxproj'), pbx);
const scheme = `<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(5)}" BuildableName="PremiumProbe.app" BlueprintName="PremiumProbe" ReferencedContainer="container:PremiumProbe.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>`;
await writeFile(path.join(project, 'xcshareddata', 'xcschemes', 'PremiumProbe.xcscheme'), scheme);
const derived = path.join(work, 'DerivedData');
run('xcodebuild', ['-project', project, '-scheme', 'PremiumProbe', '-configuration', 'Release', '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS', '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'build']);
const products = path.join(derived, 'Build', 'Products', 'Release-iphoneos');
const app = (await readdir(products)).find(name => name === 'PremiumProbe.app');
if (!app) throw new Error('Missing iPhone application.');
const payload = path.join(work, 'Payload');
await mkdir(payload);
await cp(path.join(products, app), path.join(payload, app), { recursive: true });
run('ditto', ['-c', '-k', '--keepParent', payload, path.join(output, 'PremiumProbe-unsigned.ipa')]);
console.log('Built build/PremiumProbe-unsigned.ipa; no device validation has been performed.');
