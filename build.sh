#!/bin/bash
# Build wrapper (CI sets ADAPTATION_TOOLS_USE_BUILD_WRAPPER=1 to use it).
#
# The standard tools build the kernel, the boot image and the device tarball;
# in between, the MediaTek Wi-Fi/Bluetooth modules are built against that
# kernel (scripts/build-connectivity.sh), so the tarball carries matching ones.
set -xe

BRANCH=${ADAPTATION_TOOLS_BRANCH:-main}
[ -d build ] || git clone https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools -b "$BRANCH" build

# Android's init skips group/world-writable rc and prop files: make sure the
# recovery and vendor overlays are not, whatever the umask of the checkout was.
chmod -R go-w ramdisk-recovery-overlay overlay/system/usr/share/halium-overlay/vendor/etc overlay/system/usr/share/halium-overlay/system/etc

./build/build.sh -k "$@"                  # kernel and boot.img
./scripts/build-connectivity.sh workdir  # out-of-tree vendor modules
./build/build.sh "$@"                     # again, incremental: + device tarball
