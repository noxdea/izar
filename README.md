# Izar

Pure Ruby Git staging workspace built on Thuban and Porrima. It shows staged,
unstaged, and untracked files, computes safe hunks, and keeps destructive
discard operations behind an explicit confirmation flag.

## Installation

```sh
gem install izar
```

## Usage

Run inside a Git repository:

```sh
izar status
izar stage lib/example.rb
izar unstage lib/example.rb
izar commit -m "Describe the change"
izar discard tmp.txt --yes
```

The Ruby API is intentionally small:

```ruby
repo = Izar::Repository.new
repo.status
repo.diff("README.md").staged_to_worktree
```

Izar does not invoke the `git` executable.

## Development

Run `rake spec` and `gem build --strict izar.gemspec`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/izar.

## License

MIT.
