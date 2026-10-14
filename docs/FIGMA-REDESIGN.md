# Native VLC / Juxtopposed Figma redesign (Windows 11)

Visual design credit: **Juxtopposed**, [VLC Redesign (Community)](https://www.figma.com/design/4ee8qiJqONgpJMPhP5DkTy/). Original SVG vectors for four playback controls were exported from that file. Asset redistribution terms must be checked before a public release. VLC source remains subject to its existing GPL license.

This branch is an **initial native UI implementation**, not a complete redesign. The actual VLC engine and playback controllers are preserved. Windows dark mode enables the Figma player palette and SVG controls; other platform/light UI uses VLC defaults.

### Build and test

See upstream `doc/BUILD-win32.md` for the supported MinGW-w64/WSL toolchain and container. Automated cross-compilation is configured in `.github/workflows/vlc-figma-win64.yml`. A successful build is required before claiming the code compiles. The full Figma library/media/settings/onboarding implementation and Windows GUI, playback and accessibility testing remain pending.
