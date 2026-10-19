
# Commit Guide

Make each commit a small, complete change with one clear purpose. Before committing,
review the working tree with `git status` and inspect the staged patch with
`git diff --staged`. Stage only files that belong to the change; never include
generated output, credentials, local `.env` files, debug statements, or unrelated
formatting changes.

Use the following instruction when asking a contributor or an AI to write a message:

```gitcommit
Write a commit message for this change using the Commitizen convention.
Keep the title under 50 characters, wrap every message line at 72 characters,
and return only a gitcommit code block.
```

Use a subject shaped as `type(scope): concise outcome`; common types include `feat`,
`fix`, `docs`, `refactor`, `test`, and `chore`. For example:
`feat(pagination): deterministic listing order`. Add a blank line and a compact body
when context is useful. Summarize important areas such as SQL, API, fixtures, and
tests, plus behavioral reasons, invariants, or migration steps.

Run relevant formatting and tests before committing. For Rust changes, this normally
includes `cargo fmt --check` and a focused `cargo test`. If verification cannot run,
state why in the message body or pull request. Confirm contents with
`git show --stat` before sharing the commit.
