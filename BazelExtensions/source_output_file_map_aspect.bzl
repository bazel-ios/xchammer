"""
Aspect to map source to output files (i.e. .o files generated during compilation).

The mappings are generated as JSON files per target.
"""

SourceOutputFileMapInfo = provider(
    doc = "...",
    fields = {
        "mapping": "Dictionary where keys are source file paths and values are at the respective .o file under bazel-out",
    },
)

def _source_output_file_map_aspect_impl(target, ctx):
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

source_output_file_map_aspect = aspect(
    implementation = _source_output_file_map_aspect_impl,
    attr_aspects = ["deps"],
)
