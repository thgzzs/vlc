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
