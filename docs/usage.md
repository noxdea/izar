---
layout: guide
title: Reviewing and staging changes
description: Use commands and the interactive workspace to stage files, handle hunks, and commit changes.
---

## Choose a workspace

| Command | Behavior |
| --- | --- |
| `izar` or `izar status` | Print the status groups and a diff, then exit |
| `izar status --tui` | Open the interactive terminal workspace |
| `izar status --gui` | Open a native window when terminal input and output are available |
| `izar status -C ../project` | Inspect another repository |
| `izar status --filter README` | Narrow the visible paths |

If native startup fails, `--gui` reports the problem and attempts the terminal
workspace. Interactive TUI input also needs terminal output; redirected input or
output produces a status snapshot instead.

## Review files in the terminal

1. Run `izar status --tui` from your repository root.
2. Move with `j` and `k` to select a changed path.
3. Read the diff below the status groups. `+` marks inserted lines and `-` marks
   deleted lines.
4. Press `/`, type a path query, and press Enter to narrow the groups. Submit an
   empty query to show all paths again.
5. Press `r` after changing files in your editor to reload their status.

Path filtering uses Spica's fuzzy matching when Spica is available, with plain
substring matching as a fallback. It filters paths, rather than diff contents.
The printed terminal diff contains at most 500 lines.

## Stage or unstage a file

Press Space on a changed path to stage its current working-tree content. For a
deleted tracked file, this stages the deletion. If the file is fully staged with
no additional working-tree edits, Space unstages it instead.

A partially staged file can appear in both Staged and Unstaged. Space stages its
remaining edits regardless of which entry you reached. Use the explicit
`unstage` command if you want to remove its staged changes while keeping the file
content:

```sh
izar stage lib/example.rb
izar unstage lib/example.rb
```

Press `a` to stage all changes in the repository, including untracked files and
deletions. This acts on the whole repository even when a path filter is active.

## Stage one hunk at a time

Press `s` on the selected path to stage its first available unstaged hunk. A hunk
is a block of nearby changed lines and their surrounding context. Press `s`
again to process the next remaining hunk after the workspace reloads.

For a fully staged file without further edits, `s` unstages its first staged
hunk. For a partially staged file, it stages the next unstaged hunk. There is no
separate hunk cursor or control for choosing an arbitrary hunk in the workspace.
Use [the Ruby API](repository-api.md#compare-and-stage-hunks) to select a specific
hunk.

Both terminal and native diff views show index-to-working-tree changes. They
can be empty for a fully staged file even though `s` can unstage its first hunk.

## Commit staged changes

In the terminal workspace, press `c`, enter a message, and press Enter. Izar
commits all staged changes, including files hidden by your current filter.
An empty message or an empty index produces an error.

For the same operation from a command prompt:

```sh
izar commit -m "Add installation instructions"
```

Commit identity comes from your Git configuration or Git author and committer
environment variables. See [getting started](index.md#troubleshooting) if an
identity is missing.

## Discard a file

In the terminal workspace, select the path, press uppercase `X`, and respond to
`discard PATH? [y/N]`. Only `y` or `Y` confirms the action; another response cancels
it. From the command line, explicit confirmation is also required:

```sh
izar discard README.md --yes
```

Discard restores a tracked file to its last committed content and resets its
index entry. It removes an untracked or newly added file that has no version in
HEAD. This discards both staged and unstaged changes for that path. The temporary
stash mentioned in the result is restored before discard; it is not a retained
backup of the discarded file.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `j` / `k` | Select the next / previous path |
| Space | Stage the selected file, or unstage it when fully staged |
| `a` | Stage all repository changes |
| `s` | Stage or unstage the first applicable hunk |
| `c` | Enter a message and commit staged changes in the TUI |
| `X` | Confirm and discard the selected path in the TUI |
| `/` | Enter a path filter in the TUI |
| `r` | Reload status |
| `?` | Show a short help message |
| `q` | Quit |

You can change the stage and commit bindings in
[configuration](configuration.md#keyboard-bindings). Keep the default `c` when
you need the terminal's commit-message prompt.

## Use the native window

Click a path in the sidebar to select it, or move with `j` and `k`. Space, `a`,
`s`, `r`, `?`, and `q` share the terminal workspace's actions. The native view
highlights syntax and renders up to 50,000 diff lines.

The native window has no commit-message or discard-confirmation dialog, and
ignores the default `c` and `X` keys. Use the TUI or CLI for those operations. It
also has no filter-text entry; set an initial filter with
`izar status --gui --filter README`. Pressing `/` in the window clears the filter.

Choose appearance and diff settings in [configuration](configuration.md).
