# Juxtopposed video reference and implementation gaps

Reference: https://www.youtube.com/watch?v=ERFeOgqk324
Author: Juxtopposed. Community design link from the creator's description:
https://www.figma.com/community/file/1691465999134370980

The user supplied the 21-minute 640x360 video on 2026-10-14. Review used 63 frames sampled across the full video, 18 additional timestamped frames, and the full transcript. This is a visual design reference, not a working VLC binary. Stock VLC screens shown as criticism are not target layouts. No video, soundtrack or extracted imagery is added to the executable or redistributed in this repository.

## Target inventory

Updated for the native integration checkpoint. “Integrated” describes source implementation;
it does not imply completed Windows runtime or visual verification.

| Video section | Target behavior and visual structure | Current native port |
| --- | --- | --- |
| 00:35–01:31 | Orange/neutral palette, consistent two-tone menu icons and monochrome actionable icons, softened rectangular geometry | Native palette, Inter fonts, two-tone icon system and existing four playback SVGs integrated; Windows visual sign-off pending |
| 01:35–04:02 | Compact single-row player, playback cluster at left, actions at right, substantial seek hit area, cone volume, seek thumbnail preview; title and controls revealed near fullscreen edges | Native player row, thick seek control, cone volume and fullscreen chrome integrated; VLC-backed local seek preview and native playback/seek/fullscreen/resize tests passed on c12c0aa; clean shutdown still pending |
| 04:06–05:29 | Direct subtitle/audio access, track tabs, streamlined media menu and context menu, hide-interface action | Direct track controls, tabbed track popup, redesigned menu/context menu and hide-interface action integrated |
| 05:39–08:42 | Add subtitles for file/folder/playlist; local or online selection, saved matching, cue timeline, delay/rate/duration controls, precise/relative fonts, saved presets and preferred track/language | Native subtitle effects/defaults integrated; external SRT/WebVTT source-cue list and bounded overlay added; native SRT loading/decoded cue seeking passed; bulk matching and per-show presets pending |
| 07:07–09:18 | Docked right sidebar with Playback, Video, Audio and Subtitles tabs; filters, equalizer, output devices, transform/crop/aspect/HDR controls and presets | Four-tab docked settings sidebar integrated with real native filter/equalizer/device/transform/crop/aspect options; presets beyond existing VLC options pending |
| 09:22–12:22 | Folder-linked compact library beside video; active folder in header, breadcrumbs, list/grid/details, search/sort/watched filters; music folders and songs/albums/artists/genres, cover art and optional waveform | Compact/full library, folder breadcrumbs, grid/list/details, native search/sort and music sections integrated; waveform backend pending |
| 11:35–13:56 | Library and queue stay accessible during playback, drag media into queue, saved playlists separated from active queue; pinned folders/playlists, recent and Home | Home, recent, playlists and folder-linked browsing integrated through native media-library models; runtime persistence and large-library performance checks pending |
| 12:22–13:33 | Separate streamlined open/network/capture/convert/stream dialogs; network URL can become a named saved playlist; simple playlist creation | Redesigned native open/network/capture/stream/save-name dialogs integrated; full Windows dialog/playback checks pending |
| 14:52–15:29 | Bookmarks/chapters in sidebar, quick creation and a usable timeline; shortcut feedback includes pressed key | Native bookmarks/chapters sidebar integrated; quick Ctrl+B/add/remove share one persistent library model, guarded against media-switch races; keyboard feedback refinement pending |
| 15:35–18:54 | Settings grouped under App/Media/System: General, Interface, Privacy, Controls, Playback, Video, Audio, Subtitles, Library, Network, Performance, Recording, Extensions. Basic and advanced fields in the same category, descriptive controls and help | All 13 categories have native option mappings and exact headings verified through keyboard navigation; screenshots inspected. Full persistence/search/advanced-option coverage and concept-only backends remain pending |
| 18:54–19:36 | Customize the actual player through draggable controls and placeholders, add/remove elements, alternative layouts and broader saved profiles | Drag/drop player editor, native control placeholders and toolbar profiles integrated; named application-default profiles added; automatic per-show scoping remains pending |
| 19:46–20:06 | First-launch theme/accent selection followed by a keyboard-shortcut introduction | Theme/accent onboarding and shortcut introduction integrated; Windows first-launch verification pending |
| 20:06–20:43 | Final integrated player/library/settings/customization montage and light/dark/system appearances | Integrated source checkpoint available on figma-native-complete; complete Windows build, visual comparison and functional sign-off remain pending |

## Implementation rules

Use real VLC models and controllers. A themed existing screen is not equivalent to the demonstrated new composition. A toolbar profile is not equivalent to saving all settings per profile. A play queue is not equivalent to a folder-aware compact library.

Timeline extraction, waveform/thumbnail generation, bulk subtitle associations and cross-setting presets require backend work and persistence, not placeholder controls. Implement and test them explicitly. Validate native Windows playback and screen rendering before marking a row complete.

Windows build c12c0aa compiled and packaged with Qt 6.8.3/MinGW POSIX; the
four-plugin GCC relink audit, packaged engine smoke and 417-image import audit
passed. Native GUI shutdown still failed. Real subtitle loading/cue seeking,
metadata, statistics, theme-profile save/apply/delete and all 13 settings headings
have passed separately on that immutable package. Current application source
65a90f7 is compiling a targeted Windows TLS shutdown correction and the real
bookmark API success-return fix. No completed Windows runtime sign-off is claimed.
See `windows-ci-blocker.md` and draft PR #1 for exact run/package/evidence links.
