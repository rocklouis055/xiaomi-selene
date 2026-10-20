# Remosaic library for the 50 MP mode

`libremosaic_wrapper.so` turns the Samsung JN1 sensor's full-resolution
quad-Bayer (4-cell) frame into an ordinary Bayer frame for the ISP. The phone's
own `libremosaiclib.so` is Samsung's remosaic for a different sensor (S5K2T7,
"180321_2T7_china_speed2_reference") and produces garbage on JN1 frames.

`remosaic_shim_v4_rc1.c` is unchanged from the Zinwa Q25 50 MP project by
bellhopsw (https://github.com/bellhopsw/q25-50mp, `src/shim/`, md5
`35f588721cb8e93f28b332df9fe9f145`), MIT licence (`LICENSE`). It implements
MediaTek's remosaic wrapper interface, the same one selene's camera HAL
(`libcameracustom.plugin.so`) calls: `remosaic_init`, `remosaic_process`,
`remosaic_gainmap_gen`, `remosaic_process_param_set`, `remosaic_deinit`.

Reviewed for selene: only image processing, threads and memory; reads its own
`persist.vendor.remoshim.*` properties; the only file it touches is its
calibration record `/data/vendor/camera/remoshim_cal.bin`.

The built library is installed at
`overlay/system/usr/share/halium-overlay/vendor/lib64/libremosaic_wrapper.so`
and bind-mounted over the vendor one at boot. Rebuild it with the Android NDK
(r27c used):

    $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang \
        -O3 -mcpu=cortex-a75 -shared -fPIC -Wl,-z,nodelete \
        -o libremosaic_wrapper.so remosaic_shim_v4_rc1.c -llog -lm

Settings tuned for selene's camera: `persist.vendor.remoshim.dn=5` (light
denoise) and `persist.vendor.remoshim.sharpen=60`, set by
`selene-camera-50mp.rc`.
