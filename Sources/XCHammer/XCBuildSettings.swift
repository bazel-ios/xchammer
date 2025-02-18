// Copyright 2018-present, Pinterest, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import ProjectSpec

struct XCSettingKey: CodingKey {
    let value: String

    public var stringValue: String {
        return value
    }

    public init?(stringValue: String) {
        value = stringValue
    }

    public var intValue: Int? {
        return nil
    }

    public init?(intValue _: Int) {
        value = ""
    }

    public func vary(on: String) -> XCSettingKey {
        return XCSettingKey(stringValue: value + "[" + on + "]")!
    }
}

protocol XCSettingStringEncodeable {
    func XCSettingString() -> String
}

extension First: XCSettingStringEncodeable {
    func XCSettingString() -> String {
        if let encVal = v as? XCSettingStringEncodeable {
            return encVal.XCSettingString()
        }
        return ""
    }
}

extension XCSettingStringEncodeable {
    func XCSettingString() -> String {
        return ""
    }
}

extension String: XCSettingStringEncodeable {
    func XCSettingString() -> String {
        return self
    }
}

extension Set: XCSettingStringEncodeable {
    func XCSettingString() -> String {
        return (self as! Set<String>).joined(separator: " ")
    }
}

extension Array: XCSettingStringEncodeable {
    func XCSettingString() -> String {
        return (self as! Array<String>).joined(separator: " ")
    }
}

extension OrderedArray: XCSettingStringEncodeable {
    func XCSettingString() -> String {
        return (self as! OrderedArray<String>).joined(separator: " ")
    }
}

typealias SettingValue = XCSettingStringEncodeable & Semigroup
struct Setting<T: SettingValue>: Semigroup {
    let base: T?
    let SDKiPhoneSimulator: T?
    let SDKiPhone: T?

    static func<>(lhs: Setting, rhs: Setting) -> Setting {
        return Setting(
            base: lhs.base <> rhs.base,
            SDKiPhoneSimulator: lhs.SDKiPhoneSimulator <> rhs.SDKiPhoneSimulator,
            SDKiPhone: lhs.SDKiPhone <> rhs.SDKiPhone)
    }

    init(base: T) {
        self.base = base
        SDKiPhoneSimulator = nil
        SDKiPhone = nil
    }

    init(base: T?, SDKiPhoneSimulator: T?, SDKiPhone: T?) {
        self.base = base
        self.SDKiPhoneSimulator = SDKiPhoneSimulator
        self.SDKiPhone = SDKiPhone
    }
}

extension KeyedEncodingContainer where K == XCSettingKey {

    mutating func encode<T: SettingValue>(_ value: Setting<T>, forKey strKey: XCSettingCodingKey) throws {
        guard let baseKey = XCSettingKey(stringValue: strKey.rawValue) else {
           fatalError("Invalid key \(String(describing: strKey))")
        }

        // Try encoding each setting for a key
        if let encVal = value.base?.XCSettingString(), encVal != ""  {
            try encode(encVal, forKey: baseKey)
        }

        if let encVal = value.SDKiPhoneSimulator?.XCSettingString(), encVal != "" {
	    try encode(encVal, forKey: baseKey.vary(on: "sdk=iphonesimulator*"))
        }

        if let encVal = value.SDKiPhone?.XCSettingString(), encVal.isEmpty == false  {
	    try encode(encVal, forKey: baseKey.vary(on: "sdk=iphoneos*"))
        }
    }
}

enum XCSettingCodingKey: String, CodingKey {
    // Add to this list the known XCConfig keys
    case cc = "CC"
    case swiftc = "SWIFT_EXEC"
    case ld = "LD"
    case libtool = "LIBTOOL"
    case copts = "WARNING_CFLAGS"
    case ldFlags = "OTHER_LDFLAGS"
    case productName = "PRODUCT_NAME"
    case moduleName = "PRODUCT_MODULE_NAME"
    case enableModules = "CLANG_ENABLE_MODULES"
    case headerSearchPaths = "HEADER_SEARCH_PATHS"
    case frameworkSearchPaths = "FRAMEWORK_SEARCH_PATHS"
    case librarySearchPaths = "LIBRARY_SEARCH_PATHS"
    case archs = "ARCHS"
    case validArchs = "VALID_ARCHS"
    case pch = "GCC_PREFIX_HEADER"
    case productBundleId = "PRODUCT_BUNDLE_IDENTIFIER"
    case codeSigningRequired = "CODE_SIGNING_REQUIRED"
    case codeSigningAllowed = "CODE_SIGNING_ALLOWED"
    case debugInformationFormat = "DEBUG_INFORMATION_FORMAT"
    case onlyActiveArch = "ONLY_ACTIVE_ARCH"
    case enableTestability = "ENABLE_TESTABILITY"
    case enableObjcArc = "CLANG_ENABLE_OBJC_ARC"
    case iOSDeploymentTarget = "IPHONEOS_DEPLOYMENT_TARGET"
    case macOSDeploymentTarget = "MACOSX_DEPLOYMENT_TARGET"
    case tvOSDeploymentTarget = "TVOS_DEPLOYMENT_TARGET"
    case watchOSDeploymentTarget = "WATCHOS_DEPLOYMENT_TARGET"
    case infoPlistFile = "INFOPLIST_FILE"
    case testHost = "TEST_HOST"
    case bundleLoader = "BUNDLE_LOADER"
    case appIconName = "ASSETCATALOG_COMPILER_APPICON_NAME"
    case enableBitcode = "ENABLE_BITCODE"
    case codeSigningIdentity = "CODE_SIGN_IDENTITY[sdk=iphoneos*]"
    case codeSigningStyle = "CODE_SIGN_STYLE"
    case moduleMapFile = "MODULEMAP_FILE"
    case testTargetName = "TEST_TARGET_NAME"
    case useHeaderMap = "USE_HEADERMAP"
    case swiftVersion = "SWIFT_VERSION"
    case swiftCopts = "OTHER_SWIFT_FLAGS"

    case pythonPath = "PYTHONPATH"
    case machoType = "MACH_O_TYPE"

    // Hammer Rules
    case codeSignEntitlementsFile = "HAMMER_ENTITLEMENTS_FILE"
    case mobileProvisionProfileFile = "HAMMER_PROFILE_FILE"
    case objcFrameworkVFSOverlay = "RULES_IOS_SWIFT_VFS_OVERLAY"
    case swiftFrameworkVFSOverlay = "RULES_IOS_OBJC_VFS_OVERLAY"
    case diagnosticFlags = "HAMMER_DIAGNOSTIC_FLAGS"
    case isBazel = "HAMMER_IS_BAZEL"
    case tulsiWR = "TULSI_WR"
    case sdkRoot = "SDKROOT"
    case targetedDeviceFamily = "TARGETED_DEVICE_FAMILY"
}


struct XCBuildSettings: Encodable {
    var cc: First<String>?
    var swiftc: First<String>?
    var ld: First<String>?
    var copts: [String] = []
    var productName: First<String>?
    var enableModules: First<String>?
    var headerSearchPaths: OrderedArray<String> = OrderedArray.empty
    var frameworkSearchPaths: OrderedArray<String> = OrderedArray.empty
    var librarySearchPaths: OrderedArray<String> = OrderedArray.empty
    var archs: First<String>?
    var validArchs: First<String>?
    var pch: First<String>?
    var productBundleId: First<String>?
    var debugInformationFormat: First<String>?
    var codeSigningRequired: First<String>?
    var codeSigningAllowed: First<String>? = First("NO")
    var onlyActiveArch: First<String>?
    var enableTestability: First<String>?
    var enableObjcArc: First<String>?
    var iOSDeploymentTarget: First<String>?
    var watchOSDeploymentTarget: First<String>?
    var tvOSDeploymentTarget: First<String>?
    var macOSDeploymentTarget: First<String>?
    var ldFlags: Setting<OrderedArray<String>> = Setting(base: OrderedArray.empty, SDKiPhoneSimulator: OrderedArray.empty, SDKiPhone: OrderedArray.empty)
    var infoPlistFile: First<String>?
    var testHost: First<String>?
    var bundleLoader: First<String>?
    var appIconName: First<String>?
    var enableBitcode: First<String>? = First("NO")
    var codeSigningIdentity: First<String>? = First("")
    var codeSigningStyle: First<String>? = First("manual")
    var mobileProvisionProfileFile: First<String>?
    var codeSignEntitlementsFile: First<String>?
    var objcFrameworkVFSOverlay: First<String>?
    var swiftFrameworkVFSOverlay: First<String>?
    var moduleMapFile: First<String>?
    var moduleName: First<String>?
    // Disable Xcode derived headermaps, be explicit to avoid divergence
    var useHeaderMap: First<String>? = First("NO")
    var swiftVersion: First<String>?
    var swiftCopts: [String] = []
    var testTargetName: First<String>?
    var pythonPath: First<String>?
    var machoType: First<String>?
    var sdkRoot: First<String>?
    var targetedDeviceFamily: OrderedArray<String> = OrderedArray.empty
    var isBazel: First<String> = First("NO")
    var diagnosticFlags: [String] = []

    func encode(to encoder: Encoder) throws {
        // `variableContainer` is an encoding container for `XCSettingKey`
        // First encode keys which can vary on platform
        var variableContainer = encoder.container(keyedBy: XCSettingKey.self)
        try variableContainer.encode(ldFlags, forKey: .ldFlags)

        // Require this for the simulator platform, which intermittently
        // requires this on Catalina, Xcode 11, and XCBuild
        if let codeSigningAllowed = self.codeSigningAllowed {
            let setting = Setting(base: codeSigningAllowed,
                SDKiPhoneSimulator: machoType?.v != "staticlib" ? First("YES") : First("NO"),
                SDKiPhone: codeSigningAllowed)
            try variableContainer.encode(setting, forKey: .codeSigningAllowed)
        }

        // `container` is an encoding container for `XCSettingKey`
        // next, encode all other kinds of keys
        var container = encoder.container(keyedBy: XCSettingCodingKey.self)
        try cc.map { try container.encode($0.v, forKey: .cc) }
        try swiftc.map { try container.encode($0.v, forKey: .swiftc) }
        try ld.map { try container.encode($0.v, forKey: .ld) }
        try ld.map { try container.encode($0.v, forKey: .libtool) }
        try container.encode(copts.joined(separator: " "), forKey: .copts)
        try container.encode(swiftCopts.joined(separator: " "), forKey: .swiftCopts)

        try container.encode(headerSearchPaths.joined(separator: " "), forKey: .headerSearchPaths)
        try container.encode(frameworkSearchPaths.joined(separator: " "), forKey: .frameworkSearchPaths)
        try container.encode(librarySearchPaths.joined(separator: " "), forKey: .librarySearchPaths)

        try productName.map { try container.encode($0.v, forKey: .productName) }
        try enableModules.map { try container.encode($0.v, forKey: .enableModules) }
        try archs.map { try container.encode($0.v, forKey: .archs) }
        try validArchs.map { try container.encode($0.v, forKey: .validArchs) }
        try pch.map { try container.encode($0.v, forKey: .pch) }
        try debugInformationFormat.map { try container.encode($0.v, forKey: .debugInformationFormat) }
        try productBundleId.map { try container.encode($0.v, forKey: .productBundleId) }
        try codeSigningRequired.map { try container.encode($0.v, forKey: .codeSigningRequired) }
        try codeSigningIdentity.map { try container.encode($0.v, forKey: .codeSigningIdentity) }
        try onlyActiveArch.map { try container.encode($0.v, forKey: .onlyActiveArch) }
        try enableTestability.map { try container.encode($0.v, forKey: .enableTestability) }
        try enableObjcArc.map { try container.encode($0.v, forKey: .enableObjcArc) }
        try iOSDeploymentTarget.map { try container.encode($0.v, forKey: .iOSDeploymentTarget) }
        try macOSDeploymentTarget.map { try container.encode($0.v, forKey: .macOSDeploymentTarget) }
        try tvOSDeploymentTarget.map { try container.encode($0.v, forKey: .tvOSDeploymentTarget) }
        try watchOSDeploymentTarget.map { try container.encode($0.v, forKey: .watchOSDeploymentTarget) }
        try infoPlistFile.map { try container.encode($0.v, forKey: .infoPlistFile) }
        try testHost.map { try container.encode($0.v, forKey: .testHost) }
        try bundleLoader.map { try container.encode($0.v, forKey: .bundleLoader) }
        try appIconName.map { try container.encode($0.v, forKey: .appIconName) }
        try enableBitcode.map { try container.encode($0.v, forKey: .enableBitcode) }
        try codeSigningIdentity.map { try container.encode($0.v, forKey: .codeSigningIdentity) }
        try codeSigningStyle.map { try container.encode($0.v, forKey: .codeSigningStyle) }
        try mobileProvisionProfileFile.map { try container.encode($0.v, forKey: .mobileProvisionProfileFile) }
        try objcFrameworkVFSOverlay.map { try container.encode($0.v, forKey: .objcFrameworkVFSOverlay) }
        try swiftFrameworkVFSOverlay.map { try container.encode($0.v, forKey: .swiftFrameworkVFSOverlay) }
        try codeSignEntitlementsFile.map { try container.encode($0.v, forKey: .codeSignEntitlementsFile) }
        try moduleMapFile.map { try container.encode($0.v, forKey: .moduleMapFile) }
        try moduleName.map { try container.encode($0.v, forKey: .moduleName) }
        try useHeaderMap.map { try container.encode($0.v, forKey: .useHeaderMap) }
        try testTargetName.map { try container.encode($0.v, forKey: .testTargetName) }
        try pythonPath.map { try container.encode($0.v, forKey: .pythonPath) }
        try machoType.map { try container.encode($0.v, forKey: .machoType) }
        try sdkRoot.map { try container.encode($0.v, forKey: .sdkRoot) }
        try container.encode(targetedDeviceFamily.joined(separator: ","), forKey: .targetedDeviceFamily)
        try swiftVersion.map { try container.encode($0.v, forKey: .swiftVersion) }
        try container.encode(isBazel.v, forKey: .isBazel)

        // XCHammer only supports Xcode projects at the root directory
        try container.encode("$SOURCE_ROOT", forKey: .tulsiWR)
        try container.encode(diagnosticFlags.joined(separator: " "), forKey: .diagnosticFlags)
    }
}

extension XCBuildSettings: Monoid {
    static var empty: XCBuildSettings {
        return XCBuildSettings()
    }

    static func<>(lhs: XCBuildSettings, rhs: XCBuildSettings) -> XCBuildSettings {
        return XCBuildSettings(
            cc: lhs.cc <> rhs.cc,
            swiftc: lhs.swiftc <> rhs.swiftc,
            ld: lhs.ld <> rhs.ld,
            copts: lhs.copts <> rhs.copts,
            productName: lhs.productName <> rhs.productName,
            enableModules: lhs.enableModules <> rhs.enableModules,
            headerSearchPaths: lhs.headerSearchPaths <> rhs.headerSearchPaths,
            frameworkSearchPaths: lhs.frameworkSearchPaths <> rhs.frameworkSearchPaths,
            librarySearchPaths: lhs.librarySearchPaths <> rhs.librarySearchPaths,
            archs: lhs.archs <> rhs.archs,
            validArchs: lhs.validArchs <> rhs.validArchs,
            pch: lhs.pch <> rhs.pch,
            productBundleId: lhs.productBundleId <> rhs.productBundleId,
            debugInformationFormat: lhs.debugInformationFormat <> rhs.debugInformationFormat,
            codeSigningRequired: lhs.codeSigningRequired <> rhs.codeSigningRequired,
            codeSigningAllowed: lhs.codeSigningAllowed <> rhs.codeSigningAllowed,
            onlyActiveArch: lhs.onlyActiveArch <> rhs.onlyActiveArch,
            enableTestability: lhs.enableTestability <> rhs.enableTestability,
            enableObjcArc: lhs.enableObjcArc <> rhs.enableObjcArc,
            iOSDeploymentTarget: lhs.iOSDeploymentTarget <> rhs.iOSDeploymentTarget,
            watchOSDeploymentTarget: lhs.watchOSDeploymentTarget <> rhs.watchOSDeploymentTarget,
            tvOSDeploymentTarget: lhs.tvOSDeploymentTarget <> rhs.tvOSDeploymentTarget,
            macOSDeploymentTarget: lhs.macOSDeploymentTarget <> rhs.macOSDeploymentTarget,
            ldFlags: lhs.ldFlags <> rhs.ldFlags,
            infoPlistFile: lhs.infoPlistFile <> rhs.infoPlistFile,
            testHost: lhs.testHost <> rhs.testHost,
            bundleLoader: lhs.bundleLoader <> rhs.bundleLoader,
            appIconName: lhs.appIconName <> rhs.appIconName,
            enableBitcode: lhs.enableBitcode <> rhs.enableBitcode,
            codeSigningIdentity: lhs.codeSigningIdentity <> rhs.codeSigningIdentity,
            codeSigningStyle: lhs.codeSigningStyle <> rhs.codeSigningStyle,
            mobileProvisionProfileFile: lhs.mobileProvisionProfileFile <> rhs.mobileProvisionProfileFile,
            codeSignEntitlementsFile: lhs.codeSignEntitlementsFile <> rhs.codeSignEntitlementsFile,
            objcFrameworkVFSOverlay: lhs.objcFrameworkVFSOverlay <> rhs.objcFrameworkVFSOverlay,
            swiftFrameworkVFSOverlay: lhs.swiftFrameworkVFSOverlay <> rhs.swiftFrameworkVFSOverlay,
            moduleMapFile: lhs.moduleMapFile <> rhs.moduleMapFile,
            moduleName: lhs.moduleName <> rhs.moduleName,
            useHeaderMap: lhs.useHeaderMap <> rhs.useHeaderMap,
            swiftVersion: lhs.swiftVersion <> rhs.swiftVersion,
            swiftCopts: lhs.swiftCopts <> rhs.swiftCopts,
            testTargetName: lhs.testTargetName <> rhs.testTargetName,
            pythonPath: lhs.pythonPath <> rhs.pythonPath,
            machoType: lhs.machoType <> rhs.machoType,
            sdkRoot: lhs.sdkRoot <> rhs.sdkRoot,
            targetedDeviceFamily: lhs.targetedDeviceFamily <>
                rhs.targetedDeviceFamily,
            isBazel: lhs.isBazel <> rhs.isBazel,
            diagnosticFlags: lhs.diagnosticFlags <> rhs.diagnosticFlags
        )
    }

    /// We use this to allocate a ProjectSpec.Settings
    /// TODO: Write a method to output that directly
    func getJSON() -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try? encoder.encode(self)
        let value = try? JSONSerialization.jsonObject(with: data ?? Data())
        return value as? [String: Any] ?? [:]
    }
}

/// Mark - XcodeGen support

func makeXcodeGenSettings(from settings: XCBuildSettings) -> ProjectSpec.Settings {
    return Settings(dictionary: settings.getJSON())
}

