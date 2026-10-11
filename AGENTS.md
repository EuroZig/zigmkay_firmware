# EuroZig firmware boundary development

This user-authorized clone of EuroZig/zigmkay_firmware is the active firmware
repository. Development uses `development/companion-boundary`; `main` retains
the cloned baseline. The old upstream checkout and its `reference/pr-59` are
historical evidence only.
Use exactly Zig 0.17.0 (`~/.zvm/0.17.0/zig`). Read the extraction plan and tracker
in `../zigmkay_companion/docs/plans/` before changing shared contracts.

- Keep firmware free of companion imports, geometry, project schemas and UI.
- First-party implementation, build logic and tests use Zig. Preserve existing
  imported C/dependency code without expanding it without user permission.
- The coordinator owns Git, dependency manifests, build glue, shared checks and
  regeneration. Assign workers disjoint files and frozen contracts.
- Make focused local commits. EuroZig origin is the future push/PR destination;
  a concrete publication request is still required before pushing or creating
  a PR. Do not add an official upstream remote or create more clones/worktrees.
- Default builds and tests must not access devices or flash firmware. A hardware
  task requires a separate explicit user request.
- Pin external inputs immutably. Record offline checks and unresolved native or
  device acceptance separately. Keep generated outputs in caches and all code,
  comments, diagnostics and commit messages in English.
