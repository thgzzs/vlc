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

static void* worker(void*)
{
    pthread_setspecific(lifetime.key, reinterpret_cast<void*>(1));
    return nullptr;
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
    // pthread cleanup runs before ExitThread and outside the Windows loader
    // lock. Blocking a CreateThread TLS callback instead would prevent main
    // from entering ExitProcess at all, reproducing a different deadlock.
    pthread_t thread;
    if (pthread_create(&thread, nullptr, worker, nullptr) != 0) return 6;
    if (WaitForSingleObject(entered, 5000) != WAIT_OBJECT_0) return 7;
    // In block mode the thread is inside winpthreads' TLS callback with its
    // key read lock held. Returning from main now makes Windows terminate it.
    if (blockAtThreadExit) {
        if (WaitForSingleObject(releaseCallback, 0) != WAIT_TIMEOUT) return 8;
    } else {
        if (pthread_join(thread, nullptr) != 0) return 9;
        CloseHandle(entered);
        CloseHandle(releaseCallback);
    }
    return callbacks == 1 ? 0 : 10;
}
