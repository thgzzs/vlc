// SPDX-License-Identifier: GPL-2.0-or-later
// Deterministic reproduction of a TLS cleanup reader abandoned by ExitProcess.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <pthread.h>
#include <cerrno>

static HANDLE entered, releaseCallback;
static volatile LONG callbacks;

static void cleanup(void*)
{
    InterlockedIncrement(&callbacks);
    SetEvent(entered);
    WaitForSingleObject(releaseCallback, INFINITE);
}

static struct KeyLifetime {
    pthread_key_t key;
    bool valid = pthread_key_create(&key, cleanup) == 0;
    ~KeyLifetime() { if (valid) pthread_key_delete(key); }
} lifetime;

static DWORD WINAPI worker(void*)
{
    return pthread_setspecific(lifetime.key, reinterpret_cast<void*>(1));
}

extern "C" __declspec(dllexport) int exercise_keys(int blockAtThreadExit)
{
    if (!lifetime.valid) return 1;
    // An unconditional no-op wrapper would fail this invalid-key assertion.
    if (pthread_key_delete(static_cast<pthread_key_t>(-1)) != EINVAL) return 2;
    pthread_key_t ordinary;
    if (pthread_key_create(&ordinary, nullptr) != 0) return 3;
    if (pthread_key_delete(ordinary) != 0) return 4;
    entered = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    releaseCallback = CreateEventW(nullptr, TRUE, !blockAtThreadExit, nullptr);
    if (!entered || !releaseCallback) return 5;
    HANDLE thread = CreateThread(nullptr, 0, worker, nullptr, 0, nullptr);
    if (!thread) return 6;
    if (WaitForSingleObject(entered, 5000) != WAIT_OBJECT_0) return 7;
    // In block mode the thread is inside winpthreads' TLS callback with its
    // key read lock held. Returning from main now makes Windows terminate it.
    if (blockAtThreadExit) {
        if (WaitForSingleObject(thread, 0) != WAIT_TIMEOUT) return 8;
    } else {
        if (WaitForSingleObject(thread, 5000) != WAIT_OBJECT_0) return 9;
        CloseHandle(entered);
        CloseHandle(releaseCallback);
    }
    CloseHandle(thread);
    return callbacks == 1 ? 0 : 10;
}
