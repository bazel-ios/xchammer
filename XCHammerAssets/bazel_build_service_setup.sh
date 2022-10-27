#!/bin/bash

XCODE_CONTENTS=$(dirname $DEVELOPER_DIR)
BUILD_SERVICE=$XCODE_CONTENTS/SharedFrameworks/XCBuild.framework/PlugIns/XCBBuildService.bundle/Contents/MacOS/XCBBuildService
WORKSPACE_ROOT=$(echo "$BUILD_DIR" | sed -e 's/\/Build.*//g')

if [[ ! -d $WORKSPACE_ROOT ]]; then
    echo "[ERROR] Failed to setup build service. Workspace not found at $WORKSPACE_ROOT"
    exit 1
fi

INDEX_DATA_STORE=$WORKSPACE_ROOT/Index/DataStore
INDEX_DATA_STORE_BACKUP=$WORKSPACE_ROOT/Index/DataStore.default

undo () {
    echo "Undoing"
    
    if [[ -L $INDEX_DATA_STORE ]]; then
        rm $INDEX_DATA_STORE
    fi

    if [[ -d $INDEX_DATA_STORE_BACKUP ]]; then
        mv $INDEX_DATA_STORE_BACKUP $INDEX_DATA_STORE
    fi
    
    # if [[ -L $BUILD_SERVICE ]]; then
    #     echo "[ERROR] Build service disabled in Xcode. Make sure it's uninstalled on your system by running 'bazel run @xchammer//:xchammer uninstall_xcode_build_system'"
    #     exit 1
    # fi
}

# -rwxr-xr-x  1 thiago  staff   2.5K Dec 31  1979 App-XCHammer.xcodeproj/XCHammerAssets/bazel_build_service_setup.sh
# -rwxr-xr-x  1 thiago  staff   2.5K Oct 27 17:04 XCHammerAssets/bazel_build_service_setup.sh

# This is a YAML
cat >$BUILD_SERVICE_CONFIG_PATH <<EOL
BUILD_SERVICE_INDEXING_ENABLED=$BUILD_SERVICE_INDEXING_ENABLED
BUILD_SERVICE_INDEX_STORE_PATH=$BUILD_SERVICE_INDEX_STORE_PATH
BUILD_SERVICE_PROGRESS_BAR_ENABLED=$BUILD_SERVICE_PROGRESS_BAR_ENABLED
BUILD_SERVICE_BEP_PATH=$BUILD_SERVICE_BEP_PATH
EOL

echo "wrote"
cat $BUILD_SERVICE_CONFIG_PATH


if [ ! "$BUILD_SERVICE_INDEXING_ENABLED" = "YES" ]; then
    echo "Indexing disabled"
    undo
    exit 0
else
    echo "Indexing enabled"
fi

# Check build service installation
if [[ ! -f $BUILD_SERVICE ]]; then
    echo "Could not find build service at $BUILD_SERVICE. Check your Xcode installation."
    exit 1
fi

# if [[ ! -L $BUILD_SERVICE ]]; then
#     echo "[ERROR] Build service not installed. Please run 'bazel run @xchammer//:xchammer install_xcode_build_system' and try again."
#     exit 1
# fi

# Symlink DataStore
if [[ -z "$BUILD_SERVICE_INDEX_STORE_PATH" || ! -d $BUILD_SERVICE_INDEX_STORE_PATH ]]; then
    echo "[ERROR] Failed to setup indexing. Please make sure BUILD_SERVICE_INDEX_STORE_PATH is set in Xcode and the directory exists."
    exit 1
fi

if [[ -L $INDEX_DATA_STORE ]]; then
    if [[ "$(readlink $INDEX_DATA_STORE)" = "$BUILD_SERVICE_INDEX_STORE_PATH" ]]; then
        echo "Indexing data store symlink already exists from $INDEX_DATA_STORE to $BUILD_SERVICE_INDEX_STORE_PATH"
        exit 0
    else
        rm $INDEX_DATA_STORE
    fi
fi

if [[ -d $INDEX_DATA_STORE ]]; then
    mv $INDEX_DATA_STORE $INDEX_DATA_STORE_BACKUP
    echo "Created backup for existing indexing data store"
fi

ln -s $BUILD_SERVICE_INDEX_STORE_PATH $INDEX_DATA_STORE
echo "New symlink created for index data store"

touch $BUILD_SERVICE_CONFIG_PATH