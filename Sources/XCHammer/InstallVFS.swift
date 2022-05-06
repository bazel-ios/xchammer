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


func doInstall(targetBuildDir: Path, frameworkName: String, vfsPath: String) throws {
    let jsonData = try Path(vfsPath).read()
    let vfsFile = try JSONDecoder().decode(VFSFile.self, from: jsonData)

    guard let frameworks = findRoot(name: "/build_bazel_rules_ios/frameworks",
                                    roots: vfsFile.roots) else {
        print("warning: no framwork entry - skiping copy files for framework \(frameworkName)")
        return
    }

    // Note: This could be asserted works for rules_ios - see other comment in
    // XcodeTarget.swift relating to it. This breaks for .apps right now and
    // hits other problems
    guard let fwRoot = findRoot(name: "\(frameworkName).framework", roots:
                                frameworks.contents ?? []) else {
        print("warning: Can't find framework \(frameworkName)")
        return
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
            guard let externalContents = header.externalContents else {
                return
            }
            let headerPath = Path(externalContents)
            let dstHeader = dstFrameworkPath + Path("Headers") + Path(headerPath.lastComponent)
            try? FileManager.default.removeItem(at: dstHeader.url)
            try? FileManager.default.createSymbolicLink(atPath: dstHeader.string, 
                                    withDestinationPath: getVFSEntryPath(headerPath))
        }
    }

    if let privateHeaders = findRoot(name: "PrivateHeaders", roots: fwRoot.contents ?? []) {
        try? FileManager.default.createDirectory(atPath: (dstFrameworkPath + Path("PrivateHeaders")).string,
                    withIntermediateDirectories: true,
                    attributes: [:])
        privateHeaders.contents?.forEach  { header in
            guard let externalContents = header.externalContents else {
                return
            }
            let headerPath = Path(externalContents)
            let dstHeader = dstFrameworkPath + Path("PrivateHeaders") + Path(headerPath.lastComponent)
            try? FileManager.default.removeItem(at: dstHeader.url)
            try? FileManager.default.createSymbolicLink(atPath: dstHeader.string, 
                                    withDestinationPath: getVFSEntryPath(headerPath))
        }
    }

    // return an absolute path of a file in the VFS
    func getVFSEntryPath(_ vfsIPath: Path) -> String {
        let locRootPath = ProcessInfo.processInfo.environment["LOCROOT"] ?? "" 
        let suffix = vfsIPath.absolute().string.replacingOccurrences(of: "../", with:"")
        return suffix.hasPrefix(locRootPath) ? suffix : locRootPath + suffix
    }

    try? FileManager.default.createDirectory(atPath: (dstFrameworkPath + Path("Modules")).string,
                withIntermediateDirectories: true,
                attributes: [:])

    if let modules = findRoot(name: "Modules", roots:
                                fwRoot.contents ?? []) {
        modules.contents?.forEach  { header in
            guard let externalContents = header.externalContents else {
                return
            }
            let headerPath = Path(externalContents)
            let dstName = header.name
            let dstHeader = dstFrameworkPath + Path("Modules") + Path(dstName)
            try? FileManager.default.removeItem(at: dstHeader.url)
            try? FileManager.default.createSymbolicLink(atPath: dstHeader.string, 
                                    withDestinationPath: getVFSEntryPath(headerPath))
        }
    }
}

func installVFS(targetBuildDir: Path, frameworkName: String, vfsPath: String) -> Result<(), CommandError> {
    do {
        try doInstall(targetBuildDir: targetBuildDir, frameworkName:
                      frameworkName, vfsPath: vfsPath)
        return .success(())
    } catch {
        return .failure(.swiftException(error))
    }
}
