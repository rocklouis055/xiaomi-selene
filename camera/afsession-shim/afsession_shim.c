/*
 * selene: LD_PRELOAD for Halium's camera_service.
 *
 * When the camera app releases its media recorder, ~AudioRecord() calls
 * AudioSystem::releaseAudioSessionId(), which asks the media.audio_flinger
 * binder service for it. Ubuntu Touch runs no AudioFlinger (the recorder gets
 * its audio from Halium's hybris microphone path), so get_audio_flinger()
 * retries forever: the release never returns, the camera app hangs right
 * after "stop recording" and cannot be started again.
 *
 * The session id was never allocated by an AudioFlinger, so there is nothing
 * to release: make the call a no-op.
 */
#include <android/log.h>

void release_audio_session_id(int session, int pid)
    __asm__("_ZN7android11AudioSystem21releaseAudioSessionIdE15audio_session_ti");

void release_audio_session_id(int session, int pid)
{
    __android_log_print(ANDROID_LOG_DEBUG, "selene-afsession",
                        "releaseAudioSessionId(%d, %d) skipped (no AudioFlinger)",
                        session, pid);
}
