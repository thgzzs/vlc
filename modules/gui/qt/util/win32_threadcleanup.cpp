/*****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#if defined(__MINGW32__)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <pthread.h>

// Import directly: resolving this with GetModuleHandle during DLL detach can
// itself acquire a lock abandoned by a terminated thread.
extern "C" __declspec(dllimport) BOOLEAN NTAPI RtlDllShutdownInProgress();
extern "C" int __real_pthread_key_delete(pthread_key_t key);

extern "C" int __wrap_pthread_key_delete(pthread_key_t key)
{
    // The statically linked libstdc++ condition-variable notifier deletes its
    // pthread key in a DLL static destructor. During ExitProcess all other
    // threads have already been terminated: winpthreads' key rwlock can retain
    // a reader whose cleanup callback will never return. Waiting here leaves
    // the process permanently stuck in LdrShutdownProcess.
    //
    // Only process termination skips this bookkeeping. The OS reclaims every
    // key/allocation then; ordinary key deletion and FreeLibrary still use the
    // real implementation. Player, media-library and Qt cleanup run normally
    // before this point. No process is forcibly terminated by this wrapper.
    if (RtlDllShutdownInProgress())
        return 0;
    return __real_pthread_key_delete(key);
}
#endif
