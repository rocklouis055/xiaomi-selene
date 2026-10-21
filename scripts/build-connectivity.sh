#!/bin/bash
# Build the MediaTek connectivity modules (WMT, Wi-Fi, Bluetooth, GPS,
# FM radio, connfem)
# against the kernel that halium-generic-adaptation-build-tools just built,
# and put them where the Android vendor overlay picks them up:
#   overlay/system/usr/share/halium-overlay/vendor/lib/modules/
# They are out-of-tree vendor drivers and must match the exact kernel build
# (vermagic), so they are built here every time, never committed.
#
# Sources: Xiaomi's MTK_kernel_modules at fixed commits, plus
# patches/connectivity/*.patch:
#  - the Redmi 12 branch (fire-t-oss, same MT6768, made for this 4.19 kernel)
#    for WMT (common), GPS (gps_stp), the Wi-Fi char device (wlan/adaptor),
#    FM radio and connfem. This is the driver generation MIUI shipped; with
#    the older selene-r WMT/GPS drivers the GPS ran but never received a
#    satellite (C/N0 0 on every satellite, even outdoors);
#  - the Redmi 10 branch (selene-r-oss-update) for the Wi-Fi core (gen4m) and
#    Bluetooth, which the fire branch does not carry, built against fire's WMT.
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
FIRE_COMMIT=11459b44f7b0ed48c1e7c0cdb565775846e4aa90       # fire-t-oss

KERNEL_DIR="$TMPDOWN/$(basename "$deviceinfo_kernel_source")"
KERNEL_DIR="${KERNEL_DIR%.git}"
KERNEL_OBJ="$TMPDOWN/KERNEL_OBJ"
CLANG_PATH="$TMPDOWN/linux-x86/clang-$deviceinfo_kernel_clang_revision"
[ -d "$KERNEL_OBJ" ] || { echo "no kernel build in $KERNEL_OBJ (run ./build/build.sh -k first)" >&2; exit 1; }

# only the needed directories of the (large) repository, at a fixed commit
fetch() {   # dir commit subdir...
    local dir=$1 commit=$2; shift 2
    if [ ! -d "$dir/.git" ]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$MODULES_URL"
    fi
    git -C "$dir" sparse-checkout set "$@"
    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
    fi
    git -C "$dir" checkout -q -f "$commit"
}
SELENE="$TMPDOWN/mtk_kernel_modules_selene"
FIRE="$TMPDOWN/mtk_kernel_modules_fire"
fetch "$SELENE" "$SELENE_COMMIT" connectivity/wlan/core/gen4m connectivity/bt/mt66xx/legacy
fetch "$FIRE" "$FIRE_COMMIT" connectivity/common connectivity/gps connectivity/wlan/adaptor \
    connectivity/fmradio connectivity/connfem
git -C "$SELENE" reset -q --hard "$SELENE_COMMIT"
for p in "$HERE"/patches/connectivity/*.patch; do
    git -C "$SELENE" apply "$p"
done

# the module Makefiles find each other (WMT headers) through
# $(TOP)/vendor/mediatek/kernel_modules: point it at the fire tree
TOP="$TMPDOWN/connectivity_top_fire"
mkdir -p "$TOP/vendor/mediatek/kernel_modules"
ln -sfn "$FIRE/connectivity" "$TOP/vendor/mediatek/kernel_modules/connectivity"

C="$FIRE/connectivity"   # WMT, GPS, Wi-Fi adaptor, FM, connfem
S="$SELENE/connectivity" # Wi-Fi core, Bluetooth
build() {   # source-dir [make args...]
    local src=$1; shift
    PATH="$CLANG_PATH/bin:$PATH" make -C "$KERNEL_DIR" O="$KERNEL_OBJ" ARCH=arm64 \
        LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump STRIP=llvm-strip \
        CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu- \
        M="$src" KERNEL_OUT="$KERNEL_OBJ" TOP="$TOP" \
        MTK_PLATFORM=mt6768 MTK_PLATFORM_WMT=mt6768 TARGET_BOARD_PLATFORM=mt6768 \
        TARGET_BUILD_VARIANT=userdebug MTK_CONSYS_ADIE=MT6631 \
        AUTOCONF_H="$KERNEL_OBJ/include/generated/autoconf.h" \
        "$@" -j"$(nproc)" modules
}
WMT_SYMS="$C/common/Module.symvers"
build "$C/connfem"
build "$C/common"
build "$C/wlan/adaptor" CONNAC_VER=1_0 MODULE_NAME=wmt_chrdev_wifi KBUILD_EXTRA_SYMBOLS="$WMT_SYMS"
build "$S/wlan/core/gen4m" CONFIG_MTK_COMBO_WIFI_HIF=axi MODULE_NAME=wlan_drv_gen4m \
    MTK_COMBO_CHIP=CONNAC WLAN_CHIP_ID=6768 MTK_ANDROID_WMT=y MTK_ANDROID_EMI=y MTK_WLAN_SERVICE=yes \
    KBUILD_EXTRA_SYMBOLS="$WMT_SYMS $C/wlan/adaptor/Module.symvers"
build "$S/bt/mt66xx/legacy" KBUILD_EXTRA_SYMBOLS="$WMT_SYMS"
build "$C/gps" KBUILD_EXTRA_SYMBOLS="$WMT_SYMS"
build "$C/fmradio" CFG_FM_CHIP=mt6631 CFG_FM_CHIP_ID=6631 KBUILD_EXTRA_SYMBOLS="$WMT_SYMS"

OUT="$HERE/overlay/system/usr/share/halium-overlay/vendor/lib/modules"
mkdir -p "$OUT"
install -m644 "$C/connfem/connfem.ko" "$C/common/wmt_drv.ko" \
    "$C/wlan/adaptor/wmt_chrdev_wifi.ko" "$S/wlan/core/gen4m/wlan_drv_gen4m.ko" "$OUT/"
install -m644 "$S/bt/mt66xx/legacy/bt_drv.ko" "$OUT/bt_drv_connac1x.ko"
install -m644 "$C/gps/gps_drv.ko" "$OUT/"   # ro.vendor.gps.chrdev=gps_drv
install -m644 "$C/fmradio/fmradio_drv_.ko" "$OUT/fmradio_drv_mt6631.ko"   # ro.vendor.fm.platform
"$CLANG_PATH/bin/llvm-strip" --strip-debug "$OUT"/*.ko
echo "connectivity modules for $(cat "$KERNEL_OBJ/include/config/kernel.release") in $OUT"
