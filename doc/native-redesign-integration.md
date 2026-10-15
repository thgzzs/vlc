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
- These are local source/parser checks. The complete C++ integration, Windows
  executable, plugin relink fix, first launch, DPI, playback and UI performance
  require a new Windows CI run. No such run has been created for this branch yet.
- Pull-request builds target `figma-redesign` inside this fork. Main/master and
  upstream are outside this change. No merge or public release is authorized.

The build workflow also contains a Windows GUI job for this exact package. It
validates PowerShell syntax, decodes generated local audio and video fixtures,
invokes native play/pause/seek/next/previous/fullscreen controls, resizes the Qt
window, exercises the new playback toggles, audits normal/delay PE imports and
preserves screenshots/logs/results. These expanded checks are prepared, not yet
executed against this integration. Timer expiry, cue seeking, track selection,
settings persistence, hardware output, DPI and measured UI performance remain
outside that automated check's current coverage.
