load(
    "@xchammer//:BazelExtensions/tulsi.bzl",
    "SwiftInfo",
)
load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "@bazel_tools//tools/cpp:toolchain_utils.bzl",
    "find_cpp_toolchain",
)
load(
    "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    "ACTION_NAMES",
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

def _objc_cmd_line(target, ctx, src, non_arc_srcs, output_file_path):
    """Returns flattened command line flags for ObjC sources
    """
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    copts = ctx.fragments.objc.copts + getattr(ctx.rule.attr, "copts", [])

    cc_compile_variables = cc_common.create_compile_variables(
        feature_configuration = cc_feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = copts,
        source_file = src.path,
        output_file = output_file_path,
    )

    base_args = cc_common.get_memory_inefficient_command_line(
        feature_configuration = cc_feature_configuration,
        action_name = ACTION_NAMES.objc_compile,
        variables = cc_compile_variables,
    )

    cmd_line_args = []

    # Arg pairs of the form '-flag value' to be skipped (breaks indexing if present)
    arg_pairs_to_skip = ["-c"]
    ignore_next = False

    # Contains patterns in flag values that once detected should be skipped
    #
    # e.g.:
    #
    # DEBUG_PREFIX_MAP_PWD: gives an error "error: no such file or directory: 'DEBUG_PREFIX_MAP_PWD=.'" during indexing
    #
    arg_patterns_to_skip = ["DEBUG_PREFIX_MAP_PWD"]

    # Collects all relevant compiler flags
    for arg in base_args:
        if arg in arg_pairs_to_skip:
            ignore_next = True
        elif ignore_next:
            continue
        else:
            # Reset 'arg pairs to skip' flag
            ignore_next = False
            # Only proceed if it's a valid pattern
            if len([p for p in arg_patterns_to_skip if arg.count(p) > 0]) == 0:
                # Handles single quotes to prevent the following:
                #
                # `error: Macro name must be an identifier`
                #
                a = arg
                if a.startswith("-D"):
                    a = a.replace("'", "")
                cmd_line_args.append(a)

    # Handles ARC flag
    cmd_line_args.append("-fobjc-arc" if not src in non_arc_srcs else "-fno-objc-arc")

    return cmd_line_args

def _swift_cmd_line(target, src):
    argv = []
    # In theory a single SwiftCompile action should represent
    # the compilation of `src`, so fails if more than one is found
    for a in target.actions:
        if a.argv and a.mnemonic == "SwiftCompile" and src.path in a.argv:
            argv.append(a.argv)

    if len(argv) != 1:
        fail("[ERROR] Source file {} referenced in multiple SwiftCompile actions.".format(src.path))
    argv = argv[0]

    # Collect only the args that can be used in Xcode and passed to the
    # indexing invocations
    swiftc_args = []
    for arg in argv:
        if arg.endswith("worker") or arg == "swiftc" or arg.count("-Xwrapped-swift"):
            continue
        else:
            swiftc_args.append(arg)
    return swiftc_args

def _is_objc(src):
    return src.extension in ["m", "mm", "c", "cc", "cpp"]

def _is_swift(src):
    return src.extension == "swift"

def _source_output_file_map(target, ctx):
    """
    Maps source code files to respective `.o` object file under bazel-out. Output group is used for indexing in xcbuildkit.
    """
    source_output_file_map = ctx.actions.declare_file("{}_source_output_file_map.json".format(target.label.name))
    mapping = {}
    srcs = []
    objs = []

    # List of source files to be mapped to output files
    if hasattr(ctx.rule.attr, "srcs"):
        srcs.extend([
            f
            for source_file in ctx.rule.attr.srcs
            for f in source_file.files.to_list()
            if _is_objc(f) or _is_swift(f)
        ])
    if hasattr(ctx.rule.attr, "non_arc_srcs"):
        srcs.extend([
            f
            for source_file in ctx.rule.attr.non_arc_srcs
            for f in source_file.files.to_list()
            if _is_objc(f)
        ])

    # Get compilation outputs if present
    if OutputGroupInfo in target:
        # Objc, this is empty for Swift Sources
        if hasattr(target[OutputGroupInfo], "compilation_outputs"):
            objs.extend([f.path for f in target[OutputGroupInfo].compilation_outputs.to_list()])
        # Collect Swift outputs directly, couldn't find this in a provider
        for a in target.actions:
            if a.mnemonic == "SwiftCompile":
                objs.extend([f.path for f in a.outputs.to_list() if f.extension == "o"])

    non_arc_srcs = []
    if hasattr(ctx.rule.attr, "non_arc_srcs"):
        non_arc_srcs.extend([f for src in ctx.rule.attr.non_arc_srcs for f in src.files.to_list()])

    # Map source to output file
    if len(srcs):
        if len(srcs) != len(objs):
            fail("[ERROR] Unexpected number of object files")
        for src in srcs:
            basename_without_ext = src.basename.replace(".%s" % src.extension, "")
            obj_extension = "swift.o" if _is_swift(src) else "o"
            obj = [o for o in objs if "%s.%s" % (basename_without_ext, obj_extension) == paths.basename(o)]
            if len(obj) != 1:
                fail("Failed to find single object file for source %s. Found: %s" % (src, obj))
            obj_path = obj[0]

            cmd_line = []
            if _is_objc(src):
                cmd_line = _objc_cmd_line(target, ctx, src, non_arc_srcs, obj_path)
            elif _is_swift(src):
                cmd_line = _swift_cmd_line(target, src)
            # This check is to `expand_location` only if known patterns are present on the command line args.
            # Without this check we hit the err below from `rules_swift`:
            #
            # ERROR: ... on cc_library rule @build_bazel_rules_swift//tools/worker:swift_runner: label '@build_bazel_rules_swift_index_import//:index_import' in $(location) expression is not a declared prerequisite of this rule
            #
            patterns_to_expand = ["$(location", "$(execpath"]
            if len([(x,p) for x in cmd_line for p in patterns_to_expand if x.count(p) > 0]) > 0:
                cmd_line = ctx.expand_location(" ".join(cmd_line)).split(" ")
            mapping["/{}".format(src.path)] = {
                "output_file": obj_path,
                "command_line_args": cmd_line,
            }

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
                transitive_jsons.append(dep[OutputGroupInfo].source_output_file_map)

    # Writes JSON
    ctx.actions.write(source_output_file_map, json.encode(mapping))

    return [
        OutputGroupInfo(
            source_output_file_map = depset([source_output_file_map], transitive = transitive_jsons),
        ),
        SourceOutputFileMapInfo(
            mapping = mapping,
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
    attrs = {
        "include_swift_outputs": attr.string(values=["false","true"], default="false"),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    }
)

xcode_build_sources_aspect = aspect(
    implementation=_xcode_build_sources_aspect_impl, attr_aspects=["*"],
    attrs = {
        "include_swift_outputs": attr.string(values=["false", "true"], default="true"),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    fragments = ["objc", "cpp"],
)

