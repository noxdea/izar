---
layout: guide
title: Ruby API
description: Inspect repository changes and choose individual hunks from Ruby.
---

## Inspect a repository

Require Izar and pass the directory of an existing repository. With no argument,
`Izar::Repository.new` uses the current working directory.

```ruby
require "izar"

repository = Izar::Repository.new("/path/to/project")
puts repository.branch

repository.grouped.each do |group, changes|
  changes.each { |change| puts "#{group}: #{change.code} #{change.path}" }
end
```

Each change exposes `path`, the two-character status `code`, `index`, and
`worktree`, plus `staged?`, `unstaged?`, and `untracked?` predicates. A partially
staged path appears in both the staged and unstaged groups.

## Stage a file and commit

Pass paths relative to the repository root:

```ruby
repository.stage("README.md")
commit_oid = repository.commit("Update project notes")
puts commit_oid
```

`repository.unstage("README.md")` removes its changes from the next commit while
preserving working-tree edits. `repository.stage_all` stages all repository
changes. Commit requires a non-empty message, staged changes, and a configured
author and committer identity.

## Compare and stage hunks

The API exposes both diff directions. Use `staged_to_worktree` for unstaged
changes and `head_to_staged` for changes already in the index:

```ruby
diff = repository.diff("README.md", context: 3)

unstaged_hunks = diff.staged_to_worktree
puts "#{unstaged_hunks.length} unstaged hunks"
diff.stage_hunk(unstaged_hunks.first) unless unstaged_hunks.empty?

staged_hunks = diff.head_to_staged
puts "#{staged_hunks.length} staged hunks"
```

To select another hunk, choose that element from the returned array. Pass a hunk
from `head_to_staged` to `diff.unstage_hunk(hunk)` to reverse it in the index.
Recompute the diff after each change so subsequent hunks describe the current
index content. Unlike the workspace, the API accepts `context: 0` directly.

## Handle errors and discard confirmation

Repository failures raise `Izar::Error`. Discard needs an explicit confirmation
argument and follows the same destructive behavior as the
[CLI and TUI](usage.md#discard-a-file):

```ruby
begin
  repository.discard("README.md", confirm: true)
rescue Izar::Error => error
  warn error.message
end
```

Call this only after your application has obtained confirmation. Tracked files
return to HEAD in both the working tree and index; files absent from HEAD are
removed. Izar's temporary stash is restored before discard and is not a retained
recovery copy.
