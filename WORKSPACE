workspace(name = "xchammer")

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")

git_repository(
    name = "build_bazel_rules_apple",
    commit = "7115f0188d141d57d64a6875735847c975956dae",
    remote = "https://github.com/bazelbuild/rules_apple.git",
)

load(
    "@build_bazel_rules_apple//apple:repositories.bzl",
    "apple_rules_dependencies",
)

apple_rules_dependencies()

git_repository(
    name = "build_bazel_rules_swift",
    commit = "22192877498705ff1adbecd820fdc2724414b0b2",
    remote = "https://github.com/bazelbuild/rules_swift.git",
)

load(
    "@build_bazel_rules_swift//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()

load(
    "@build_bazel_rules_swift//swift:extras.bzl",
    "swift_rules_extra_dependencies",
)

swift_rules_extra_dependencies()

load(
    "@build_bazel_apple_support//lib:repositories.bzl",
    "apple_support_dependencies",
)

apple_support_dependencies()

load(
    "@com_google_protobuf//:protobuf_deps.bzl",
    "protobuf_deps",
)

protobuf_deps()

http_file(
    name = "xctestrunner",
    executable = 1,
    urls = ["https://github.com/google/xctestrunner/releases/download/0.2.6/ios_test_runner.par"],
)

## SPM Dependencies

load("//third_party:repositories.bzl", "xchammer_dependencies")

xchammer_dependencies()

## Build system
# This needs to be manually imported
# https://github.com/bazelbuild/bazel/issues/1550
git_repository(
    name = "xcbuildkit",
    commit = "b2f0e4dd5a572b7029db3cf791d0897977f96a80",
    remote = "https://github.com/jerrymarino/xcbuildkit.git",
)

load("@xcbuildkit//third_party:repositories.bzl", xcbuildkit_dependencies = "dependencies")

xcbuildkit_dependencies()

## Buildifier deps (Bazel file formatting)
http_archive(
    name = "io_bazel_rules_go",
    sha256 = "3743a20704efc319070957c45e24ae4626a05ba4b1d6a8961e87520296f1b676",
    url = "https://github.com/bazelbuild/rules_go/releases/download/0.18.4/rules_go-0.18.4.tar.gz",
)

load("@io_bazel_rules_go//go:deps.bzl", "go_register_toolchains", "go_rules_dependencies")

go_rules_dependencies()

go_register_toolchains()

# FIX-ME: Conflicts with how rules_ios loads buidlifier, bring this back or remote it after
# finding the root cause
# http_archive(
#     name = "com_github_bazelbuild_buildtools",
#     strip_prefix = "buildtools-0.25.0",
#     url = "https://github.com/bazelbuild/buildtools/archive/0.25.0.zip",
# )

# load("@com_github_bazelbuild_buildtools//buildifier:deps.bzl", "buildifier_dependencies")

# buildifier_dependencies()
