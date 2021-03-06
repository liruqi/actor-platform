#!/bin/bash
set -e

# Configuration
J2OBJC_VERSION=0.9.8.1
BUILD_DIRECTORY="$1/build-tools"
J2OBJC_DIR="${BUILD_DIRECTORY}/dist/"

source "$BUILD_DIRECTORY/common.sh"

if [ ! -d "${J2OBJC_DIR}/j2objc-${J2OBJC_VERSION}" ]; then
	echo_w "Downloading j2objc..."
	curl -o "${BUILD_DIRECTORY}/j2objc-${J2OBJC_VERSION}.zip" -L https://dl.bintray.com/actor/j2objc/j2objc-${J2OBJC_VERSION}.zip

	echo "Extracting j2objc..."
	mkdir -p "${J2OBJC_DIR}"
	unzip -q "${BUILD_DIRECTORY}/j2objc-${J2OBJC_VERSION}.zip" -d "${J2OBJC_DIR}"
	rm "${BUILD_DIRECTORY}/j2objc-${J2OBJC_VERSION}.zip"
else
	echo_w "Cocoa Dependency already installed. Skipping..."
fi
