<h1 align="center">Izar</h1>

<p align="center">
  <strong>Pure Ruby Git staging workspace for safe status, diff, and staging operations.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/izar"><img src="https://img.shields.io/gem/v/izar?style=flat-square" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/izar"><img src="https://img.shields.io/gem/dt/izar?style=flat-square" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/izar/actions/workflows/main.yml"><img src="https://github.com/noxdea/izar/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.2-CC342D?style=flat-square" alt="Ruby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#interactive-mode">Interactive mode</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#ruby-api">Ruby API</a>
</p>

---

Izar is a pure Ruby Git staging workspace for safe status, diff, and staging
operations. It builds on [Thuban](https://github.com/noxdea/thuban) and
[Porrima](https://github.com/noxdea/porrima) without invoking the `git`
executable.

## Features

- **Clear status groups** — staged, unstaged, and untracked files stay separate.
- **File and hunk staging** — stage or unstage a whole path or the selected hunk.
- **Safe destructive actions** — discard requires explicit confirmation.
- **Interactive workspace** — terminal and native GUI views share the same model.
- **Fast filtering** — narrow large change sets while reviewing.
- **Readable diffs** — syntax highlighting with bounded, virtualized rendering.
- **Small Ruby API** — inspect and update a repository without shelling out.

## Installation

```bash
gem install izar
```

Izar requires Ruby 3.2 or newer.

## Quick start

Run Izar inside a Git repository:

```bash
izar status
izar stage lib/example.rb
izar unstage lib/example.rb
izar commit -m "Describe the change"
```

Discard is intentionally gated:

```bash
izar discard tmp.txt --yes
```

Use `-C` to target another repository and `--filter` to narrow status output:

```bash
izar status -C ../project --filter README
```

## Interactive mode

Launch the terminal workspace or native GUI:

```bash
izar status --tui
izar status --gui
```

| Key | Action |
|---|---|
| `j` / `k` | Move between files |
| `space` | Toggle the selected file |
| `a` | Stage all changes |
| `s` | Toggle the selected hunk |
| `c` | Commit staged changes |
| `X` | Confirm and discard the selected file |
| `/` | Filter paths |
| `r` | Reload |
| `?` | Show help |
| `q` | Quit |

## Configuration

Create `.izar.jsonc` in the repository root:

```jsonc
{
  "theme": "dark",
  "split_ratio": 0.35,
  "keymap": {
    "stage": "space",
    "commit": "c"
  },
  "diff": {
    "context": 3,
    "highlight": true
  }
}
```

Unknown keys and invalid values fail before input is dispatched.

## Ruby API

```ruby
require "izar"

repository = Izar::Repository.new
repository.status
repository.diff("README.md").staged_to_worktree
repository.stage("README.md")
```

## Development

```bash
bundle install
bundle exec rake
bundle exec rbs -I sig validate
gem build --strict izar.gemspec
```

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/noxdea/izar).

## License

Izar is available under the [MIT License](LICENSE.txt).
