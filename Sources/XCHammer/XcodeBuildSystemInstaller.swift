// Copyright 2019-present, Pinterest, Inc.
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
import Result
import ShellOut

enum XcodeBuildSystemInstaller {
    /// Installs the Xcode build system contained inside the bundle if necessary
    /// It noops quickly if the installed plist doesnt match in order to be ran
    /// inline with builds or project generation

    static let servicePath =
            "/Contents/SharedFrameworks/XCBuild.framework/PlugIns/XCBBuildService.bundle/Contents/MacOS/XCBBuildService"

    static let supportedXcodeVersions = ["11", "12", "13"]

    static func installIfNecessary() -> Result<(), CommandError> {
        let bundle = Bundle.main
        let buildkitBundlePath = bundle.path(forResource: "XCBuildKit", ofType: "bundle")!
        let installedAppDir = "/opt/XCBuildKit/XCBuildKit.app"
        let plistPath = buildkitBundlePath + "/BuildInfo.plist"
        let pkgVersion = getVersion(path: plistPath)

        // Check each Xcode that's compatible with this version and verify if
        // it's installed
        var hasUnlinkedXcodes = false

        do {
            hasUnlinkedXcodes = try getXcodes(withBuildSystemInstalled: false).count > 0
        } catch {
            return .failure(.basic(error.localizedDescription))
        }

        let installedPlistPath = installedAppDir + "/Contents/Info.plist"
        if hasUnlinkedXcodes || pkgVersion != getVersion(path: installedPlistPath) {
            print("xchammer requires install")
            let installerPath = buildkitBundlePath + "/BazelBuildServiceInstaller.pkg"
            let script = "installer -pkg \(installerPath) -target /"
            guard ShellOutWithSudo(script) == 0 else {
                return .failure(.basic("failed to install. please see /var/log/install.log for more info"))
            }
        }
        return .success(())
    }

    static func uninstallIfNecessary() -> Result<(), CommandError> {
        do {
            let needsUninstalls = try getXcodes(withBuildSystemInstalled: true)

            for xcode in needsUninstalls {
                let defaultBsTempPath = String(xcode + servicePath + ".default")
                let defaultBsOriginalPath = String(xcode + servicePath)

                guard FileManager.default.fileExists(atPath: defaultBsTempPath) else {
                    return .failure(.basic("Default build system not found at temporary path: \(defaultBsTempPath)"))
                }

                try FileManager.default.removeItem(atPath: defaultBsOriginalPath)
                try FileManager.default.moveItem(atPath: defaultBsTempPath, toPath: defaultBsOriginalPath)
            }
        } catch {
            return .failure(.basic(error.localizedDescription))
        }

        return .success(())
    }

    static func getVersion(path: String) -> String? {
        guard let plistXML = FileManager.default.contents(atPath: path) else {
            return nil
        }
        var propertyListFormat =  PropertyListSerialization.PropertyListFormat.xml
        guard let plistData: [String: AnyObject] = try? PropertyListSerialization.propertyList(from:
            plistXML, options: .mutableContainersAndLeaves,
            format: &propertyListFormat) as! [String:AnyObject] else {
            fatalError("Can't read plist")
        }
        // This is determined by the ref of xcbuildkit either built by it's
        // self, or the repository_rule that defined it.
        // https://github.com/jerrymarino/xcbuildkit/blob/master/BUILD#L101
        return plistData["BUILD_COMMIT"] as? String
    }

    private static func getXcodes(withBuildSystemInstalled filterInstalled: Bool) throws -> [String] {
        let bundle = Bundle.main
        let buildkitBundlePath = bundle.path(forResource: "XCBuildKit", ofType: "bundle")!
        let xcodeLocatorPath =  buildkitBundlePath + "/xcode-locator"
        let installedAppDir = "/opt/XCBuildKit/XCBuildKit.app"
        let installedBinPath =  installedAppDir + "/Contents/MacOS/BazelBuildService"

        let xcodeLocatorCmd = xcodeLocatorPath + " 2>&1"
        let xcodeLocatorOutput = try shellOut(to: xcodeLocatorCmd)
        var allXcodes: String = ""
        // Loop through supported Xcode versions and extract the path if present
        for xcodeVersion in supportedXcodeVersions {
            let xcodePathCmd = "printf '%s\n' \"\(xcodeLocatorOutput)\" | grep \"expanded=\(xcodeVersion)\" | sed -e 's,.*file://,,g' -e 's,/:.*,,g'"
            let xcodePathOutput = try shellOut(to: xcodePathCmd)

            if xcodePathOutput.count > 0 {
                allXcodes += "\n\(xcodePathOutput)"
            }
        }

        // Returns an array of [/Path/To/Xcode.app/]
        let xcodes = allXcodes.split(separator: "\n").map { String($0) }
        guard xcodes.count > 0 else {
            print("warning: No Xcodes installed")
            return []
        }

        // Based on what was requested in `filterInstalled` returns Xcodes with build system installed or Xcodes
        // with build system not installed. See usage in `installIfNecessary` and `uninstallIfNecessary` above.
        return xcodes.filter {
            xcode in
            let bsPath = String(xcode + servicePath)
            guard let link = try? FileManager.default.destinationOfSymbolicLink(atPath: bsPath) else {
                return filterInstalled ? false : true
            }
            guard link == installedBinPath else {
                return filterInstalled ? false : true
            }
            return filterInstalled ? true : false
        }
    }
}

/// Disable echo to prevent exposing stdin.
/// This behaves nearly identical but swallows the newline before
/// "Sorry, please try again"
func disableEcho(fileHandle: FileHandle) -> termios {
    let struct_pointer = UnsafeMutablePointer<termios>.allocate(capacity: 1)
    var raw = struct_pointer.pointee
    struct_pointer.deallocate()

    tcgetattr(fileHandle.fileDescriptor, &raw)
    let original = raw
    raw.c_lflag &= ~(UInt(ECHO))
    raw.c_lflag &= (UInt(ECHOE |  ECHONL | ICANON | ECHOCTL))
    tcsetattr(fileHandle.fileDescriptor, TCSAFLUSH, &raw);
    return original
}

func restoreEcho(fileHandle: FileHandle, originalTerm: termios) {
    var term = originalTerm
    tcsetattr(fileHandle.fileDescriptor, TCSAFLUSH, &term);
}

func ShellOutWithSudo(_ script: String) -> Int32 {
    let process = Process()
    process.environment = ProcessInfo.processInfo.environment
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = stdin
    process.launchPath = "/bin/bash"

    // Unless this is running 
    let originalTerm = disableEcho(fileHandle: FileHandle.standardInput)
    defer {
        restoreEcho(fileHandle: FileHandle.standardInput, originalTerm: originalTerm)
    }

    // Pipe fitting:
    // pipe stdin to the process stdin
    FileHandle.standardInput.readabilityHandler = {
        stdin.fileHandleForWriting.write($0.availableData)
    }

    // pipe stdout to our stdout
    stderr.fileHandleForReading.readabilityHandler = {
        FileHandle.standardError.write($0.availableData)
    }

    // pipe stderr to our stdout
    stdout.fileHandleForReading.readabilityHandler = {
        FileHandle.standardOutput.write($0.availableData)
    }
    process.arguments = ["-c", "sudo -S \(script)"] 
    process.launch()
    process.waitUntilExit()
    return process.terminationStatus
}
