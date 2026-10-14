# VLC Windows x64 native redesign — development checkpoint

Compiled source: 10e67ea7ab714f2d68b8b7ebf648e6b2ad62b012.
Latest source/build fix: 959bbd7ab090050f4b62308ce13f523993287063 (not yet compiled or verified).
GUI test source: 942d2c74d47b84c8e8272808690d1ac0810840a3 on figma-redesign-gui-tests.

Build: https://github.com/thgzzs/vlc/actions/runs/38645449054
ZIP: https://github.com/thgzzs/vlc/actions/runs/38645449054/artifacts/11932719099
Size: 101,910,943 bytes (97.2 MiB).
SHA-256: 65f0596b69b42bda958f1fb2337677a24afe6475fe3c9e676681f1fc10e5e3d7

## Run
Extract the complete ZIP. Keep the DLLs, plugins and assets beside vlc.exe.
Launch vlc-juxtopposed.cmd inside the extracted VLC folder.
A fresh Windows configuration selects Night and the Juxtopposed toolbar profile. Existing saved selections are preserved; select those options to inspect this layout.

## Actual results
| Check | Result |
| --- | --- |
| Native Windows x64 compilation | Passed |
| Full directory packaging and upload | Passed |
| Archive SHA-256 | Verified against GitHub artifact metadata |
| Final PE import inspection | Four plugins still import libgcc_s_seh-1.dll |
| New-layout Windows GUI tests | Cancelled before completion; one retry requested |
| New-layout video/fullscreen/seek/playlist tests | No completed result |
| Visual comparison against supplied frames | Pending new Windows screenshots |

The four affected plugins are SRT input, SRT output, x265 encoder, and Game Music Emu. Earlier packages failed to load these dependencies because VLC restricts DLL search to System32. The same shared imports remain in this ZIP despite -static-libgcc. Copying runtime DLLs beside vlc.exe did not fix earlier loader checks.

Commit 959bbd7 adds a targeted relink of these four plugins: remove explicit -lgcc_s from generated SRT_LIBS, LIBS_x265 and LIBS_gme, link libgcc_eh/libgcc statically, and inspect final DLL imports before packaging. This correction is unverified. At this checkpoint no Actions run/check was returned for this commit; the GUI retry was queued without an allocated job. The reason is not established.

Earlier initial-build tests proved startup, WAV decode and native Play/Pause/resume, including wide/narrow resizing. They do not validate the new layout in this ZIP. Dummy audio was used; physical audio output was not tested.

## Implemented native layout checkpoint
Dark palette and fresh Windows theme/profile defaults; compact player navigation and left docked queue; inline seek/timestamps on wide windows and stacked narrow fallback; native playback SVGs; library navigation/card styling; mini-player styling; scrolling track popups and real subtitle-delay slider; native preferences/dialog styling. VLC controllers and multimedia engine are used.

## Remaining work
This is not the complete Juxtopposed redesign. Full settings category restructuring, onboarding, remaining dialogs/menu variants, light-theme fidelity, original icon/font exports, complete visual comparisons, subtitle/audio-track switching, stop/volume/mute, settings persistence, keyboard shortcuts, DPI scaling (100/125/150%), hardware audio/video and performance validation remain pending.

Figma access hit the Starter quota. The supplied ZIP has 25 PNG references, without editable design data, font files or a redistribution license. No screenshots are substituted for interactive UI or media artwork. Design credit: Juxtopposed, https://www.figma.com/design/4ee8qiJqONgpJMPhP5DkTy/.
Asset redistribution terms remain unconfirmed; no public release or merge into master is authorized.

All source/build changes are in thgzzs/vlc development branches. The source tree was restored after an incomplete-tree commit; master and the official upstream repository were not changed.
