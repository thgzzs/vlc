# Windows CI status — 2026-10-15 UTC

Windows CI is running. The repository restriction described below is historical.

## Actual build and runtime evidence

- https://github.com/thgzzs/vlc/actions/runs/38663707984 — native source
  `d072b5087a5e7dda07a20b864a6d50611b5c6082` compiled and packaged with
  Qt 6.8.3 and the MinGW POSIX toolchain; packaged engine startup/exit passed.
- https://github.com/thgzzs/vlc/actions/runs/38680067863 — source
  `0ece54a9a53e59f7c2620ab0e8180fb316eac506` also compiled, packaged and passed
  the engine smoke test. The dependency audit found no unresolved imports among
  417 PE images. The whole workflow did not pass: native GUI shutdown failed.
- Package for that source:
  https://github.com/thgzzs/vlc/actions/runs/38680067863/artifacts/11947942228
  SHA256: `117ceb0b91176aa34604445fea3d28a7e814087996600f0a1f67a660e4776fc4`.
  This is a diagnostic build with a known shutdown hang, not a completed delivery.
- https://github.com/thgzzs/vlc/actions/runs/38680825104 — native GUI tests
  passed audio/video controls, decoded seeking, media switching, resizing,
  fullscreen and a real VLC-generated seek preview. The original offscreen
  1440x900 runner layout was corrected to fit its actual 1024x768 desktop.
- https://github.com/thgzzs/vlc/actions/runs/38682700850 — application profile
  save, switch to Light, apply saved Dark and delete passed on the compiled
  `0ece54a` package. Screenshots confirm the real theme changed.
- https://github.com/thgzzs/vlc/actions/runs/38683353969 — all 13 settings-page
  screenshots captured; missing accessible headings remain explicitly unverified.
  The newer source provides names and requires them in its Windows test.
- https://github.com/thgzzs/vlc/actions/runs/38681958022 — CDB captured the final
  thread waiting in `libqt_plugin` during `ntdll!LdrShutdownProcess`, after core
  cleanup. `HasExited` was true while `WaitForExit` remained false. Tests correctly
  require a signaled process and exit code zero. MTA and HTTP keep-alive changes
  did not solve the native teardown wait.
- https://github.com/thgzzs/vlc/actions/runs/38682700939 — C++ compilation
  passed, but an incorrect diagnostic symbol-export path blocked packaging. That
  path was corrected and diagnostic exports no longer suppress valid packaging.
- https://github.com/thgzzs/vlc/actions/runs/38684762153 — `c12c0aa` compiled,
  packaged and passed engine smoke, symbol export and the 417-image DLL audit.
  GUI shutdown still failed despite the Qt pool drain completing successfully.
  Package: https://github.com/thgzzs/vlc/actions/runs/38684762153/artifacts/11949847360
  SHA256: `48ab423b6760cd4fc4e16e338acf934b4a6f9215148d5c714af32c91cf3a7ea5`.
  This remains a diagnostic package with a known shutdown hang.
- https://github.com/thgzzs/vlc/actions/runs/38694052885 — all 13 exact settings
  headings passed using native keyboard category navigation; screenshots inspected.
- https://github.com/thgzzs/vlc/actions/runs/38694635008 — the real native subtitle
  picker, SRT parsing and decoded source-cue seeking passed.
- https://github.com/thgzzs/vlc/actions/runs/38695722580 — rendered media-source
  metadata and native decoder counters passed. Dummy output does not implement
  volume/mute, so those checks are explicitly unverified, not passed.
- Symbol resolution identifies the shutdown wait as libstdc++ condition-variable
  TLS-key deletion waiting on the static winpthreads key rwlock after other threads
  have terminated. The Qt worker-pool hypothesis was removed. The new MinGW guard
  forwards all normal deletions and skips only OS process-termination bookkeeping.
- The bookmark test created an unnamed row because the medialibrary API returned
  `VLC_EGENERIC` after successful creation. `65a90f7` returns `VLC_SUCCESS` there.
- https://github.com/thgzzs/vlc/actions/runs/38695316946 — current application
  source `65a90f7` is compiling with both corrections. Actual clean GUI shutdown,
  named bookmarks and complete package runtime acceptance remain pending.

The full workflow uses feature-branch pushes. PR opened/reopened/ready events
also build; synchronize is intentionally covered by the branch push so test-only
or documentation updates do not restart a native compile. The separate runtime
workflow pins a compiled package run and source commit explicitly. Its results
validate that package, not later C++ changes. Both native compilation and complete
packaged runtime verification remain required.

## Earlier compiler corrections

- https://github.com/thgzzs/vlc/actions/runs/38661285852 — failed C++ compilation:
  an unintended currentTime guard in MLBookmarkModel::clear(). Corrected in
  a13a10a0b00cbb45bc9a178986caab6158b78cd3.
- https://github.com/thgzzs/vlc/actions/runs/38662133653 — missing SubtitleTimeline
  notification signal declarations. Corrected in d072b50, which compiled.

# Previous Windows CI restriction — historical record

The public GitHub Actions page for this fork reports that workflows were not
being run because of the scale of GitHub Actions usage, and that a
repository maintainer can re-enable them:

https://github.com/thgzzs/vlc/actions/workflows/vlc-figma-win64.yml

This is an observed repository-level GitHub restriction, not a compiler result.
It explains why subsequent pushes and PR events have produced no new runs.
The earlier API-only inspection could list runs but could not expose workflow
state. No billing/quota diagnosis beyond GitHub's displayed notice is assumed.

A separate trigger defect was corrected in commit
fa0686f5f3e70943303d158fd743d0b1955a5e5a: the push branch filter now includes
`figma-native-complete` as well as `figma-redesign`. PR builds still target
`figma-redesign` inside this fork. This does not bypass disabled workflows.

The connected GitHub tools do not expose workflow enable/dispatch operations.
Changing the disabled workflow state requires authenticated maintainer access.

## Historical continuation steps (completed to restore CI)

1. Restore maintainer authentication in the browser handoff.
2. Re-enable **Build VLC Figma Win64** on this fork.
3. Dispatch that workflow for **figma-native-complete** (not the old checkpoint).
4. Monitor actual compilation, packaging, engine smoke and native GUI jobs.
5. Inspect/fix failures and rerun until the packaged Windows application passes.

The earlier absence of Windows builds is resolved; the complete GUI runtime
pass remains outstanding. The definition of done remains compilation, packaging
and real Windows runtime validation, including clean shutdown. Remaining feature and test gaps
are listed in `juxtopposed-video-scope.md` and `native-redesign-integration.md`.
