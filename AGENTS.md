# Aggregate project instructions

## Project knowledge

Before project tasks, use $project-knowledge at /Users/guo/.codex/skills/project-knowledge/SKILL.md. Retrieve relevant notes from /Users/guo/Projects/Codex, searching this project first, then other projects, then the web. Check prior notes against current source and dependencies. Archive task outcomes using the skill's daily-note and index rules.

## Product scope

The current release targets macOS only. Keep shared Flutter/Dart contracts and widgets independent of macOS APIs so later platforms can reuse them. See docs/architecture.md and docs/ui-design.md.

## Commit and push workflow

After each completed and verified project task, create a local Git commit and push it to the current branch's configured upstream without asking for a file-list review. Commit only task-related source, tests, documentation, and required test baselines; exclude generated artifacts and secrets. Use a concise Chinese commit message. Push normally without force; if the branch has no upstream or the push is rejected, keep the local commit and report the blocker.
