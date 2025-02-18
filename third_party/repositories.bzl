load(
    "@bazel_tools//tools/build_defs/repo:git.bzl",
    "git_repository",
    "new_git_repository",
)

NAMESPACE_PREFIX = "xchammer-"

def namespaced_name(name):
    if name.startswith("@"):
        return name.replace("@", "@%s" % NAMESPACE_PREFIX)
    return NAMESPACE_PREFIX + name

def namespaced_dep_name(name):
    if name.startswith("@"):
        return name.replace("@", "@%s" % NAMESPACE_PREFIX)
    return name

def namespaced_new_git_repository(name, **kwargs):
    new_git_repository(
        name = namespaced_name(name),
        **kwargs
    )

def namespaced_git_repository(name, **kwargs):
    git_repository(
        name = namespaced_name(name),
        **kwargs
    )

def namespaced_build_file(libs):
    return """
package(default_visibility = ["//visibility:public"])
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_c_module",
"swift_library")
""" + "\n\n".join(libs)

def namespaced_swift_c_library(name, srcs, hdrs, includes, module_map):
    return """
objc_library(
  name = "{name}Lib",
  srcs = glob([
    {srcs}
  ]),
  hdrs = glob([
    {hdrs}
  ]),
  includes = [
    {includes}
  ]
)

swift_c_module(
  name = "{name}",
  deps = [":{name}Lib"],
  module_map = "{module_map}",
  module_name = "{name}",
)
""".format(**dict(
        name = name,
        srcs = ",\n".join(['"%s"' % x for x in srcs]),
        hdrs = ",\n".join(['"%s"' % x for x in hdrs]),
        includes = ",\n".join(['"%s"' % x for x in includes]),
        module_map = module_map,
    ))

def namespaced_swift_library(name, srcs, deps = None, defines = None, copts = []):
    deps = [] if deps == None else deps
    defines = [] if defines == None else defines
    return """
swift_library(
    name = "{name}",
    srcs = glob([{srcs}]),
    module_name = "{name}",
    deps = [{deps}],
    defines = [{defines}],
    copts = ["-DSWIFT_PACKAGE", {copts}],
)""".format(**dict(
        name = name,
        srcs = ",\n".join(['"%s"' % x for x in srcs]),
        defines = ",\n".join(['"%s"' % x for x in defines]),
        deps = ",\n".join(['"%s"' % namespaced_dep_name(x) for x in deps]),
        copts = ",\n".join(['"%s"' % x for x in copts]),
    ))

def xchammer_dependencies():
    """Fetches repositories that are dependencies of the xchammer workspace.

    Users should call this macro in their `WORKSPACE` to ensure that all of the
    dependencies of xchammer are downloaded and that they are isolated from
    changes to those dependencies.
    """
    namespaced_new_git_repository(
        name = "AEXML",
        remote = "https://github.com/tadija/AEXML.git",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "AEXML",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
        commit = "38f7d00b23ecd891e1ee656fa6aeebd6ba04ecc3",
    )

    namespaced_new_git_repository(
        name = "Commandant",
        remote = "https://github.com/Carthage/Commandant.git",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Commandant",
                srcs = ["Sources/**/*.swift"],
                deps = [
                    "@Result//:Result",
                ],
            ),
        ]),
        commit = "2cd0210f897fe46c6ce42f52ccfa72b3bbb621a0",
    )

    namespaced_new_git_repository(
        name = "Commander",
        remote = "https://github.com/kylef/Commander.git",
        commit = "e5b50ad7b2e91eeb828393e89b03577b16be7db9",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Commander",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "XcodeCompilationDatabase",
        remote = "https://github.com/jerrymarino/XcodeCompilationDatabase.git",
        commit = "598725fdcb37138e9b4ec8379653cbb99f2605dd",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "XcodeCompilationDatabaseCore",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "JSONUtilities",
        remote = "https://github.com/yonaskolb/JSONUtilities.git",
        commit = "128d2ffc22467f69569ef8ff971683e2393191a0",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "JSONUtilities",
                srcs = ["Sources/**/*.swift"],
                copts = [
                    "-swift-version",
                    "4.2",
                ],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Nimble",
        remote = "https://github.com/Quick/Nimble.git",
        commit = "43304bf2b1579fd555f2fdd51742771c1e4f2b98",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Nimble",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "PathKit",
        remote = "https://github.com/kylef/PathKit.git",
        commit = "e2f5be30e4c8f531c9c1e8765aa7b71c0a45d7a0",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "PathKit",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Quick",
        remote = "https://github.com/Quick/Quick.git",
        commit = "20b340da40ccd2bf62ea1e803e6b8f7933f7515e",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Quick",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Rainbow",
        remote = "https://github.com/onevcat/Rainbow.git",
        commit = "9c52c1952e9b2305d4507cf473392ac2d7c9b155",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Rainbow",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Result",
        remote = "https://github.com/antitypical/Result.git",
        commit = "2ca499ba456795616fbc471561ff1d963e6ae160",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Result",
                srcs = ["Result/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "ShellOut",
        remote = "https://github.com/JohnSundell/ShellOut.git",
        commit = "d3d54ce662dfee7fef619330b71d251b8d4869f9",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "ShellOut",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Spectre",
        remote = "https://github.com/kylef/Spectre.git",
        commit = "f14ff47f45642aa5703900980b014c2e9394b6e5",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Spectre",
                srcs = ["Sources/**/*.swift"],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "SwiftShell",
        remote = "https://github.com/kareman/SwiftShell",
        commit = "99680b2efc7c7dbcace1da0b3979d266f02e213c",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "SwiftShell",
                srcs = ["Sources/**/*.swift"],
                copts = [
                ],
            ),
        ]),
    )

    namespaced_git_repository(
        name = "Tulsi",
        remote = "https://github.com/bazel-ios/tulsi.git",
        # These tags are based on the bazel-version - see XCHammer docs for
        # convention. It cherry-picks all changes to HEAD at a give bazel
        # release, then adds changes to this tag for the Bazel release in
        # question
        # Persisted on github tag=rules_ios-5.0.0,
        commit = "a90a2925d24cc02174188a9365bc84f9c2cb37f4",
    )

    namespaced_new_git_repository(
        name = "XcodeGen",
        remote = "https://github.com/yonaskolb/XcodeGen.git",
        commit = "047e9968d6e5308df73126d72cb42af8527a644c",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "XcodeGenKit",
                srcs = ["Sources/XcodeGenKit/**/*.swift"],
                deps = [
                    ":ProjectSpec",
                    "@JSONUtilities//:JSONUtilities",
                    "@PathKit//:PathKit",
                    "@Yams//:Yams",
                    ":XcodeGenCore",
                ],
            ),
            namespaced_swift_library(
                name = "XcodeGenCore",
                srcs = ["Sources/XcodeGenCore/**/*.swift"],
                deps = [
                    "@PathKit//:PathKit",
                    "@Yams//:Yams",
                ],
            ),
            namespaced_swift_library(
                name = "ProjectSpec",
                srcs = ["Sources/ProjectSpec/**/*.swift"],
                deps = [
                    "@JSONUtilities//:JSONUtilities",
                    "@XcodeProj//:XcodeProj",
                    "@Yams//:Yams",
                    "@Version//:Version",
                    ":XcodeGenCore",
                ],
            ),
        ]),
    )
    namespaced_new_git_repository(
        name = "XcodeProj",
        remote = "https://github.com/tuist/xcodeproj.git",
        commit = "aa2a42c7a744ca18b5918771fdd6cf40f9753db5",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "XcodeProj",
                srcs = ["Sources/**/*.swift"],
                deps = [
                    "@AEXML//:AEXML",
                    "@PathKit//:PathKit",
                    "@SwiftShell//:SwiftShell",
                    "@Version//:Version",
                    "@GraphViz//:DOT",
                ],
                copts = [
                    "-swift-version",
                    "5",
                ],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "GraphViz",
        remote = "https://github.com/SwiftDocOrg/GraphViz.git",
        commit = "70bebcf4597b9ce33e19816d6bbd4ba9b7bdf038",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "DOT",
                srcs = ["Sources/DOT/**/*.swift"],
                deps = [":GraphViz"],
                copts = [
                    "-swift-version",
                    "5",
                ],
            ),
            namespaced_swift_library(
                name = "GraphVizBuilder",
                srcs = ["Sources/GraphVizBuilder/**/*.swift"],
                deps = [":GraphViz"],
                copts = [
                    "-swift-version",
                    "5",
                ],
            ),
            namespaced_swift_library(
                name = "GraphViz",
                srcs = ["Sources/GraphViz/**/*.swift"],
                deps = [],
                copts = [
                    "-swift-version",
                    "5",
                ],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Version",
        remote = "https://github.com/mxcl/Version.git",
        commit = "a94b48f36763c05629fc102837398505032dead9",
        build_file_content = namespaced_build_file([
            namespaced_swift_library(
                name = "Version",
                srcs = ["Sources/**/*.swift"],
                deps = [],
                copts = [
                    "-swift-version",
                    "5",
                ],
            ),
        ]),
    )

    namespaced_new_git_repository(
        name = "Yams",
        remote = "https://github.com/jpsim/Yams.git",
        commit = "9ff1cc9327586db4e0c8f46f064b6a82ec1566fa",
        patch_cmds = [
            """
echo '
module CYaml {
    umbrella header "CYaml.h"
    export *
}
' > Sources/CYaml/include/Yams.modulemap
""",
        ],
        build_file_content = namespaced_build_file([
            namespaced_swift_c_library(
                name = "CYaml",
                srcs = [
                    "Sources/CYaml/src/*.c",
                    "Sources/CYaml/src/*.h",
                ],
                hdrs = [
                    "Sources/CYaml/include/*.h",
                ],
                includes = ["Sources/CYaml/include"],
                module_map = "Sources/CYaml/include/Yams.modulemap",
            ),
            namespaced_swift_library(
                name = "Yams",
                srcs = ["Sources/Yams/*.swift"],
                deps = [":CYaml", ":CYamlLib"],
                defines = ["SWIFT_PACKAGE"],
            ),
        ]),
    )
