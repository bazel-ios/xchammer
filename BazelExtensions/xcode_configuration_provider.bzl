load(
    "@xchammer//:BazelExtensions/tulsi.bzl",
    "SwiftInfo",
)

XcodeProjectTargetInfo = provider(
    fields={
        "target_config_json_str": """
JSON string of target_config
Note: this must be a string as it's a rule input
"""
    }
)


def _declare_target_config_impl(ctx):
    return struct(
        providers=[XcodeProjectTargetInfo(target_config_json_str=ctx.attr.json)],
        objc=apple_common.new_objc_provider(),
    )


_declare_target_config = rule(
    implementation=_declare_target_config_impl,
    output_to_genfiles=True,
    attrs={"json": attr.string(mandatory=True)},
)


def declare_target_config(name, config, **kwargs):
    """ Declare a target configuration for an Xcode project
    This rule takes a `target_config` from XCHammerConfig
    and aggregates it onto the depgraph
    """
    _declare_target_config(name=name, json=config.to_json().replace("\\", ""), **kwargs)


XcodeConfigurationAspectInfo = provider(
    fields={
        "values": """This is the value of the JSON
"""
    }
)


def _target_config_aspect_impl(itarget, ctx):
    infos = []
    if ctx.rule.kind == "_declare_target_config":
        return []
    info_map = {}
    if XcodeProjectTargetInfo in itarget:
        target = itarget
        info_map[str(itarget.label)] = target[XcodeProjectTargetInfo].target_config_json_str

    if hasattr(ctx.rule.attr, "deps"):
        for target in ctx.rule.attr.deps:
            if XcodeConfigurationAspectInfo in target:
                for info in target[XcodeConfigurationAspectInfo].values:
                    info_map[info] = target[XcodeConfigurationAspectInfo].values[info]

            elif XcodeProjectTargetInfo in target:
                info_map[str(itarget.label)] = target[XcodeProjectTargetInfo].target_config_json_str

    return XcodeConfigurationAspectInfo(values=info_map)


target_config_aspect = aspect(
    implementation=_target_config_aspect_impl, attr_aspects=["*"]
)


XcodeBuildSourceInfo = provider(
    fields={
        "values": """The values of source files
""",

        "transitive": """The transitive values of source files
"""
    }
)

ObjcInfo = apple_common.Objc

def _collect_attr(target, ctx, attr_name, files):
    if hasattr(ctx.rule.attr, attr_name):
        attr_value = getattr(ctx.rule.attr, attr_name)
        if attr_value and DefaultInfo in attr_value:
            attr_value_files = attr_value[DefaultInfo].files
            files.append(attr_value_files)
        elif type(attr_value) == "list":
            for f in attr_value:
                if hasattr(f, "files"):
                     files.append(f.files)

def _extract_generated_sources(target, ctx):
    """ Collects all of the generated source files"""

    files = []
    if ctx.rule.kind == "entitlements_writer":
        files.append(target.files)

    _collect_attr(target, ctx, 'srcs', files)
    _collect_attr(target, ctx, 'entitlements', files)
    _collect_attr(target, ctx, 'infoplists', files)

    if SwiftInfo in target:
        include_swift_outputs = ctx.attr.include_swift_outputs == "true"
        module_info = target[SwiftInfo]
        if hasattr(module_info, "transitive_modulemaps"):
            files.append(module_info.transitive_modulemaps)
        if include_swift_outputs and hasattr(module_info, "transitive_swiftmodules"):
            files.append(module_info.transitive_swiftmodules)

    if CcInfo in target:
        files.append(depset(target[CcInfo].compilation_context.direct_public_headers))
    if ObjcInfo in target:
        objc = target[ObjcInfo]
        files.append(depset(objc.direct_headers))
    trans_files = depset(transitive = files)
    return [f for f in trans_files.to_list() if not f.is_source and not f.path.endswith("-Swift.h")]

get_srcroot = "\"$(cat ../../DO_NOT_BUILD_HERE)/\""
non_hermetic_execution_requirements = { "no-cache": "1", "no-remote": "1", "local": "1", "no-sandbox": "1" }

def _install_action(ctx, infos, itarget):
    inputs = []
    cmd = []
    cmd.append("SRCROOT=" + get_srcroot)
    for info in infos:
        parts = info.path.split("/bin/")
        dirname = info.path
        short_path = info.short_path.split("/")[:-1]
        if len(short_path) > 0 and short_path[0] == "..":
            target_dir = "external/" + "/".join(short_path[1:])
        else:
            target_dir = "/".join(short_path)
        if len(parts) > 0:
            inputs.append(info)
            last = parts[len(parts) - 1]
            cmd.append(
                "target_dir=\"$SRCROOT/xchammer-includes/x/x/" + target_dir + "\""
            )
            cmd.append("mkdir -p \"$target_dir\"")
            cmd.append("ditto " + info.path + " \"$target_dir\"")

    output = ctx.actions.declare_file(itarget.label.name + "_outputs.dummy")
    cmd.append("touch " + output.path)
    ctx.actions.run_shell(
        inputs=inputs,
        command="\n".join(cmd),
        use_default_shell_env=True,
        outputs=[output],
        execution_requirements = non_hermetic_execution_requirements
    )
    return [output]

SourceOutputFileMapInfo = provider(
    doc = "...",
    fields = {
        "mapping": "Dictionary where keys are source file paths and values are at the respective .o file under bazel-out",
    },
)

def _source_output_file_map(target, ctx):
    """
    Maps source code files to respective `.o` object file under bazel-out. Output group is used for indexing in xcbuildkit.
    """
    source_output_file_map = ctx.actions.declare_file("{}_source_output_file_map.json".format(target.label.name))

    mapping = {}
    objc_srcs = []
    objc_objects = []

    # List of source files to be mapped to output files
    if hasattr(ctx.rule.attr, "srcs"):
        objc_srcs = [
            f
            for source_file in ctx.rule.attr.srcs
            for f in source_file.files.to_list()
            # Handling objc only for now
            if f.path.endswith(".m")
            # TODO: handle swift
        ]

    # Get compilation outputs if present
    if OutputGroupInfo in target:
        if hasattr(target[OutputGroupInfo], "compilation_outputs"):
            objc_objects.extend(target[OutputGroupInfo].compilation_outputs.to_list())

    # Map source to output file
    if len(objc_srcs):
        if len(objc_srcs) != len(objc_objects):
            fail("[ERROR] Unexpected number of object files")
        for src in objc_srcs:
            basename_without_ext = src.basename.replace(".%s" % src.extension, "")
            obj = [o for o in objc_objects if "%s.o" % basename_without_ext == o.basename]
            if len(obj) != 1:
                fail("Failed to find single object file for source %s. Found: %s" % (src, obj))

            obj = obj[0]
            mapping["/{}".format(src.path)] = obj.path

    # Collect info from deps
    deps = getattr(ctx.rule.attr, "deps", [])
    transitive_jsons = []
    for dep in deps:
        # Collect mappings from deps
        if SourceOutputFileMapInfo in dep:
            for k, v in dep[SourceOutputFileMapInfo].mapping.items():
                mapping[k] = v
        # Collect generated JSON files from deps
        if OutputGroupInfo in dep:
            if hasattr(dep[OutputGroupInfo], "source_output_file_map"):
                transitive_jsons.extend(dep[OutputGroupInfo].source_output_file_map.to_list())

    # Writes JSON
    ctx.actions.write(source_output_file_map, json.encode(mapping))

    return [
        OutputGroupInfo(
            source_output_file_map = depset([source_output_file_map] + transitive_jsons),
        ),
        SourceOutputFileMapInfo(
            mapping = mapping
        ),
    ]
def _xcode_build_sources_aspect_impl(itarget, ctx):
    """ Install Xcode project dependencies into the source root.

    This is required as by default, Bazel only installs genfiles for those
    genfiles which are passed to the Bazel command line.
    """

    # Note: we need to collect the transitive files seperately from our own
    infos = []
    transitive = []
    infos.extend(_extract_generated_sources(itarget, ctx))
    if XcodeBuildSourceInfo in itarget:
       transitive.append(itarget[XcodeBuildSourceInfo].values)
       transitive.extend(itarget[XcodeBuildSourceInfo].transitive)

    if hasattr(ctx.rule.attr, "deps"):
        for target in ctx.rule.attr.deps:
            infos.extend(_extract_generated_sources(target, ctx))
            if XcodeBuildSourceInfo in target:
                transitive.append(target[XcodeBuildSourceInfo].values)
                transitive.extend(target[XcodeBuildSourceInfo].transitive)

    if hasattr(ctx.rule.attr, "transitive_deps"):
        for target in ctx.rule.attr.transitive_deps:
            infos.extend(_extract_generated_sources(target, ctx))
            if XcodeBuildSourceInfo in target:
                transitive.append(target[XcodeBuildSourceInfo].values)
                transitive.extend(target[XcodeBuildSourceInfo].transitive)

    compacted_transitive_files = depset(transitive=transitive).to_list()
    return [
        OutputGroupInfo(
            xcode_project_deps = _install_action(
                ctx,
                depset(direct=infos, transitive=transitive).to_list(),
                itarget,
            ),
        ),
        XcodeBuildSourceInfo(values = depset(infos), transitive=[depset(compacted_transitive_files)]),
    ] + _source_output_file_map(itarget, ctx)


# Note, that for "pure" Xcode builds we build swiftmodules with Xcode, so we
# don't need to pre-compile them with Bazel
pure_xcode_build_sources_aspect = aspect(
    implementation=_xcode_build_sources_aspect_impl, attr_aspects=["*"],
    attrs = { "include_swift_outputs": attr.string(values=["false","true"], default="false") }
)

xcode_build_sources_aspect = aspect(
    implementation=_xcode_build_sources_aspect_impl, attr_aspects=["*"],
    attrs = { "include_swift_outputs": attr.string(values=["false", "true"], default="true") }
)

