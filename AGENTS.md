# Official firmware boundary development

This existing checkout is authorized for focused extraction boundary work.
Preserve `reference/pr-59`; development uses `development/companion-boundary`.
Use exactly Zig 0.17.0 (`~/.zvm/0.17.0/zig`). Read the extraction plan and tracker
in `../zigmkay_companion/docs/plans/` before changing shared contracts.

- Keep firmware free of companion imports, geometry, project schemas and UI.
- First-party implementation, build logic and tests use Zig. Preserve existing
  imported C/dependency code without expanding it without user permission.
- The coordinator owns Git, dependency manifests, build glue, shared checks and
  regeneration. Assign workers disjoint files and frozen contracts.
- Make focused local commits. No pushes or PRs are authorized; upstream push
  URL must remain disabled. Do not create more clones or worktrees.
- Default builds and tests must not access devices or flash firmware. A hardware
  task requires a separate explicit user request.
- Pin external inputs immutably. Record offline checks and unresolved native or
  device acceptance separately. Keep generated outputs in caches and all code,
  comments, diagnostics and commit messages in English.
