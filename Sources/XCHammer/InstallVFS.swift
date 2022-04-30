/// Quick helper to copy relevant files into rules_ios frameworks
/// mainly it's ran prior to compiling.
import Foundation
import Result
import PathKit

struct VFSRoot: Codable {
  enum CodingKeys : String, CodingKey {
        case name = "name"
        case type = "type"
        case contents = "contents"
        case externalContents = "external-contents"
    }

    var name: String
    var type: String // directory | file
    var contents: [VFSRoot]? // directory | file
    var externalContents: String? // directory | file
}

struct VFSFile: Codable {
    var roots: [VFSRoot]
}

func findRoot(name: String, roots: [VFSRoot]) -> VFSRoot? {
    for root in roots {
        if root.name == name {
            return root
        }
    }
    return nil
}

/// Takes something like 
/// -DSome -vfsoverlay/some/other -DNone and parses the VFS
func getVFSPath(compilerFlags: String) -> String? {
    guard let startIdx = compilerFlags.range(of: "vfsoverlay") else {
        return nil
    }

    var foundVFS = compilerFlags[startIdx.upperBound...]
    if let terminator = foundVFS.range(of: " ") {
        foundVFS = foundVFS[..<terminator.lowerBound]
    }
    return String(foundVFS)
}

func doInstall(targetBuildDir: Path, frameworkName: String, compilerFlags: String) throws {
    guard let vfsPath = getVFSPath(compilerFlags: compilerFlags) else {
        print("warning: no VFS - skipping copy files for framework \(frameworkName)")
        return
    }
    let jsonData = try Path(vfsPath).read()
    let vfsFile = try JSONDecoder().decode(VFSFile.self, from: jsonData)

    guard let frameworks = findRoot(name: "/build_bazel_rules_ios/frameworks",
                                    roots: vfsFile.roots) else {
        print("warning: no framwork entry - skiping copy files for framework \(frameworkName)")
        return
    }

    // Note: This assertion works for rules_ios - see other comment in
    // XcodeTarget.swift relating to it.
    guard let fwRoot = findRoot(name: "\(frameworkName).framework", roots:
                                frameworks.contents ?? []) else {
        fatalError("Can't find framework \(frameworkName)")
    }

    // Resolve subset of roots relative to the VFS
    FileManager.default.changeCurrentDirectoryPath(dirname(vfsPath))

    let dstFrameworkPath = targetBuildDir + Path(frameworkName + ".framework")

    // Consider unifying these 3 looping bodies after addressing the comments
    if let headers = findRoot(name: "Headers", roots: fwRoot.contents ?? []) {
        try? FileManager.default.createDirectory(atPath: (dstFrameworkPath + Path("Headers")).string,
                    withIntermediateDirectories: true,
                    attributes: [:])
        headers.contents?.forEach  { header in
            guard let headerPathS = header.externalContents  else {
                return
            }
            let headerPath = Path(headerPathS)
            let fwHeader = dstFrameworkPath + Path("Headers") + Path(headerPath.lastComponent)
            try? FileManager.default.createSymbolicLink(at: fwHeader.url, 
                                    withDestinationURL: headerPath.url)
        }
    }

    if let privateHeaders = findRoot(name: "PrivateHeaders", roots: fwRoot.contents ?? []) {
        try? FileManager.default.createDirectory(atPath: (dstFrameworkPath + Path("PrivateHeaders")).string,
                    withIntermediateDirectories: true,
                    attributes: [:])
        privateHeaders.contents?.forEach  { header in
            guard let headerPathS = header.externalContents  else {
                return
            }
            let headerPath = Path(headerPathS)
            let fwHeader = dstFrameworkPath + Path("PrivateHeaders") + Path(headerPath.lastComponent)
            try? FileManager.default.createSymbolicLink(at: fwHeader.url, 
                                    withDestinationURL: headerPath.url)
        }
    }

    try? FileManager.default.createDirectory(atPath: (dstFrameworkPath + Path("Modules")).string,
                withIntermediateDirectories: true,
                attributes: [:])

    if let modules = findRoot(name: "Modules", roots:
                                fwRoot.contents ?? []) {
        modules.contents?.forEach  { header in
            guard let headerPathS = header.externalContents  else {
                return
            }
            // FIXME: This is wrong! use the name before merging this
            let dstName: String
            let headerPath = Path(headerPathS)
            if headerPath.extension == "modulemap" {
                dstName = "module.modulemap"
            } else {
                dstName = headerPath.lastComponent
            }

            let fwHeader = dstFrameworkPath + Path("Modules") + Path(dstName)
            try? FileManager.default.createSymbolicLink(at: fwHeader.url, 
                                    withDestinationURL: headerPath.url)
        }
    }
}

func installVFS(targetBuildDir: Path, frameworkName: String, compilerFlags: String) -> Result<(), CommandError> {
    do {
        try doInstall(targetBuildDir: targetBuildDir, frameworkName:
                      frameworkName, compilerFlags: compilerFlags)
        return .success(())
    } catch {
        return .failure(.swiftException(error))
    }
}
