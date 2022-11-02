#!/bin/bash

# Values set at project generation time, for reference check `BazelExtensions/xcodeproject.bzl` => `_install_xcode_project` rule
BUILD_SERVICE_BAZEL_EXEC_ROOT=__BAZEL_EXEC_ROOT__

# Check `BazelExtensions/source_output_file_map_aspect.bzl`, xcbuildkit needs to know what pattern to look for to pre-load indexing information
BUILD_SERVICE_SOURCE_OUTPUT_FILE_MAP_SUFFIX=source_output_file_map.json

# Load DataStore related paths, used below to setup the DataStore or undo the setup if the build service is not installed
WORKSPACE_ROOT=$(echo "$BUILD_DIR" | sed -e 's/\/Build.*//g')

if [[ ! -d $WORKSPACE_ROOT ]]; then
    echo "[ERROR] Failed to setup build service. Workspace not found at $WORKSPACE_ROOT"
    exit 1
fi

INDEX_DATA_STORE=$WORKSPACE_ROOT/Index/DataStore
INDEX_DATA_STORE_BACKUP=$WORKSPACE_ROOT/Index/DataStore.default

undoDataStoreSetupIfNecessary () {
    # Remove symlink
    if [[ -L $INDEX_DATA_STORE ]]; then
        rm $INDEX_DATA_STORE

        # If there's a backup put it back
        if [[ -d $INDEX_DATA_STORE_BACKUP ]]; then
            mv $INDEX_DATA_STORE_BACKUP $INDEX_DATA_STORE
        fi
    fi
}

# Build service binary checks
XCODE_CONTENTS=$(dirname $DEVELOPER_DIR)
BUILD_SERVICE=$XCODE_CONTENTS/SharedFrameworks/XCBuild.framework/PlugIns/XCBBuildService.bundle/Contents/MacOS/XCBBuildService

# if the build service does not exist at this location we messed something up
if [[ ! -f $BUILD_SERVICE ]]; then
    echo "Could not find build service at $BUILD_SERVICE. Check your Xcode installation."
    undoDataStoreSetupIfNecessary
    exit 1
fi

# If the build service is not a symlink, xcbuildkit is not installed so there's nothing to do
if [[ ! -L $BUILD_SERVICE ]]; then
    echo "Build service not installed. Nothing to do."
    undoDataStoreSetupIfNecessary
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

# Setup DataStore

# If for some reason there's an existing symlink and it does not match 'BUILD_SERVICE_INDEX_STORE_PATH' remove it and reconfigure below,
# otherwise exits since there's nothing to do and build service is fully configured
if [[ -L $INDEX_DATA_STORE ]]; then
    if [[ "$(readlink $INDEX_DATA_STORE)" = "$BUILD_SERVICE_INDEX_STORE_PATH" ]]; then
        echo "[INFO] Build service already configured. DataStore symlinked from $INDEX_DATA_STORE to $BUILD_SERVICE_INDEX_STORE_PATH."
        exit 0
    else
        rm $INDEX_DATA_STORE
    fi
fi

# If there's an existing DataStore create a backup before symlink-ing
if [[ -d $INDEX_DATA_STORE ]]; then
    if [[ -d $INDEX_DATA_STORE_BACKUP ]]; then
        rm -fr $INDEX_DATA_STORE_BACKUP
    fi
    mv $INDEX_DATA_STORE $INDEX_DATA_STORE_BACKUP
fi

ln -s $BUILD_SERVICE_INDEX_STORE_PATH $INDEX_DATA_STORE

echo "[INFO] Build service setup complete. DataStore symlinked from $INDEX_DATA_STORE to $BUILD_SERVICE_INDEX_STORE_PATH."