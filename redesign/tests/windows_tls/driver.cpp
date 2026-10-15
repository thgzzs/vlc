// SPDX-License-Identifier: GPL-2.0-or-later
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>

int main(int argc, char** argv)
{
    if (argc != 3) return 11;
    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) return 12;
    auto exercise = reinterpret_cast<int (*)(int)>(GetProcAddress(dll, "exercise_keys"));
    if (!exercise) return 13;
    const bool block = std::strcmp(argv[2], "block") == 0;
    const int result = exercise(block);
    if (result) return result;
    std::puts(block ? "TLS cleanup reader is blocked; exiting normally" : "Normal key lifecycle passed; unloading normally");
    std::fflush(stdout);
    if (!block && !FreeLibrary(dll)) return 14;
    return 0;
}
