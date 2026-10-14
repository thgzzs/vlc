@echo off
rem Native VLC development launcher: enables library and pinned playback controls.
setlocal
"%~dp0vlc.exe" --media-library --qt-pin-controls %*
