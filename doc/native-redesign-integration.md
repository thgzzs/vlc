# Native redesign integration

This branch builds on the existing thgzzs/vlc figma-redesign history. The initial
four playback SVGs, their resource entries, stable toolbar profile identifier,
Windows build fixes, launcher, and existing saved toolbar profiles are retained.
The playback vectors are rendered through the common theme-aware SVG provider;
their source geometry is unchanged.

The expanded native Qt/QML implementation reuses GPL-covered work from:
- https://github.com/Pyr0zen/vlc, redesign commit
  680592f5a51fccc1e62b7aaca788ddaab7127046 (player, panels, library, dialogs,
  onboarding, customization, theme and reusable widgets).
- The same repository's redesign-settings commit
  f66484e37d7d55aa6bd5fdd76ed4e1ddf24dcd76 (13 settings categories and the native
  option catalog, pickers, persistence bindings and advanced settings).

Source headers and VLC's GPL/LGPL notices remain intact. No donor CI workflow,
private work notes, reference video, music or screenshot imagery is imported.
The Inter font's SIL Open Font License is retained beside the font files.

Visual design and original icons: Juxtopposed, VLC Redesign (Community):
https://www.figma.com/community/file/1691465999134370980
https://www.figma.com/design/4ee8qiJqONgpJMPhP5DkTy/
Reference video: https://www.youtube.com/watch?v=ERFeOgqk324
Additional SVG exports retain the provenance of the source implementation.
Figma's stated license for free Community files is CC BY 4.0:
https://help.figma.com/hc/en-us/articles/360042296374-Figma-Community-copyright-and-licensing
No public release is authorized; remaining asset/license verification must be
recorded before release. Media artwork and thumbnails use the real library data.

The integration preserves VLC's multimedia pipeline. Legacy complete preferences
remain reachable for advanced options. Stable toolbar control enum values are
preserved; dedicated audio/subtitle controls occupy previously reserved values.
Settings and sidebar pages load on demand; inactive pages do not create all their
controls during startup. Menu/modal ownership and focus are centralized, and
library views reuse VLC's models and asynchronous thumbnail loading.

Local verification uses the actual Qt 6.8.3 QML compiler with C++ registration
stubs. This catches type/property/alias errors but does not prove native playback
or backend bindings at runtime. The high-resolution-time value source is the one
known stub limitation. Build registration/resource checks and Windows compilation,
GUI playback, layout, dependency, DPI and performance checks must also pass.

New backend features from the video (for example sleep timer, cue timeline,
waveform/thumbnail generation, bulk subtitle matching and broader presets) require
their own functional implementation and tests; importing the UI does not mark
those features complete.

## Native playback services

`PlaybackTools` adds a cancellable sleep timer (1–1440 minutes, 30/60/90-minute
presets) and live statistics. The deadline uses Qt's monotonic clock and includes
paused time. Expiry stops the native playlist controller; no shutdown command is
executed. The one-second timer is inactive unless armed. Statistics subscribe to
the existing player signal only while the expanded playback section is visible,
clear on media changes, and do not poll or duplicate decoding. Metadata bindings
use the existing player fields and retain the native metadata editor and codec
information dialog.

The bookmark sidebar and Ctrl+B now share one media-library model. Add records
the current playback time; remove acts on the selected row. Both persist through
VLC's existing media-library worker queue. The advanced bookmark editor remains
available through VLC's existing menus. With the media library disabled, the
bookmark shortcuts and list are not loaded.

The Qt 6.8.3 source checker now returns nonzero for compilation diagnostics and
worker crashes. Its exact HighResolutionTimeUpdater value-source stub limitation
is reported separately. This check compiles QML; it does not prove C++ compilation,
window instantiation, playback or Windows packaging.


## External subtitle source cues

The optional subtitle timeline uses the existing `AsyncTask`/`TaskHandle`
infrastructure and a virtualized list. It accepts explicitly added local SRT and
WebVTT files encoded as UTF-8 or BOM-detected Unicode. It does not fetch remote
URLs or replace VLC's subtitle decoder. Parsing is deferred until the timeline
is enabled; changing media abandons pending results. Files are limited to 8 MiB,
50,000 cues and 8 KiB of text per cue. The seek-bar overlay always has at most 256
bins, prepared on load/length changes instead of every playback frame.

Cue times are **source timestamps**. Click-to-seek uses those original times;
subtitle delay, FPS and duration effects remain separate native controls. This
is not extraction of embedded subtitle streams, and a selected cue file is not
a claim that another selected subtitle track has identical text/timing.

The standalone C++ parser tests cover SRT/CRLF, Unicode text/BOM, WebVTT settings
and comments, overlapping and out-of-order cues, malformed/overflowing timestamps,
empty/reversed ranges, missing separators and file/cue/text bounds, plus 10,000
deterministic malformed byte strings. They pass with `-fsanitize=undefined`.
Address/LeakSanitizer could not finish in this sandbox because it cannot access
`/proc` task information; no memory-sanitizer pass is claimed. The Windows build
workflow runs the standalone parser regression suite before compiling VLC.

Additional bookmark safeguards clear stale rows during media lookup and check the
player item and library revision under their existing locks before recording a
quick bookmark. An old library ID cannot be reused for a newly selected file.

## Validation status

- 358 QML files compile in the Qt 6.8.3 source checker: zero actionable errors,
  zero worker crashes, one separately reported native timer stub limitation.
- The QML failure gate rejects an injected invalid type with a nonzero exit.
- Resource registration, original asset checks and whitespace checks pass.
- Windows C++ compilation, stripping/packaging, packaged engine startup/exit and
  the audit of 417 PE images passed for source `0ece54a9a53e59f7c2620ab0e8180fb316eac506`:
  https://github.com/thgzzs/vlc/actions/runs/38680067863
- Native Windows tests have passed audio/video decoding, play/pause/resume,
  decoded midpoint seeking, next/previous, resizing, F/Escape fullscreen, a real
  decoded seek-preview image, application profile save/apply/delete and theme
  restoration. Results are tied to the immutable package source, not later code.
- Source `c12c0aa742875fa514fc3090a507e0baf2838d72` compiled and packaged:
  https://github.com/thgzzs/vlc/actions/runs/38684762153 . Its engine smoke and
  417-image import audit passed, but GUI clean shutdown still failed. The global
  Qt pool drained successfully and was ruled out as the cause.
- CDB plus the unstripped symbol map locate the wait in libstdc++'s condition-
  variable thread-exit key destructor, `pthread_key_delete` and the winpthreads
  key rwlock during Windows `LdrShutdownProcess`. The source now wraps key deletion
  only during OS process termination, using directly imported
  `RtlDllShutdownInProgress`. Ordinary deletion/unloading still call the real
  implementation. This does not force process termination or bypass VLC cleanup.
  Microsoft documents why DLLs should leave resource reclamation to the OS in
  this phase: https://learn.microsoft.com/en-us/windows/win32/dlls/dllmain .
- Windows runtime https://github.com/thgzzs/vlc/actions/runs/38694052885 verified
  all 13 exact settings headings through real Down-key category navigation. Their
  screenshots were visually inspected. The file picker is an owned native child;
  its UIA bridge represents the file-name edit as a Pane. Native Alt+N/paste and
  normalized Windows paths load the fixture without blocking the automation client.
- https://github.com/thgzzs/vlc/actions/runs/38694635008 verified native subtitle
  loading, two parsed SRT cues and decoded seeking to the 4.5-second source cue.
- https://github.com/thgzzs/vlc/actions/runs/38695722580 additionally verified the
  rendered native source URL and live decoder statistics. The dummy audio output
  has no volume/mute callbacks and returns volume -1; those controls remain
  explicitly unverified on this runner, rather than being counted as passed.
- Native bookmark testing found a real backend return-value defect: successful
  `VLC_ML_MEDIA_ADD_BOOKMARK` returned `VLC_EGENERIC`, preventing the caller from
  assigning its name. `65a90f7` corrects that return to `VLC_SUCCESS`; it is the
  only change outside Qt/build/tests/docs and directly supports the bookmark API.
- The previously validated application source `65a90f7` compiled and packaged in build job
  https://github.com/thgzzs/vlc/actions/runs/38695316946/job/116290430565 . The exact
  portable ZIP and SHA256 are recorded in `windows-ci-blocker.md`. Subsequent
  tests are tied to that exact package; the continuation below changes application code.
- Complete runtime https://github.com/thgzzs/vlc/actions/runs/38700128120 passed
  on this exact package, using test commit `6d04350`. Audio/video native shutdown,
  all 13 headings, profiles, subtitles, metadata/statistics, named bookmarks,
  Ctrl+B, decoded bookmark seeking/removal and visible media-switch isolation
  passed. Screenshots and machine-readable results are linked in
  `windows-ci-blocker.md`.
- Onboarding finished, exited zero, restarted with retained Dark theme and no
  repeated wizard, then exited zero again. Customization opens/cancels; drag/drop
  editing remains unverified. A real one-minute timer stopped playback. Tests
  require `WaitForExit` and exit code zero, never just `HasExited`.
- Native E/next-frame advances the paused decoder for source-cue/bookmark seek
  checks. Distinct pointer clicks respect the Windows double-click interval.
  Ctrl+B is checked against its newly created row, not the deleted row's timestamp;
  sidebar actions are operated only while the list is visible.
- The isolated MinGW regression exercises normal key deletion and module unload
  plus a worker blocked in pthread cleanup outside the loader lock. The unguarded
  binary must reproduce the shutdown wait; the guarded one must exit zero. The
  earlier CreateThread fixture blocked under the Windows loader lock, a different
  deadlock, and was corrected. A separate runtime build compiles/tests this fixture
  without restarting unchanged VLC compilation.
- Hardware output, DPI, measured UI performance and complete visual fidelity are
  not established. Actual run links, package hashes and blockers are tracked in
  `windows-ci-blocker.md` and draft PR #1. The hosted Windows suite passed; that
  does not establish hardware sound, DPI, complete option persistence, all VLC
  dialog/library workflows or full visual parity.
- Pull-request builds target `figma-redesign` inside this fork. Main/master and
  upstream are outside this change. No merge or public release is authorized.

The full workflow compiles and packages each native source change. A separate
runtime workflow downloads a specifically pinned compiled artifact to iterate
GUI tests without recompiling unchanged code. Test-only or documentation pushes
must not cancel an expensive native build. Evidence is preserved on failure,
including incremental check results, screenshots, logs and native shutdown stacks.

## Seek previews and application default profiles

The native seek-preview service uses VLC's preparser/thumbnailer to produce real
320x180 PNG frames for local video. It debounces pointer movement for 150 ms,
allows one cancellable request with a five-second timeout, quantizes requests to
two-second buckets and keeps at most 32 images in a temporary cache. Media changes
invalidate requests and images; stale completions cannot replace the new media's
preview. Preview file loading is asynchronous. No hover request opens a remote
media URL. The playback sidebar exposes the preview toggle.

Application profiles store named appearance and explicitly listed audio, video
and subtitle defaults in the native Qt settings store (maximum 32 profiles,
80-character names, schema version 1). Save/apply/delete actions report storage
errors. Theme and accent update through MainCtx; playback defaults use RdEffects
and apply to new media, with restart requirements stated in the settings page.
This is not a snapshot of every VLC option or of current per-input effects.
Passwords, paths, network/privacy options and existing toolbar profile records and
IDs are outside these snapshots. The original toolbar profile editor remains.

The segmented controls now use Qt abstract buttons with tab roles and selected
states, preserving their geometry/colors and group keyboard navigation. The
prepared Windows GUI tests exercise all 13 settings categories, native preview
image loading, application profile save/apply/delete and theme restoration, clean
window shutdown, and failure screenshots/accessible-control dumps. Only actual
completed Windows runs can validate these additions.

## Bounded audio waveforms

The opt-in `AudioWaveform` service decodes the primary audio track of a local file
through a private native VLC player and transcode/smem output. It produces 256
peak bins from 8 kHz mono PCM16 on one worker, never controlling the main input.
`smem{no-time-sync,...}` is required: VLC chain booleans use presence/negation,
so `time-sync=false` still enables pacing. The dedicated decoder clears inherited
slaves, filters and interactivity. Analysis rejects remote/UNC inputs, files over
2 GiB and durations over six hours; blocks and sample counts are bounded, with a
60-second wall deadline and cancellation checked every 50 ms. The worker is joined
before Qt/VLC object cleanup.

A 32-entry session cache keys canonical path, size, modification time and duration;
the file is checked again before publication. Media changes abandon stale results.
A single cached `QQuickPaintedItem` texture renders the envelope, with no per-frame
PCM aggregation or hundreds of QML nodes. Waveforms describe the primary audio
track relative to its first audio timestamp. They are not selected-track/effects
visualization, persisted disk analysis or a measured large-library performance pass.

Source `6c9a7b1` compiled/packaged with Qt 6.8.3 and passed the complete Windows
runtime workflow https://github.com/thgzzs/vlc/actions/runs/38741034605 . The PCM
fixture contains silence/25%/75%/silence quarters; native tests verified 75% peak,
unchanged paused main playback, native cache reuse, generation after media switching
and clean shutdown. The standalone envelope regression also covers chunking, gaps,
invalid data, duration/position overflow and signed minimum samples with UBSan.

## Reviewed bulk subtitle matching

`BulkSubtitleMatch` snapshots up to 200 queued input items and scans one local
folder off the UI thread, without recursion or symlinks. It visits at most 5,000
entries and accepts SRT/VTT/ASS/SSA files no larger than 8 MiB. Exact normalized
filename stems can shed up to four recognized language/accessibility suffixes;
there is no fuzzy episode guessing. A unique candidate is preselected; ambiguous
candidates remain skipped until the user chooses. The modal review uses existing
native widgets and a virtual list. Scanning is cancellable and uses one worker.

Save writes external subtitle associations through VLC's media-library worker.
The callback rechecks stable queue IDs, held input items and unchanged URIs before
adding native subtitle slaves for their next playback. It leaves the current
selected track unchanged and reports partial failures. Removed queue items retain
their valid library association. A fresh library input now reconstructs up to 32
associated subtitle slaves; unavailable subtitle devices do not block the main
media. Opening a file directly by path does not promise a library association
lookup. This is the second related multimedia source fix outside Qt, alongside
the earlier bookmark success-return correction.

Windows compilation, reviewed application, native subtitle loading and association
persistence/reopen tests for this continuation are **pending**. A test checks a
fresh input created by the existing Ctrl+1 library shortcut after actual restart,
requiring a native subtitle-load log outside the media directory; same-folder
subtitle autodetection cannot satisfy it. Do not treat prepared tests as passes.

## Exact-folder timing presets

`FolderPresets` stores at most 128 named records in a separate versioned Qt
settings key. It saves speed (0.25–4×), audio/subtitle delays (±10 minutes) and
external subtitle FPS (0–120). Invalid/non-finite records and names over 80
characters are rejected. The exact canonical local folder scopes a record;
subfolders do not inherit it. Player APIs apply per-input delays, and previous
player-wide rate/FPS defaults are restored when leaving the folder or stopping.
Saving never writes global VLC options or toolbar/application profile IDs.

Windows save/switch/restoration, real restart persistence and removal tests are
**pending** for this continuation. Automatic per-show font/effect/appearance
profiles, inheritance and snapshots of arbitrary VLC options remain unimplemented.
Named application-default profiles remain a separate explicit action.
