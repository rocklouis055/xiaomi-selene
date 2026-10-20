# libselene_afsession.so

LD_PRELOAD for Halium's `camera_service` (32-bit), loaded through
`/system/etc/init/camera_service.rc` in the Halium overlay.

Stopping a video in the camera app makes `camera_service` destroy its
`StagefrightRecorder`; `~AudioRecord()` then calls
`AudioSystem::releaseAudioSessionId()`, which waits for the
`media.audio_flinger` binder service. Ubuntu Touch has no AudioFlinger, so
`get_audio_flinger()` retries forever, the recorder's `release()` never
returns, and the camera app hangs (and cannot be relaunched). The shim makes
that call a no-op. The recorded file is already complete at that point.

Build (NDK r27c):

    armv7a-linux-androideabi31-clang -O2 -shared -fPIC \
        -Wl,-soname,libselene_afsession.so -o libselene_afsession.so \
        afsession_shim.c -llog

The prebuilt copy lives in
`overlay/system/usr/share/halium-overlay/system/lib/hw/` (the linker's
`default` namespace for /system binaries permits /system/lib/hw).
