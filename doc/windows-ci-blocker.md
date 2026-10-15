# Windows CI and delivered package — 2026-10-15 UTC

**Current continuation (acceptance still in progress):** application source
`9ed8dd60b3e9fb2ead8a833a709c393bd699f3d3` compiled and packaged with Qt 6.8.3
and the upstream Win64 MinGW POSIX toolchain:
https://github.com/thgzzs/vlc/actions/runs/38756194984/job/116495262897 .
Engine smoke and TLS lifecycle tests passed. The actual development ZIP is
https://github.com/thgzzs/vlc/actions/runs/38756194984/artifacts/11985690393 ,
SHA256 `e19609af819396383cb4c4b070b93807c7a145eea66140e3ad5ef4783ed70baf`.
The GUI test passed waveform generation/cache, toolbar drag/cancel, reviewed bulk
matching/native queued subtitle loading, and folder timing save/return/isolation.
A real folder-rate restoration bug was fixed by using VLC's native speed request
without the demux-capability gate. Runs 38780610713 and 38782066172 also passed
one-minute timer expiry, first clean exit, actual preset restart application and
removal. Full acceptance still awaits exact-media library re-open and the second
clean exit. A read-only diagnostic confirmed the two generated fixture subtitle
associations are persisted as external subtitle files. The original Ctrl+1 test
selected a recent audio fixture rather than the required video; exact selection
through Open Recent still reproduced the loss. Source inspection found external
preparsing replacing explicit user slaves with its URI-only worker result. The
core merge now retains user associations and has a native Windows regression;
this new source must compile/package and pass the full runtime before delivery.
Current source `2624bce20176c5b924c73e712a2988c236915006` is building in
https://github.com/thgzzs/vlc/actions/runs/38785832090 . Another test race was fixed:
player-wide PLAYING can precede the new decoder, so pause checks require real
decoded frames. Native thread-stack capture remains available on timeouts.

The initial ref-only rate-fix update produced a delayed push run; it superseded an
intermediate contents-push run. PR checkout now pins the same immutable head for
compilation and GUI tests. Run 38755438439 used an older synthetic merge and was
superseded, never counted as validation of the fix. Test-only pushes continue to
use the separate pinned runtime workflow. Historical successful checkpoints
below contain earlier application sources and do not establish current acceptance.


The native application compiled, packaged and passed the complete packaged Windows
runtime workflow. This is a tested development preview with the feature/test gaps
below, not full implementation of every concept in the reference video.

## Historical baseline build and package

- Application source: `65a90f7ccf5a235fc777f2d80a1cc732f3edf5a7`.
- Native compilation/packaging passed:
  https://github.com/thgzzs/vlc/actions/runs/38695316946/job/116290430565
- Packaged engine startup and normal exit passed:
  https://github.com/thgzzs/vlc/actions/runs/38695316946/job/116296904600
- Portable Windows x64 ZIP:
  https://github.com/thgzzs/vlc/actions/runs/38695316946/artifacts/11954356651
- ZIP SHA256, independently downloaded and checked:
  `57adc9f542135ce203f3d3558982548bd0407658381a47452b68fde6c68420f8`.
- Qt 6.8.3 / Win64 MinGW POSIX; upstream container
  `registry.videolan.org/vlc-debian-win64-posix:20260611225331`.

Extract the entire ZIP and run `vlc-juxtopposed.cmd`. It enables the native library
and pinned controls. The archive contains 666 entries including vlc.exe,
libvlc/libvlccore, plugins, GCC runtimes, font license and design attribution.
Qt is linked into `plugins/gui/libqt_plugin.dll`; there are no separate Qt DLLs
to deploy. There is no NSIS installer in this delivery.

## Historical baseline runtime acceptance

https://github.com/thgzzs/vlc/actions/runs/38700128120 — **success**.
Test source: `6d04350bc630fbcaa938458d9b3fe79e1593bd65`. This run downloads the exact
immutable package above. The results in this section apply only to that immutable baseline ZIP.

- Fresh hosted Microsoft Windows Server 2025 runner, 1024×768 desktop; native
  window sizes 984×688 and 700×600. This is not a clean consumer Windows machine.
- Real WAV/video decoding, accessible play/pause/resume, decoded midpoint seek,
  next/previous media, resizing, F/Escape fullscreen and real seek thumbnail passed.
- All 13 exact settings headings passed via native keyboard navigation; captured
  screens inspected. Profile save, Light selection, saved Dark restoration and
  deletion passed. Customizer open/cancel passed; drag/drop was not tested.
- Native subtitle file picker, two parsed SRT cues and decoded seek to 4.6s passed.
  The native next-frame hotkey advances the paused decoder, avoiding measurement
  overshoot from slow automation round trips.
- Named bookmark add/remove, Ctrl+B recreation, visible absence on other media,
  restoration on return, decoded seek to 4.8s and final removal passed. The test
  follows the newly created bookmark rather than assuming an identical timestamp.
- Native rendered metadata and live decoder counters passed.
- A real one-minute timer stopped playback after 59.596s measured after setup.
- Onboarding changed Light to Dark, finished and exited normally. A real restart
  retained Dark, did not repeat the wizard and exited normally again.
- Audio/video native exits required `WaitForExit` and exit code zero; runtime QML
  error scan passed. No forced VLC termination counts as a successful exit.
- Audit of 417 x64 PE images found no unresolved normal/delay imports. The
  four-plugin GCC exception-runtime relink audit passed during compilation.

[GUI screenshots/logs/results](https://github.com/thgzzs/vlc/actions/runs/38700128120/artifacts/11955752527)
SHA256 `70d9891057a8381cb2a63cf0d868e255c0dccf4164d8343f6873d095e5a8ff79`.
[TLS lifecycle regression](https://github.com/thgzzs/vlc/actions/runs/38700128120/job/116306723062)
passed normal key deletion/unload and guarded process detach; the unguarded
negative control reproduced the original hang. Its isolated pass supplements,
and does not replace, the actual VLC clean exits.

## Diagnosed regressions and CI history

The original build run is not wholly green: its frozen GUI assertions and initial
TLS fixture failed. The successful runtime workflow above tests the same package
with corrected tests. Historical failures are not being described as successes.

CDB and the unstripped symbol map resolved the shutdown hang to libstdc++'s
condition-variable thread-exit key destructor, pthread_key_delete and the
winpthreads key rwlock during LdrShutdownProcess. The MinGW wrapper uses directly
imported RtlDllShutdownInProgress, skipping only OS process-termination key
bookkeeping. Normal deletion/FreeLibrary forward to the real implementation.
The earlier Qt worker-pool drain failed to fix it and was removed. The initial
CreateThread fixture blocked under the loader lock; pthread_create reproduces
the actual cleanup callback outside that lock.

Bookmark testing found the medialibrary API returning VLC_EGENERIC after a
successful add, so the caller skipped its name. The one-line VLC_SUCCESS contract
fix in 65a90f7 was the baseline multimedia source change outside Qt. The current
continuation also restores explicit external subtitle associations in
`modules/misc/medialibrary/entities.cpp`. A third related fix preserves explicit
user slaves in `src/input/item.c` when external preparsing updates metadata.
Native input creation logs only media IDs and file/slave counts, never paths.

The initial absence of runs had two causes: the push filter omitted the feature
branch, and GitHub displayed a repository restriction requiring maintainer
re-enablement. Authentication/re-enablement and the branch trigger are restored.
Feature-branch pushes build source changes; PR opened/reopened/ready events also
build. Push covers synchronize without restarting compilation for test/docs-only
changes. A separately pinned runtime workflow supports test iteration.

The first compiler regressions were corrected and subsequently compiled:
https://github.com/thgzzs/vlc/actions/runs/38661285852 (bookmark clear guard),
https://github.com/thgzzs/vlc/actions/runs/38662133653 (subtitle notification signals).
No history rewrite, master/upstream change, merge or public release was performed.

## Remaining limitations

The continuation implements bounded session-cached waveforms, reviewed bulk
subtitle matching and exact-folder timing presets. Waveforms, reviewed subtitle matching and folder timing switching have passed
their individual Windows checks; full current-package acceptance is still pending. See `native-redesign-integration.md` for
limits and pending tests. Disk-persisted waveform analysis and automatic per-show
font/effect/appearance profiles remain unimplemented. Named application profiles
apply explicit global defaults.

Dummy audio validates decoding/control flow, not hardware sound or volume/mute.
Track switching, DPI, library/playlist persistence, large-library performance,
full settings persistence, network/capture/convert/stream and error-dialog flows,
saving customized toolbars across restart and full pixel-level fidelity remain
unverified. Actual toolbar drag/cancel passed in the current continuation. See
`juxtopposed-video-scope.md` and draft PR #1 for the full scope inventory.
