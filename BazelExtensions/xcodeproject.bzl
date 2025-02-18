# Load the sources aspect from Tulsi
load(
    "@xchammer//:BazelExtensions/tulsi.bzl",
    "tulsi_sources_aspect",
    "TulsiSourcesAspectInfo",
)

load(
    "@xchammer//:BazelExtensions/xchammerconfig.bzl",
    "xchammer_config",
    "gen_xchammer_config",
    "project_config",
    "bazel_build_service_config"
)

load(
    "@xchammer//:BazelExtensions/xcode_configuration_provider.bzl",
    "XcodeProjectTargetInfo",
    "XcodeConfigurationAspectInfo",
    "target_config_aspect",
    "XcodeBuildSourceInfo",
    "SourceOutputFileMapInfo",
)

non_hermetic_execution_requirements = { "no-cache": "1", "no-remote": "1", "local": "1", "no-sandbox": "1" }

# Why are we rendering JSON here?
# - the XCHammerConfig is modeled as structs which are passed to rules as strings
# - calling to_json() recursivly renders a dict as a string
# To fix this, we could _try_ to refactor xchammerconfig.bzl and express the
# entire DSL as providers.
def _dict_to_json(value):
    entries = []
    for key in value:
        entries.append("\"" + key + "\":" + value[key] + "")
    return "{ " + ",".join([t for t in entries]) + " }"

def _array_to_json(value):
    return "[ " + ",".join(["\"" + t + "\""  for t in value]) + " ]"

def _xcode_project_impl(ctx):
    # Collect Target configuration JSON from deps
    # Then, merge them to a list
    aggregate_target_config = {}

    for dep in ctx.attr.targets:
        if XcodeConfigurationAspectInfo in dep:
            for info in dep[XcodeConfigurationAspectInfo].values:
                # For some targets, this is set on an internal target. We need
                # to set this on the actual label. The convention is to name the
                # target as ".__internal__.apple_binary" or
                # ".__internal__.SOME"
                if ".__internal__" in info:
                    key = info.split(".__internal__")[0]
                else:
                    key = info
                aggregate_target_config[key] = dep[XcodeConfigurationAspectInfo].values[info]

    xchammerconfig_json = ctx.actions.declare_file(ctx.attr.name + "_xchammer_config.json")
    target_config_attr = ctx.attr.target_config if ctx.attr.target_config else None

    # Consider adding the ability to support this
    if len(aggregate_target_config) > 0 and ctx.attr.target_config:
        print("warning: cannot use aggregate target config and target config directly")
        target_config_json =  _dict_to_json(aggregate_target_config)
    elif len(aggregate_target_config) > 0:
        target_config_json =  _dict_to_json(aggregate_target_config)
    else:
        target_config_json = ctx.attr.target_config
    projects_json = (
        ctx.attr.project_config
        if ctx.attr.project_config
        else project_config(paths=["**"]).to_json()
    )
    xchammerconfig = _dict_to_json({
        "targetConfig" : target_config_json,
        "projects" : _dict_to_json({ctx.attr.project_name: projects_json}),
        "targets": _array_to_json([str(t.label) for t in ctx.attr.targets])
    })
    ctx.actions.write(content=xchammerconfig, output=xchammerconfig_json)

    artifacts = []

    for dep in ctx.attr.targets:
        for a in dep[OutputGroupInfo].tulsi_info.to_list():
            artifacts.append(a)

    xchammer_info_json = ctx.actions.declare_file(ctx.attr.name + "_xchammer_info.json")

    xchammer_files = ctx.attr.xchammer.files.to_list()
    xchammer = xchammer_files[0]
    if xchammer.extension == "zip":
        if xchammer.basename != "xchammer.zip":
            fail("Unexpected app name: " + xchammer.path)
        # Assume that if we're dealing with a zip, then it's adjacent to the
        # archive root.
        ar_root_bin = "/xchammer_archive-root/xchammer.app/Contents/MacOS/xchammer"
        xchammer_bin = xchammer.dirname + ar_root_bin
    else:
        # Perhaps we always want to have this:
        xchammer_bin = xchammer.path

    # Drop off Contents/MacOS/Resources
    xchammer_app = "/".join(xchammer_bin.split("/")[:-3])
    xchammer_info = struct(
        tulsiinfos=[a.path for a in artifacts],
        # This is used by bazel_build_settings.py and replaced by
        # install_xcode_project.
        execRoot="__BAZEL_EXEC_ROOT__",
        bazelTargets=[str(ctx.label)[:-5]],
        xchammerPath=xchammer_app
        if xchammer_app[0] == "/"
        else "$SRCROOT/" + xchammer_app,
    )
    ctx.actions.write(content=xchammer_info.to_json(), output=xchammer_info_json)

    xchammer_command = [
        "set -e;",
        xchammer_bin
    ]
    project_name = ctx.attr.project_name + ".xcodeproj"
    xchammer_command.extend(
        [
            "generate_v2",
            xchammerconfig_json.path,
            # Write the xcode project into the execroot. We need to copy to the
            # bin-dir after generation for validation. This is not 100% safe
            # and needs patches in XcodeGen validation ( or remove XcodeGen )
            # In order to keep this hermetic, the project is installed out of band
            # in another non-hermetic rule which depends on this
            "--workspace_root",
            "$PWD",
            "--bazel",
            ctx.attr.bazel
            if ctx.attr.bazel[0] == "/"
            else "\\$SRCROOT/" + ctx.attr.bazel,
            "--xcode_project_rule_info",
            xchammer_info_json.path,
            "; ditto " + project_name + " " + ctx.outputs.out.path,
        ]
    )

    ctx.actions.run_shell(
        mnemonic="XcodeProject",
        inputs=artifacts + [xchammerconfig_json, xchammer_info_json] + xchammer_files,
        command=" ".join(xchammer_command),
        outputs=[ctx.outputs.out],
        execution_requirements = { "local": "1" }
    )

_xcode_project = rule(
    implementation=_xcode_project_impl,
    attrs={
        "targets": attr.label_list(
            aspects=[tulsi_sources_aspect, target_config_aspect],
        ),
        "project_name": attr.string(),
        "bazel": attr.string(default="bazel"),
        "target_config": attr.string(default="{}"),
        "project_config": attr.string(),
        "xchammer": attr.label(mandatory=False,default="@xchammer//:xchammer"),
    },
    outputs={"out": "%{project_name}.xcodeproj"},
)

# Get the workspace by reading DO_NOT_BUILD_HERE
# https://github.com/bazelbuild/bazel/blob/master/src/main/java/com/google/devtools/build/lib/runtime/BlazeWorkspace.java#L298
get_srcroot = "\"$(cat ../../DO_NOT_BUILD_HERE)/\""

def _xcbuildkit_config_value(bazel_build_service_config_json, key, default_value, is_bool = False):
    if not key in bazel_build_service_config_json:
        return default_value
    if not is_bool:
        return bazel_build_service_config_json[key] if bazel_build_service_config_json[key] else default_value

    return "YES" if bazel_build_service_config_json[key] else "NO"

def _install_xcode_project_impl(ctx):
    xcodeproj = ctx.attr.xcodeproj.files.to_list()[0]
    output_proj = "$SRCROOT/" + xcodeproj.basename

    command = [
        "SRCROOT=" + get_srcroot,
        "ditto " + xcodeproj.path + " " + output_proj,
        "sed -i '' \"s,__BAZEL_EXEC_ROOT__,$PWD,g\" " + output_proj + "/XCHammerAssets/bazel_build_settings.py",
        "sed -i '' \"s,__BAZEL_OUTPUT_BASE__,$(dirname $(dirname $PWD)),g\" " + output_proj + "/XCHammerAssets/bazel_build_settings.py",
        # This is kind of a hack for reference bazel relative to the source
        # directory, as bazel_build_settings.py doesn't sub Xcode build
        # settings.
        "sed -i '' \"s,\\$SRCROOT,$SRCROOT,g\" "
        + output_proj
        + "/XCHammerAssets/bazel_build_settings.py",
        # Ensure the `external` symlink points to output_base/external
        "test $SRCROOT/external -ef $PWD/../../external || " +
        "(rm -f $SRCROOT/external && ln -sf $PWD/../../external $SRCROOT/external)",
        'echo "' + output_proj + '" > ' + ctx.outputs.out.path,
    ]

    if ctx.attr.bazel_build_service_config:
        # Same default values as xcbuildkit
        xcbuildkit_config_path = output_proj + "/xcbuildkit.config"
        xcbuildkit_default_indexing_data_dir = "/tmp/xcbuildkit-data/{}/indexing".format(ctx.attr.name)
        xcbuildkit_default_bep_path = "/tmp/{}.bep".format(ctx.attr.name)

        # Decode user provided config
        bazel_build_service_config_json = json.decode(ctx.attr.bazel_build_service_config)

        # Resolving each setting
        indexing_enabled = _xcbuildkit_config_value(bazel_build_service_config_json, "indexingEnabled", "NO", True)
        index_store_path = _xcbuildkit_config_value(bazel_build_service_config_json, "indexStorePath", "")
        indexing_data_dir = _xcbuildkit_config_value(bazel_build_service_config_json, "indexingDataDir", xcbuildkit_default_indexing_data_dir)
        progress_bar_enabled = _xcbuildkit_config_value(bazel_build_service_config_json, "progressBarEnabled", "NO", True)
        bep_path = _xcbuildkit_config_value(bazel_build_service_config_json, "bepPath", xcbuildkit_default_bep_path)
        # Hard coded since this is very XCHammer specific and there's no need to make it configurable.
        # See `BazelExtensions/xcode_configuration_provider.bzl` => `SourceOutputFileMapInfo` usage.
        output_file_map_suffix = "source_output_file_map.json"

        if indexing_enabled and (not index_store_path or len(index_store_path) == 0):
            fail("[ERROR] The 'index_store_path' attribute is mandatory. The $SRCROOT env variable is available to specify a path to the index store populated by Bazel in your repo, e.g., '$SRCROOT/path/to/my-index-store'.")

        # Create xcbuildkit config file and make sure `indexingDataDir` exists
        command += [
            "touch " + xcbuildkit_config_path,
            "mkdir -p " + indexing_data_dir,
            """
cat >{xcbuildkit_config_path} <<EOL
BUILD_SERVICE_INDEXING_ENABLED={build_service_indexing_enabled}
BUILD_SERVICE_INDEX_STORE_PATH={build_service_index_store_path}
BUILD_SERVICE_INDEXING_DATA_DIR={build_service_indexing_data_dir}
BUILD_SERVICE_PROGRESS_BAR_ENABLED={build_service_progress_bar_enabled}
BUILD_SERVICE_BEP_PATH={build_service_bep_path}
BUILD_SERVICE_BAZEL_EXEC_ROOT=$PWD
BUILD_SERVICE_SOURCE_OUTPUT_FILE_MAP_SUFFIX={build_service_output_file_map_suffix}
EOL
            """.format(
                xcbuildkit_config_path = xcbuildkit_config_path,
                build_service_indexing_enabled = indexing_enabled,
                build_service_index_store_path = index_store_path,
                build_service_indexing_data_dir = indexing_data_dir,
                build_service_progress_bar_enabled = progress_bar_enabled,
                build_service_bep_path = bep_path,
                build_service_output_file_map_suffix = output_file_map_suffix,
            ),
        ]

    ctx.actions.run_shell(
        inputs=ctx.attr.xcodeproj.files,
        command=";".join(command),
        use_default_shell_env=True,
        outputs=[ctx.outputs.out],
        execution_requirements = non_hermetic_execution_requirements
    )


_install_xcode_project = rule(
    implementation=_install_xcode_project_impl,
    attrs={
        "xcodeproj": attr.label(mandatory=True),
        "bazel_build_service_config": attr.string(),
    },
    outputs={"out": "%{name}.dummy"},
)

def _bazel_build_service_config_json(proj_args):
    config_json = None
    if "bazel_build_service_config" in proj_args:
        bazel_build_service_config = proj_args.pop("bazel_build_service_config", None)
        if bazel_build_service_config:
            config_json = bazel_build_service_config.to_json()
    return config_json

def xcode_project(**kwargs):
    """ Generate an Xcode project

    name: attr.string name of the target

    targets:  attr.label_list

    bazel: attr.string path to Bazel used during Xcode builds

    xchammer: attr.string path to xchammer

    project_name: (optional)

    target_config: (optional) struct(target_config)
    
    project_config: (optional) struct(target_config)
    """
    proj_args = kwargs
    bazel_build_service_config = _bazel_build_service_config_json(proj_args)
    rule_name = kwargs["name"]

    if not kwargs.get("project_name"):
        proj_args["project_name"] = kwargs["name"]

    # Build an XCHammer config Based on inputs
    if "target_config" in  proj_args:
        str_dict = {}
        for k in proj_args["target_config"]:
            str_dict[k] = proj_args["target_config"][k].to_json()

        proj_args["target_config"] = _dict_to_json(str_dict)
    else:
        proj_args["target_config"] =  "{}"

    proj_args["name"] = rule_name + "_impl"
    proj_args["project_config"] = proj_args["project_config"].to_json() if "project_config" in proj_args else None

    _xcode_project(**proj_args)

    # Note: _xcode_project does the hermetic, reproducible bits
    # and then, we install this xcode project into the root directory.
    _install_xcode_project(
        name=rule_name,
        xcodeproj=kwargs["name"],
        testonly=proj_args.get("testonly", False),
        bazel_build_service_config = bazel_build_service_config,
    )
