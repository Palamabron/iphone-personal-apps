import { mkdir, mkdtemp, readFile, writeFile, cp, readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
function run(command, args) { const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' }); if (result.status !== 0) throw new Error('Nieudane polecenie: ' + command); }
run(process.execPath, ['scripts/prepare-ios.mjs']);
if (process.platform !== 'darwin') throw new Error('HTML przygotowany. Kompilacja IPA wymaga macOS/Xcode; użyj ręcznego workflow lub własnego Maca.');
const output = path.join(root, 'build', 'ios'); await mkdir(output, { recursive: true });
const work = await mkdtemp(path.join(output, 'radar-'));
await cp(path.join(root, 'ios', 'RadarApp.swift'), path.join(work, 'RadarApp.swift'));
await cp(path.join(output, 'resources', 'radar.html'), path.join(work, 'radar.html'));
const project = path.join(work, 'TechRadar.xcodeproj'); await mkdir(path.join(project, 'xcshareddata', 'xcschemes'), { recursive: true });
const id = n => 'A' + n.toString(16).toUpperCase().padStart(23, '0');
const settings = 'SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 18.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES; TARGETED_DEVICE_FAMILY = 1;';
const targetSettings = settings + ' PRODUCT_NAME = TechRadar; PRODUCT_BUNDLE_IDENTIFIER = dev.palamabron.warsawtechradar; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 0.2.0; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "Tech Radar"; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait; CODE_SIGN_STYLE = Automatic; SWIFT_EMIT_LOC_STRINGS = YES;';
const pbx = `// !$*UTF8*$!
{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {
${id(1)} = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = ${id(2)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = pl; hasScannedForEncodings = 0; knownRegions = (pl,en,Base); mainGroup = ${id(3)}; productRefGroup = ${id(4)}; projectDirPath = ""; projectRoot = ""; targets = (${id(5)});};
${id(2)} = {isa = XCConfigurationList; buildConfigurations = (${id(6)},${id(7)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
${id(3)} = {isa = PBXGroup; children = (${id(8)},${id(9)},${id(4)}); sourceTree = "<group>";};
${id(4)} = {isa = PBXGroup; children = (${id(10)}); name = Products; sourceTree = "<group>";};
${id(5)} = {isa = PBXNativeTarget; buildConfigurationList = ${id(11)}; buildPhases = (${id(12)},${id(13)},${id(14)}); buildRules = (); dependencies = (); name = TechRadar; productName = TechRadar; productReference = ${id(10)}; productType = "com.apple.product-type.application";};
${id(6)} = {isa = XCBuildConfiguration; buildSettings = {${settings}}; name = Debug;};
${id(7)} = {isa = XCBuildConfiguration; buildSettings = {${settings}}; name = Release;};
${id(8)} = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RadarApp.swift; sourceTree = "<group>";};
${id(9)} = {isa = PBXFileReference; lastKnownFileType = text.html; path = radar.html; sourceTree = "<group>";};
${id(10)} = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = TechRadar.app; sourceTree = BUILT_PRODUCTS_DIR;};
${id(11)} = {isa = XCConfigurationList; buildConfigurations = (${id(15)},${id(16)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;};
${id(12)} = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (${id(17)}); runOnlyForDeploymentPostprocessing = 0;};
${id(13)} = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
${id(14)} = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (${id(18)}); runOnlyForDeploymentPostprocessing = 0;};
${id(15)} = {isa = XCBuildConfiguration; buildSettings = {${targetSettings} SWIFT_OPTIMIZATION_LEVEL = "-Onone";}; name = Debug;};
${id(16)} = {isa = XCBuildConfiguration; buildSettings = {${targetSettings} SWIFT_OPTIMIZATION_LEVEL = "-O";}; name = Release;};
${id(17)} = {isa = PBXBuildFile; fileRef = ${id(8)};};
${id(18)} = {isa = PBXBuildFile; fileRef = ${id(9)};};
}; rootObject = ${id(1)}; }
`;
await writeFile(path.join(project, 'project.pbxproj'), pbx);
const scheme = `<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${id(5)}" BuildableName="TechRadar.app" BlueprintName="TechRadar" ReferencedContainer="container:TechRadar.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>`;
await writeFile(path.join(project, 'xcshareddata', 'xcschemes', 'TechRadar.xcscheme'), scheme);
const derived = path.join(work, 'DerivedData');
run('xcodebuild', ['-project', project, '-scheme', 'TechRadar', '-configuration', 'Release', '-sdk', 'iphoneos', '-destination', 'generic/platform=iOS', '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'build']);
const products = path.join(derived, 'Build', 'Products', 'Release-iphoneos');
const app = (await readdir(products)).find(name => name.endsWith('.app')); if (!app) throw new Error('Brak produktu .app.');
const payload = path.join(work, 'Payload'); await mkdir(payload); await cp(path.join(products, app), path.join(payload, app), { recursive: true });
run('ditto', ['-c', '-k', '--keepParent', payload, path.join(output, 'TechRadar-unsigned.ipa')]);
console.log('Gotowe: build/ios/TechRadar-unsigned.ipa. Podpisz własnym kontem przy instalacji w SideStore.');
