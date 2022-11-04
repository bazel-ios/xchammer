#!/bin/bash

# Values set at project generation time, for reference check `BazelExtensions/xcodeproject.bzl` => `_install_xcode_project` rule
BUILD_SERVICE_BAZEL_EXEC_ROOT=__BAZEL_EXEC_ROOT__

# Check `BazelExtensions/source_output_file_map_aspect.bzl`, xcbuildkit needs to know what pattern to look for to pre-load indexing information
BUILD_SERVICE_SOURCE_OUTPUT_FILE_MAP_SUFFIX=source_output_file_map.json

# Build service binary checks
XCODE_CONTENTS=$(dirname $DEVELOPER_DIR)
BUILD_SERVICE=$XCODE_CONTENTS/SharedFrameworks/XCBuild.framework/PlugIns/XCBBuildService.bundle/Contents/MacOS/XCBBuildService

# if the build service does not exist at this location we messed something up
if [[ ! -f $BUILD_SERVICE ]]; then
    echo "Could not find build service at $BUILD_SERVICE. Check your Xcode installation."
    exit 1
fi

# If the build service is not a symlink, xcbuildkit is not installed so there's nothing to do
if [[ ! -L $BUILD_SERVICE ]]; then
    echo "Build service not installed. Nothing to do."
    exit 0
fi

# Ensure this folder exists, used by xcbuildkit to hold cached indexing data
mkdir -p $BUILD_SERVICE_INDEXING_DATA_DIR

# xcbuildkit expects a config file called `xcbuildkit.config` under path/to/foo.xcodeproj
BUILD_SERVICE_CONFIG_PATH=$PROJECT_FILE_PATH/xcbuildkit.config

cat >$BUILD_SERVICE_CONFIG_PATH <<EOL
BUILD_SERVICE_INDEXING_ENABLED=$BUILD_SERVICE_INDEXING_ENABLED
BUILD_SERVICE_INDEX_STORE_PATH=$BUILD_SERVICE_INDEX_STORE_PATH
BUILD_SERVICE_INDEXING_DATA_DIR=$BUILD_SERVICE_INDEXING_DATA_DIR
BUILD_SERVICE_PROGRESS_BAR_ENABLED=$BUILD_SERVICE_PROGRESS_BAR_ENABLED
BUILD_SERVICE_BEP_PATH=$BUILD_SERVICE_BEP_PATH
BUILD_SERVICE_BAZEL_EXEC_ROOT=$BUILD_SERVICE_BAZEL_EXEC_ROOT
BUILD_SERVICE_SOURCE_OUTPUT_FILE_MAP_SUFFIX=$BUILD_SERVICE_SOURCE_OUTPUT_FILE_MAP_SUFFIX
EOL

echo "[INFO] Wrote xcbuildkit config file at $BUILD_SERVICE_CONFIG_PATH"