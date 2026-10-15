# Windows CI status — 2026-10-15 UTC

Windows CI is running. The repository restriction described below is historical.

## Actual build and runtime evidence

- https://github.com/thgzzs/vlc/actions/runs/38663707984 — integrated native
  redesign d072b5087a5e7dda07a20b864a6d50611b5c6082: C++ compilation,
  four-plugin GCC runtime relink verification, stripping/packaging and packaged
  engine startup/clean exit passed with Qt 6.8.3 and the MinGW POSIX toolchain.
- The Windows PE audit checked 417 images with no unresolved DLL imports.
- GUI audio decoding and native pause passed. Pointer seeking failed before
  further GUI assertions. The saved screenshot shows a 1440x900 window extending
  below the runner's 1024x768 desktop, where the seek bar cannot receive a click.
- Package: https://github.com/thgzzs/vlc/actions/runs/38663707984/artifacts/11941110493
  SHA256: 607494eacbfc7b741a61652616e9e2e12f897ae93fee6e1893fef8d253d19d20
- Evidence: https://github.com/thgzzs/vlc/actions/runs/38663707984/artifacts/11940713196
- https://github.com/thgzzs/vlc/actions/runs/38679122064 — rapid runtime test of
  that immutable package: failed while querying a display mode on the hosted
  runner, before launching VLC. The test now tolerates an unavailable mode
  query and fits the actual desktop.

A separate test-only workflow pins the compiled package run and names its source
commit explicitly. Its results validate that package, not later C++ changes.
The full build workflow independently compiles source changes and tests its own
package. Both kinds of results remain required; no complete runtime pass is
claimed yet.

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

## Required continuation

1. Restore maintainer authentication in the browser handoff.
2. Re-enable **Build VLC Figma Win64** on this fork.
3. Dispatch that workflow for **figma-native-complete** (not the old checkpoint).
4. Monitor actual compilation, packaging, engine smoke and native GUI jobs.
5. Inspect/fix failures and rerun until the packaged Windows application passes.

No new Windows executable, successful run or completed runtime test is claimed
for the integrated redesign. The definition of done remains compilation,
packaging and real Windows runtime validation. Remaining feature and test gaps
are listed in `juxtopposed-video-scope.md` and `native-redesign-integration.md`.
