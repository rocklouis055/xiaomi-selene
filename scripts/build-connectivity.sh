#!/bin/bash
# Build the MediaTek connectivity modules (WMT, Wi-Fi, Bluetooth, connfem)
# against the kernel that halium-generic-adaptation-build-tools just built,
# and put them where the Android vendor overlay picks them up:
#   overlay/system/usr/share/halium-overlay/vendor/lib/modules/
# They are out-of-tree vendor drivers and must match the exact kernel build
# (vermagic), so they are built here every time, never committed.
#
# Sources: Xiaomi's MTK_kernel_modules, the Redmi 10 branch (WMT, Wi-Fi, BT)
# and the Redmi 12 branch (connfem, which the selene branch lacks), at fixed
# commits, plus patches/connectivity/*.patch.
#
# Usage (from the repository root, after `./build/build.sh -k`):
#   scripts/build-connectivity.sh [workdir]
set -e

HERE=$(pwd)
BUILD_DIR=$(realpath "${1:-workdir}")
TMPDOWN="$BUILD_DIR/downloads"
source "$HERE/deviceinfo"

MODULES_URL=https://github.com/MiCode/MTK_kernel_modules
SELENE_COMMIT=57c17e45975cd8af98ca4cf124a5eb76b4ddb1da     # selene-r-oss-update
FIRE_COMMIT=11459b44f7b0ed48c1e7c0cdb565775846e4aa90       # fire-t-oss (connfem)

KERNEL_DIR="$TMPDOWN/$(basename "$deviceinfo_kernel_source")"
KERNEL_DIR="${KERNEL_DIR%.git}"
KERNEL_OBJ="$TMPDOWN/KERNEL_OBJ"
CLANG_PATH="$TMPDOWN/linux-x86/clang-$deviceinfo_kernel_clang_revision"
[ -d "$KERNEL_OBJ" ] || { echo "no kernel build in $KERNEL_OBJ (run ./build/build.sh -k first)" >&2; exit 1; }

# only the connectivity directory of the (large) repository, at a fixed commit
fetch() {   # dir commit subdir
    local dir=$1 commit=$2 sub=$3
    if [ ! -d "$dir/.git" ]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$MODULES_URL"
        git -C "$dir" sparse-checkout set "$sub"
    fi
    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
        git -C "$dir" checkout -q -f "$commit"
    fi
}
SELENE="$TMPDOWN/mtk_kernel_modules_selene"
FIRE="$TMPDOWN/mtk_kernel_modules_fire"
fetch "$SELENE" "$SELENE_COMMIT" connectivity
fetch "$FIRE" "$FIRE_COMMIT" connectivity/connfem
git -C "$SELENE" reset -q --hard "$SELENE_COMMIT"
for p in "$HERE"/patches/connectivity/*.patch; do
    git -C "$SELENE" apply "$p"
done

# the module Makefiles find each other through $(TOP)/vendor/mediatek/kernel_modules
TOP="$TMPDOWN/connectivity_top"
mkdir -p "$TOP/vendor/mediatek/kernel_modules"
ln -sfn "$SELENE/connectivity" "$TOP/vendor/mediatek/kernel_modules/connectivity"

C="$SELENE/connectivity"
build() {   # source-dir [make args...]
    local src=$1; shift
    PATH="$CLANG_PATH/bin:$PATH" make -C "$KERNEL_DIR" O="$KERNEL_OBJ" ARCH=arm64 \
        LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump STRIP=llvm-strip \
        CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
        M="$src" KERNEL_OUT="$KERNEL_OBJ" TOP="$TOP" \
        MTK_PLATFORM=mt6768 MTK_PLATFORM_WMT=mt6768 TARGET_BOARD_PLATFORM=mt6768 \
        TARGET_BUILD_VARIANT=userdebug MTK_CONSYS_ADIE=MT6631 \
        "$@" -j"$(nproc)" modules
}
build "$FIRE/connectivity/connfem"
build "$C/common"
build "$C/wlan/adaptor" CONNAC_VER=1_0 MODULE_NAME=wmt_chrdev_wifi \
    KBUILD_EXTRA_SYMBOLS="$C/common/Module.symvers"
build "$C/wlan/core/gen4m" CONFIG_MTK_COMBO_WIFI_HIF=axi MODULE_NAME=wlan_drv_gen4m \
    MTK_COMBO_CHIP=CONNAC WLAN_CHIP_ID=6768 MTK_ANDROID_WMT=y MTK_ANDROID_EMI=y MTK_WLAN_SERVICE=yes \
    KBUILD_EXTRA_SYMBOLS="$C/common/Module.symvers $C/wlan/adaptor/Module.symvers"
build "$C/bt/mt66xx/legacy" KBUILD_EXTRA_SYMBOLS="$C/common/Module.symvers"

OUT="$HERE/overlay/system/usr/share/halium-overlay/vendor/lib/modules"
mkdir -p "$OUT"
install -m644 "$FIRE/connectivity/connfem/connfem.ko" "$C/common/wmt_drv.ko" \
    "$C/wlan/adaptor/wmt_chrdev_wifi.ko" "$C/wlan/core/gen4m/wlan_drv_gen4m.ko" "$OUT/"
install -m644 "$C/bt/mt66xx/legacy/bt_drv.ko" "$OUT/bt_drv_connac1x.ko"
"$CLANG_PATH/bin/llvm-strip" --strip-debug "$OUT"/*.ko
echo "connectivity modules for $(cat "$KERNEL_OBJ/include/config/kernel.release") in $OUT"
