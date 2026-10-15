# Windows CI blocker — confirmed 2026-10-15 UTC

The public GitHub Actions page for this fork reports that workflows are not
currently being run because of the scale of GitHub Actions usage, and that a
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

## Recovery and actual compiler results

Maintainer browser access was restored on 2026-10-15 UTC. The workflow was
observed enabled, and a source push started real Actions runs. Push and PR events
share a branch concurrency group so only the latest duplicate builds.

- https://github.com/thgzzs/vlc/actions/runs/38661285852 — failed C++ compilation:
  an unintended currentTime guard in MLBookmarkModel::clear(). Corrected in
  a13a10a0b00cbb45bc9a178986caab6158b78cd3.
- https://github.com/thgzzs/vlc/actions/runs/38662133653 — failed C++ compilation:
  missing notification signal declarations in SubtitleTimeline. The declarations
  are now added for the next native compilation.

These are failed build records, not completed runtime tests. Packaging and
Windows functional/visual validation are still required.
