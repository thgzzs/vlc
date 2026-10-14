# Juxtopposed VLC redesign: native layout checkpoint

Design credit: Juxtopposed, Figma file 4ee8qiJqONgpJMPhP5DkTy. Reference prototype node 187:328.
The user supplied VLC Redesign (Community).zip on 2026-10-14. Its 25 entries are PNG exports; no SVGs, fonts, editable Figma data, or redistribution license were included. These screen images are references, not interactive UI assets or replacement media thumbnails. The original four playback SVGs from the earlier implementation remain in the native resource bundle.

## Compilation and package evidence
Commit 05418be815f972ca6178f25e0ff9015deb0a1102 compiled and packaged successfully:
https://github.com/thgzzs/vlc/actions/runs/38609164261
Initial package:
https://github.com/thgzzs/vlc/actions/runs/38609164261/artifacts/11918671677
This package predates the layout changes in this checkpoint. It is not the complete redesign.
The old --version check remains stalled; Windows winvlc can show a modal error on libvlc initialization returning null. The updated workflow instead bounds a real dummy-interface startup/quit check to 60 seconds.

## Changes in this checkpoint
- Windows dark palette, flat sidebar surfaces and selection states.
- Expanded 200-dp and collapsed 50-dp navigation; existing navigation model retained.
- 16:9 video cards, rounded corners and accent watch-progress bars; actual library thumbnails retained.
- Inline seekbar and timestamps between existing configurable player controls on wide windows without center controls.
- Narrow/custom center-control layouts continue using the existing stacked layout.
- Compact playback strip and rectangular seek handle; existing playback, seeking and volume backends retained.
- Vertical native preferences category navigation and dark form styling; existing preference pages, persistence, advanced and expert views retained.

## Reference inventory
Player.png: playback with compact navigation and playlist panel.
Player-1.png: expanded library/navigation and video cards.
Settings - global.png, Settings - audio.png: native settings visual references.
Subtitles.png: subtitle-management reference.
Property 1=expanded.png through Property 1=expanded-6.png: expanded control/menu references.
right-click menu.png: context-menu reference.
Player-2.png through Player-4.png, Frame 151 variants, Frame 159 variants, and three 24x24 icon PNGs: component/reference exports.

## Verification and remaining work
Source/resource check and git diff --check passed before committing. This checkpoint must compile and run on Windows before it is described as working.
Native GUI testing lives on figma-redesign-gui-tests and checks generated WAV decoding plus actual Qt Play/Pause accessibility actions. Results must be taken from executed CI, not inferred from the script.
Full settings category restructuring, subtitle dialogs, onboarding, menu variants, light-theme fidelity, complete original icon/font exports, visual comparisons, video/fullscreen/track tests, settings persistence tests, DPI checks, and performance validation remain pending.
Figma MCP continues to reject calls due to the Starter quota. The PNG reference workflow proceeds from the user's explicit attachment and request.
Asset redistribution permission remains unconfirmed; no public release is approved.

## Native playback and popup follow-up
A fresh Windows profile now starts dark and includes a Juxtopposed toolbar profile. Existing selected profiles remain selected; the new profile is appended if absent.
Windowed playback has compact native navigation and a left-side docked play queue. Fullscreen retains the established fullscreen behavior. Native track popups now scroll, track delay has a real controller-bound slider, and subtitle FPS refresh uses its actual notify signal and correct scale.
Native QVLC dialogs receive the dark palette and tab/input/button styling. The packaged vlc-juxtopposed.cmd launcher enables the real media library and pins controls; it invokes the actual VLC executable.

Executed GUI evidence for the initial 05418be package:
https://github.com/thgzzs/vlc/actions/runs/38636013999
Startup, local WAV decode, native Play/Pause and resume passed. The test used dummy audio output and did not validate physical audio hardware.
An audit checked 414 PE images and found libgcc_s_seh-1.dll missing for four SRT/x265/Game Music plugins. The packaging workflow now copies the matching MinGW runtime DLLs and uses upstream package-win-strip. This fix must be audited in the newly compiled package.
New source changes are not a full fidelity sign-off: remaining screen restructuring, original asset/font exports, light-mode fidelity, video/track/fullscreen validation and DPI/performance tests are still required.
