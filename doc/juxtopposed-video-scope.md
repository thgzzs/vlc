# Juxtopposed video reference and implementation gaps

Reference: https://www.youtube.com/watch?v=ERFeOgqk324
Author: Juxtopposed. Community design link from the creator's description:
https://www.figma.com/community/file/1691465999134370980

The user supplied the 21-minute 640x360 video on 2026-10-14. Review used 63 frames sampled across the full video, 18 additional timestamped frames, and the full transcript. This is a visual design reference, not a working VLC binary. Stock VLC screens shown as criticism are not target layouts. No video, soundtrack or extracted imagery is added to the executable or redistributed in this repository.

## Target inventory

| Video section | Target behavior and visual structure | Current native port |
| --- | --- | --- |
| 00:35–01:31 | Orange/neutral palette, consistent two-tone menu icons and monochrome actionable icons, softened rectangular geometry | Partial tokens and four playback SVGs; complete icon system pending |
| 01:35–04:02 | Compact single-row player, playback cluster at left, actions at right, substantial seek hit area, cone volume, seek thumbnail preview; title and controls revealed near fullscreen edges | Partial player/seek layout; cone volume, thumbnail previews and exact fullscreen reveal behavior pending |
| 04:06–05:29 | Direct subtitle/audio access, track tabs, streamlined media menu and context menu, hide-interface action | Existing controller-backed track popup retained and styled; target menu composition pending |
| 05:39–08:42 | Add subtitles for file/folder/playlist; local or online selection, saved matching, cue timeline, delay/rate/duration controls, precise/relative fonts, saved presets and preferred track/language | Real subtitle delay slider and FPS refresh correction; bulk matching, cue timeline, full formatting/preset UI pending |
| 07:07–09:18 | Docked right sidebar with Playback, Video, Audio and Subtitles tabs; filters, equalizer, output devices, transform/crop/aspect/HDR controls and presets | Floating track popup and existing effects dialogs remain; full docked four-tab composition pending |
| 09:22–12:22 | Folder-linked compact library beside video; active folder in header, breadcrumbs, list/grid/details, search/sort/watched filters; music folders and songs/albums/artists/genres, cover art and optional waveform | Navigation/card/mini-player styling and left queue exist; left queue is not the compact library browser; exact folder/header/music/waveform layouts pending |
| 11:35–13:56 | Library and queue stay accessible during playback, drag media into queue, saved playlists separated from active queue; pinned folders/playlists, recent and Home | Existing VLC models/controllers retained; complete redesigned composition and interactions pending |
| 12:22–13:33 | Separate streamlined open/network/capture/convert/stream dialogs; network URL can become a named saved playlist; simple playlist creation | Existing native dialogs styled; target restructuring pending |
| 14:52–15:29 | Bookmarks/chapters in sidebar, quick creation and a usable timeline; shortcut feedback includes pressed key | Existing VLC facilities retained; redesigned presentation pending |
| 15:35–18:54 | Settings grouped under App/Media/System: General, Interface, Privacy, Controls, Playback, Video, Audio, Subtitles, Library, Network, Performance, Recording, Extensions. Basic and advanced fields in the same category, descriptive controls and help | Native preferences styling/navigation foundation only; complete category/field restructuring pending |
| 18:54–19:36 | Customize the actual player through draggable controls and placeholders, add/remove elements, alternative layouts and broader saved profiles | Existing VLC toolbar editor and added Juxtopposed toolbar profile; target editor and complete profile behavior pending |
| 19:46–20:06 | First-launch theme/accent selection followed by a keyboard-shortcut introduction | Not implemented |
| 20:06–20:43 | Final integrated player/library/settings/customization montage and light/dark/system appearances | No complete visual or functional sign-off |

## Implementation rules

Use real VLC models and controllers. A themed existing screen is not equivalent to the demonstrated new composition. A toolbar profile is not equivalent to saving all settings per profile. A play queue is not equivalent to a folder-aware compact library.

Timeline extraction, waveform/thumbnail generation, bulk subtitle associations and cross-setting presets require backend work and persistence, not placeholder controls. Implement and test them explicitly. Validate native Windows playback and screen rendering before marking a row complete.

The earlier Windows package compiled source 10e67ea and is a partial checkpoint. Plugin relink correction 959bbd7 is still unverified; successful compilation alone is not full redesign completion. Original editable Figma data/assets and licensing remain useful for exact fidelity, but the supplied video now provides a concrete visual/interaction reference for these screens.
