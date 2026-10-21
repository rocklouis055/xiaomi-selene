# Ubuntu Touch for the Xiaomi Redmi 10 (selene)

Community port of [Ubuntu Touch](https://ubuntu-touch.io) 24.04 to the Redmi 10 /
Redmi 10 Prime (`selene`, MediaTek Helio G85/G88, MT6768), on Halium 12 with the
stock MIUI 14 (Android 12) vendor.

| | |
|---|---|
| Codename | `selene` (models 21061119AG, 21061119BI, 21061119DG) |
| Halium | 12 |
| Ubuntu Touch | 24.04-2.x |
| Kernel | 4.19, Xiaomi's MT6768 tree (MiCode `fire-t-oss`) with the selene board support ported to it: [kernel-xiaomi-selene](https://github.com/rocklouis055/kernel-xiaomi-selene), branch `halium-12` |
| Vendor | Stock MIUI 14 Android 12 vendor (V14.0.x) |

## Status

Working (tested on 21061119BI):

- Display (1080x2400, 60/90 Hz, switchable in System Settings), touch, backlight
- Wi-Fi (IPv4 and IPv6), Bluetooth
- Wi-Fi hotspot, also while the phone itself stays on Wi-Fi (shares that
  connection; `etc/NetworkManager/dispatcher.d/90-selene-hotspot`)
- Mobile network: calls with VoLTE and call audio, SMS, mobile data, signal strength (dual SIM)
- Audio: stereo speakers, earpiece, headphone jack, microphone, speakerphone
- GPS (MediaTek GNSS; connectivity drivers from the Redmi 12 branch, see
  `scripts/build-connectivity.sh`)
- Sensors: rotation, proximity, light
- Double tap to wake (System Settings; needs the kernel's NT36672C fix)
- Cameras (camera app): photo and video, flash, autofocus, all rear cameras
  including macro; real 50 MP photos (8160x6144) from the main camera
- Video recording up to 2560x1440 at 30 fps (H.264, hardware encoder);
  4K is beyond the encoder (2560x1440 maximum)
- Battery level and fast charging (QC 2.0, 9 V)
- USB: MTP/ADB/network to a PC, OTG host (keyboards, mice, storage, hubs),
  and host mode while charging from a powered hub (see below)
- Hardware video decoding and encoding (V4L2 and the Android codecs)
- GPU: OpenGL ES and Vulkan 1.1 (Mali-G52) through libhybris
- IR blaster (`selene-ir`)
- Waydroid (Android apps)
- TEE
- UBports recovery (Volume Up + Power), built into the boot image

Not working / not tested:

- Fingerprint: the FPC1022 driver works; enrolment from Ubuntu Touch is untested
- Camera frame rates above 30 fps (high-speed modes give black frames)
- 1440p recording reaches about 25 fps rather than 30
- No USB Power Delivery: the Type-C controller (WUSB3801) has none

### USB host while charging

The Type-C controller cannot negotiate power roles, so a powered hub makes the
phone see a charger and switch its USB to device mode. `selene-otg-charge`
puts the USB controller back into host mode when the phone charges and no USB
host is talking to it, and lifts the input current cap while it does. A PC
connection is unaffected (the phone stays a USB device). The hub needs a
steady power supply: a laptop USB-A port is not enough.

## Building

```bash
./build.sh
```

This runs the UBports
[halium-generic-adaptation-build-tools](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools)
through a small wrapper: kernel and boot image first, then the MediaTek
connectivity modules (WMT, Wi-Fi, Bluetooth, connfem), then the device tarball.
The modules are out-of-tree vendor drivers from Xiaomi's
[MTK_kernel_modules](https://github.com/MiCode/MTK_kernel_modules) (branches
`selene-r-oss-update` and `fire-t-oss`, pinned commits) plus
`patches/connectivity/`; they must match the exact kernel build, so
`scripts/build-connectivity.sh` builds them every time into
`overlay/system/usr/share/halium-overlay/vendor/lib/modules/` (not committed).

Output in `out/`: `boot.img` and the device tarball. CI uses the shared
community-ports pipeline (`.gitlab-ci.yml`) with the wrapper.

Host requirements are those of the build tools (git, python3, bc, bison, flex,
libssl-dev, lz4, cpio...), plus `git` with partial clone support.

## Installing

The port boots from slot **b**. The stock vendor (the drivers) stays on slot a
(`selene-dm-links` maps `vendor_b` to `vendor_a`), and Ubuntu Touch lives in
the logical `system_b` partition, 4.5 GB.

**Installing removes the stock Android system partitions** (`system_a`,
`system_ext_a`) from super, which only has room for Ubuntu Touch without them.
Stock MIUI does not boot afterwards; flash the stock firmware again to go
back. Back up anything you need first.

1. Unlock the bootloader and flash the stock MIUI 14 (Android 12) firmware, so
   the vendor partition is the one this port is built for.
2. `fastboot flash boot_b boot.img && fastboot set_active b`
3. Boot into the UBports recovery (Volume Up + Power) and install Ubuntu
   Touch with the UBports Installer, or push a system-image update to
   `/cache/recovery`. The recovery removes the stock system partitions, grows
   `system_b` to 4.5 GB and installs into it (the partition layout is set in
   `ramdisk-recovery-overlay/system/etc/init/selene-systemimage.rc`).

`ramdisk-recovery-overlay/system/bin/system-image-upgrader` is UBports' script
with two fixes, marked `selene:`: `lpresize` changes the partition tables of
both slots (the recovery maps the booted slot's table, the halium initramfs
reads slot 0's), and the system partition is looked up again after the resize
maps it to another device.

## Layout

| Path | What |
|---|---|
| `deviceinfo` | Device and build description for the build tools |
| `build.sh`, `scripts/` | Build wrapper and the connectivity module build |
| `patches/connectivity/` | Fixes to Xiaomi's connectivity sources for the 4.19 kernel |
| `ramdisk-recovery-overlay/` | UBports recovery: partition table, install layout, fixed upgrader |
| `overlay/system/` | Installed into the Ubuntu Touch rootfs, laid out as in `/` |
| `overlay/system/usr/share/halium-overlay/` | Bind-mounted over the Android vendor partition at boot |

Main pieces of the overlay:

- `etc/ofono/binder.conf`: modem (MTK RIL, IRadio 1.4, VoLTE)
- `etc/systemd/system/selene-dm-links.service`: slot b to slot a partition links
- `usr/libexec/lxc-android-config/device-hacks`: Wi-Fi bring-up (WMT)
- `etc/deviceinfo/devices/selene.yaml`, `etc/default/lsc-wrapper.d/`, `etc/ubuntu-touch-session.d/`: display, Mir (HWC2), scaling
- `selene-refresh-rate`: 60/90 Hz, with its System Settings page
- `selene-audio-tuning`: speakerphone tuning for the vendor audio HAL
- `selene-waydroid-binder`: binder devices for Waydroid
- `selene-otg-charge`: USB host mode while charging
- `selene-camera-macro`: makes the macro camera reachable from the camera
  app; at boot it patches one instruction of the device's own
  `libcameraservice.so` (known build only, checked by checksum) in a copy
  under `/run` and bind-mounts it over the original
- `selene-camera-50mp`: 50 MP photos. The kernel reads out the full sensor
  (4-cell Bayer); the camera HAL's own remosaic library (written for another
  sensor) is overridden with an open-source one (`camera/remosaic-shim/`,
  MIT); at boot a copy of `libmtkcam_metastore.so` with the 8160x6144 size in
  its size table is bind-mounted over the original (checked by checksum)
- `selene-camera-video`: offers 2560x1440 video in the camera app (copy of
  `media_profiles_V1_0.xml` with a 1440p profile)
- `camera/afsession-shim/`: preloaded into Halium's `camera_service` so that
  stopping a video does not wait forever for Android's AudioFlinger (which
  Ubuntu Touch does not run) and hang the camera app
- Lomiri component and camera app QML fixes for the screen shape and gestures

## Licensing and firmware

The repository follows the [REUSE](https://reuse.software) specification
(`reuse lint` passes, and CI runs it). `REUSE.toml` gives the copyright and
licence of every file, and the licence texts are in `LICENSES/`:

- The scripts and configuration written for this port: GPL-3.0-only (`LICENSE`).
- Files that override parts of Ubuntu Touch keep the licence of the project
  they come from: the Lomiri UI Toolkit QML (LGPL-3.0, with kugiigi's MariKit
  back gesture, GPL-3.0), the camera app QML (GPL-3.0), `mount-android-partitions`
  (lxc-android-config, GPL-3.0-or-later), `system-image-upgrader`
  (halium_bootable_recovery, Apache-2.0) and the Android init scripts (Apache-2.0).
- The patch to Xiaomi's connectivity driver: GPL-2.0-only, like the driver.
- The remosaic shim and the library built from it: MIT (bellhopsw).

No vendor firmware or binaries are included. The touch controller firmware
is loaded from the phone's own vendor partition (`firmware_class.path=/vendor/firmware`,
set by the bootloader), the connectivity modules are built from Xiaomi's
published GPL sources, and the camera fixes patch the phone's own libraries at
boot. The two prebuilt shims (`libremosaic_wrapper.so`,
`libselene_afsession.so`) are built from the sources in `camera/`.

## Credits

Xiaomi (kernel and module sources), the UBports porters and the Halium project.
50 MP: the S5KJN1 full-resolution register table and the remosaic library come
from [bellhopsw/q25-50mp](https://github.com/bellhopsw/q25-50mp) (MIT).
