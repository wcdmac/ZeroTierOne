#!/usr/bin/env python3
import uuid, os

def genid():
    return uuid.uuid4().hex[:24].upper()

project_dir = os.path.dirname(os.path.abspath(__file__))
xcode_dir = os.path.join(project_dir, "ZeroTierOne.xcodeproj")
os.makedirs(xcode_dir, exist_ok=True)

main_app_source = os.path.join(project_dir, "ZeroTierOne")
tunnel_source = os.path.join(project_dir, "ZeroTierOne", "ZeroTierTunnel")
root_dir = os.path.dirname(project_dir)

APP_TARGET_UUID = genid()
TUNNEL_TARGET_UUID = genid()
APP_BUILD_CFG_DEBUG = genid()
APP_BUILD_CFG_RELEASE = genid()
TUNNEL_BUILD_CFG_DEBUG = genid()
TUNNEL_BUILD_CFG_RELEASE = genid()
APP_CFG_LIST = genid()
TUNNEL_CFG_LIST = genid()
PROJECT_CFG_LIST = genid()
PROJECT_CFG_DEBUG = genid()
PROJECT_CFG_RELEASE = genid()
PBX_PROJECT = genid()
PBX_BUILD_FILE_APP = genid()
PBX_BUILD_FILE_TUNNEL = genid()
PBX_FILE_REF_APP = genid()
PBX_FILE_REF_TUNNEL = genid()
PBX_SOURCES_APP = genid()
PBX_SOURCES_TUNNEL = genid()
PBX_FRAMEWORKS_APP = genid()
PBX_FRAMEWORKS_TUNNEL = genid()
PBX_COPY_FILES = genid()
PBX_GROUP_MAIN = genid()
PBX_GROUP_APP = genid()
PBX_GROUP_TUNNEL = genid()
PBX_GROUP_PRODUCTS = genid()
PBX_CONTAINER_PROXY = genid()
PBX_TARGET_DEP = genid()
NATIVE_APP_TARGET = genid()
NATIVE_TUNNEL_TARGET = genid()

FILE_REF_BRIDGE_H = genid()
FILE_REF_PTP_SWIFT = genid()
FILE_REF_MAIN_M = genid()
FILE_REF_ZTNODEBRIDGE_H = genid()
FILE_REF_ZTNODEBRIDGE_MM = genid()
FILE_REF_APPDELEGATE = genid()
FILE_REF_SCENEDELEGATE = genid()
FILE_REF_VIEWCTRL = genid()
FILE_REF_ZTBRIDGE = genid()
FILE_REF_APP_BRIDGE_H = genid()

BUILD_FILE_BRIDGE_H = genid()
BUILD_FILE_PTP_SWIFT = genid()
BUILD_FILE_MAIN_M = genid()
BUILD_FILE_ZTNODEBRIDGE_MM = genid()
BUILD_FILE_APPDELEGATE = genid()
BUILD_FILE_SCENEDELEGATE = genid()
BUILD_FILE_VIEWCTRL = genid()
BUILD_FILE_ZTBRIDGE = genid()

SDK = "iphoneos"
MIN_VER = "15.0"

app_src = "ZeroTierOne"
tun_src = "ZeroTierOne/ZeroTierTunnel"

pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
		{BUILD_FILE_APPDELEGATE} /* AppDelegate.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_APPDELEGATE} /* AppDelegate.swift */; }};
		{BUILD_FILE_SCENEDELEGATE} /* SceneDelegate.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_SCENEDELEGATE} /* SceneDelegate.swift */; }};
		{BUILD_FILE_VIEWCTRL} /* ViewController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_VIEWCTRL} /* ViewController.swift */; }};
		{BUILD_FILE_ZTBRIDGE} /* ZeroTierBridge.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_ZTBRIDGE} /* ZeroTierBridge.swift */; }};
		{BUILD_FILE_PTP_SWIFT} /* PacketTunnelProvider.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_PTP_SWIFT} /* PacketTunnelProvider.swift */; }};
		{BUILD_FILE_MAIN_M} /* main.m in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_MAIN_M} /* main.m */; }};
		{BUILD_FILE_ZTNODEBRIDGE_MM} /* ZTNodeBridge.mm in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_ZTNODEBRIDGE_MM} /* ZTNodeBridge.mm */; }};
		{PBX_BUILD_FILE_APP} /* ZeroTierOne.app in Products */ = {{isa = PBXBuildFile; fileRef = {PBX_FILE_REF_APP} /* ZeroTierOne.app */; }};
		{PBX_BUILD_FILE_TUNNEL} /* ZeroTierTunnel.appex in Products */ = {{isa = PBXBuildFile; fileRef = {PBX_FILE_REF_TUNNEL} /* ZeroTierTunnel.appex */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{PBX_CONTAINER_PROXY} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {PBX_PROJECT} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {APP_TARGET_UUID};
			remoteInfo = ZeroTierOne;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{PBX_COPY_FILES} /* Embed App Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{PBX_BUILD_FILE_TUNNEL} /* ZeroTierTunnel.appex in Embed App Extensions */,
			);
			name = "Embed App Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{PBX_FILE_REF_APP} /* ZeroTierOne.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ZeroTierOne.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{PBX_FILE_REF_TUNNEL} /* ZeroTierTunnel.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ZeroTierTunnel.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{FILE_REF_APPDELEGATE} /* AppDelegate.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; }};
		{FILE_REF_SCENEDELEGATE} /* SceneDelegate.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SceneDelegate.swift; sourceTree = "<group>"; }};
		{FILE_REF_VIEWCTRL} /* ViewController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ViewController.swift; sourceTree = "<group>"; }};
		{FILE_REF_ZTBRIDGE} /* ZeroTierBridge.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ZeroTierBridge.swift; sourceTree = "<group>"; }};
		{FILE_REF_APP_BRIDGE_H} /* ZeroTierOne-Bridging-Header.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = "ZeroTierOne-Bridging-Header.h"; sourceTree = "<group>"; }};
		{FILE_REF_PTP_SWIFT} /* PacketTunnelProvider.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PacketTunnelProvider.swift; sourceTree = "<group>"; }};
		{FILE_REF_MAIN_M} /* main.m */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = main.m; sourceTree = "<group>"; }};
		{FILE_REF_ZTNODEBRIDGE_H} /* ZTNodeBridge.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = ZTNodeBridge.h; sourceTree = "<group>"; }};
		{FILE_REF_ZTNODEBRIDGE_MM} /* ZTNodeBridge.mm */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; path = ZTNodeBridge.mm; sourceTree = "<group>"; }};
		{FILE_REF_BRIDGE_H} /* ZeroTierTunnel-Bridging-Header.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = "ZeroTierTunnel-Bridging-Header.h"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{PBX_FRAMEWORKS_APP} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{PBX_FRAMEWORKS_TUNNEL} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{PBX_GROUP_MAIN} /* Main Group */ = {{
			isa = PBXGroup;
			children = (
				{PBX_GROUP_APP} /* ZeroTierOne */,
				{PBX_GROUP_PRODUCTS} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{PBX_GROUP_PRODUCTS} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{PBX_FILE_REF_APP} /* ZeroTierOne.app */,
				{PBX_FILE_REF_TUNNEL} /* ZeroTierTunnel.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{PBX_GROUP_APP} /* ZeroTierOne */ = {{
			isa = PBXGroup;
			children = (
				{FILE_REF_APPDELEGATE} /* AppDelegate.swift */,
				{FILE_REF_SCENEDELEGATE} /* SceneDelegate.swift */,
				{FILE_REF_VIEWCTRL} /* ViewController.swift */,
				{FILE_REF_ZTBRIDGE} /* ZeroTierBridge.swift */,
				{FILE_REF_APP_BRIDGE_H} /* ZeroTierOne-Bridging-Header.h */,
				{PBX_GROUP_TUNNEL} /* ZeroTierTunnel */,
			);
			path = ZeroTierOne;
			sourceTree = "<group>";
		}};
		{PBX_GROUP_TUNNEL} /* ZeroTierTunnel */ = {{
			isa = PBXGroup;
			children = (
				{FILE_REF_PTP_SWIFT} /* PacketTunnelProvider.swift */,
				{FILE_REF_MAIN_M} /* main.m */,
				{FILE_REF_ZTNODEBRIDGE_H} /* ZTNodeBridge.h */,
				{FILE_REF_ZTNODEBRIDGE_MM} /* ZTNodeBridge.mm */,
				{FILE_REF_BRIDGE_H} /* ZeroTierTunnel-Bridging-Header.h */,
			);
			path = ZeroTierTunnel;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{APP_TARGET_UUID} /* ZeroTierOne */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {APP_CFG_LIST} /* Build configuration list for PBXNativeTarget "ZeroTierOne" */;
			buildPhases = (
				{PBX_SOURCES_APP} /* Sources */,
				{PBX_FRAMEWORKS_APP} /* Frameworks */,
				{PBX_COPY_FILES} /* Embed App Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{PBX_TARGET_DEP} /* PBXTargetDependency */,
			);
			name = ZeroTierOne;
			productName = ZeroTierOne;
			productReference = {PBX_FILE_REF_APP} /* ZeroTierOne.app */;
			productType = "com.apple.product-type.application";
		}};
		{TUNNEL_TARGET_UUID} /* ZeroTierTunnel */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {TUNNEL_CFG_LIST} /* Build configuration list for PBXNativeTarget "ZeroTierTunnel" */;
			buildPhases = (
				{PBX_SOURCES_TUNNEL} /* Sources */,
				{PBX_FRAMEWORKS_TUNNEL} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ZeroTierTunnel;
			productName = ZeroTierTunnel;
			productReference = {PBX_FILE_REF_TUNNEL} /* ZeroTierTunnel.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PBX_PROJECT} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				TargetAttributes = {{
					{APP_TARGET_UUID} = {{
						CreatedOnToolsVersion = 15.4;
					}};
					{TUNNEL_TARGET_UUID} = {{
						CreatedOnToolsVersion = 15.4;
						SystemExtensionValue = 1;
					}};
				}};
			}};
			buildConfigurationList = {PROJECT_CFG_LIST} /* Build configuration list for PBXProject "ZeroTierOne" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				"zh-Hans",
				Base,
			);
			mainGroup = {PBX_GROUP_MAIN} /* Main Group */;
			productRefGroup = {PBX_GROUP_PRODUCTS} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{APP_TARGET_UUID} /* ZeroTierOne */,
				{TUNNEL_TARGET_UUID} /* ZeroTierTunnel */,
			);
		}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		{PBX_SOURCES_APP} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{BUILD_FILE_APPDELEGATE} /* AppDelegate.swift in Sources */,
				{BUILD_FILE_SCENEDELEGATE} /* SceneDelegate.swift in Sources */,
				{BUILD_FILE_VIEWCTRL} /* ViewController.swift in Sources */,
				{BUILD_FILE_ZTBRIDGE} /* ZeroTierBridge.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{PBX_SOURCES_TUNNEL} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{BUILD_FILE_PTP_SWIFT} /* PacketTunnelProvider.swift in Sources */,
				{BUILD_FILE_MAIN_M} /* main.m in Sources */,
				{BUILD_FILE_ZTNODEBRIDGE_MM} /* ZTNodeBridge.mm in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{PBX_TARGET_DEP} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {TUNNEL_TARGET_UUID} /* ZeroTierTunnel */;
			targetProxy = {PBX_CONTAINER_PROXY} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{PROJECT_CFG_DEBUG} /* Debug (Project) */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				IPHONEOS_DEPLOYMENT_TARGET = {MIN_VER};
				SDKROOT = iphoneos;
			}};
			name = Debug;
		}};
		{PROJECT_CFG_RELEASE} /* Release (Project) */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				IPHONEOS_DEPLOYMENT_TARGET = {MIN_VER};
				SDKROOT = iphoneos;
			}};
			name = Release;
		}};
		{APP_BUILD_CFG_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEBUG_INFORMATION_FORMAT = dwarf;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ZeroTierOne/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = {MIN_VER};
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 1.16.1;
				OTHER_LDFLAGS = "-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework NetworkExtension";
				PRODUCT_BUNDLE_IDENTIFIER = com.zerotier.ZeroTierOne;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				CODE_SIGN_ENTITLEMENTS = ZeroTierOne/ZeroTierOne.entitlements;
				SWIFT_OBJC_BRIDGING_HEADER = ZeroTierOne/ZeroTierOne-Bridging-Header.h;
			}};
			name = Debug;
		}};
		{APP_BUILD_CFG_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEBUG_INFORMATION_FORMAT = dwarf;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ZeroTierOne/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = {MIN_VER};
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
				MARKETING_VERSION = 1.16.1;
				OTHER_LDFLAGS = "-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework NetworkExtension";
				PRODUCT_BUNDLE_IDENTIFIER = com.zerotier.ZeroTierOne;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Osize";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				CODE_SIGN_ENTITLEMENTS = ZeroTierOne/ZeroTierOne.entitlements;
				SWIFT_OBJC_BRIDGING_HEADER = ZeroTierOne/ZeroTierOne-Bridging-Header.h;
			}};
			name = Release;
		}};
		{TUNNEL_BUILD_CFG_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEBUG_INFORMATION_FORMAT = dwarf;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ZeroTierOne/ZeroTierTunnel/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = {MIN_VER};
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
				MARKETING_VERSION = 1.16.1;
				OTHER_LDFLAGS = "-lc++ -framework NetworkExtension -framework Foundation -force_load $(PROJECT_DIR)/../libzerotiercore-ios.a";
				PRODUCT_BUNDLE_IDENTIFIER = com.zerotier.ZeroTierOne.Tunnel;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				CODE_SIGN_ENTITLEMENTS = ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel.entitlements;
				SWIFT_OBJC_BRIDGING_HEADER = ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel-Bridging-Header.h;
			}};
			name = Debug;
		}};
		{TUNNEL_BUILD_CFG_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEBUG_INFORMATION_FORMAT = dwarf;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ZeroTierOne/ZeroTierTunnel/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = {MIN_VER};
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";
				MARKETING_VERSION = 1.16.1;
				OTHER_LDFLAGS = "-lc++ -framework NetworkExtension -framework Foundation -force_load $(PROJECT_DIR)/../libzerotiercore-ios.a";
				PRODUCT_BUNDLE_IDENTIFIER = com.zerotier.ZeroTierOne.Tunnel;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Osize";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				CODE_SIGN_ENTITLEMENTS = ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel.entitlements;
				SWIFT_OBJC_BRIDGING_HEADER = ZeroTierOne/ZeroTierTunnel/ZeroTierTunnel-Bridging-Header.h;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{PROJECT_CFG_LIST} /* Build configuration list for PBXProject "ZeroTierOne" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{PROJECT_CFG_DEBUG} /* Debug */,
				{PROJECT_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{APP_CFG_LIST} /* Build configuration list for PBXNativeTarget "ZeroTierOne" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{APP_BUILD_CFG_DEBUG} /* Debug */,
				{APP_BUILD_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{TUNNEL_CFG_LIST} /* Build configuration list for PBXNativeTarget "ZeroTierTunnel" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{TUNNEL_BUILD_CFG_DEBUG} /* Debug */,
				{TUNNEL_BUILD_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {PBX_PROJECT} /* Project object */;
}}
"""

with open(os.path.join(xcode_dir, "project.pbxproj"), "w") as f:
    f.write(pbxproj)

print(f"Generated Xcode project at: {xcode_dir}")
