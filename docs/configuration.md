---
layout: guide
title: Configuration
description: Set Izar's appearance, stage binding, and diff settings with .izar.jsonc.
---

## Create a configuration file

Create `.izar.jsonc` in the directory from which you launch Izar. When you use
`-C`, place it in that directory instead. Launching from the repository root is
the easiest way to use one project configuration consistently; Izar does not
search parent directories for this file.

This example contains every setting and its default:

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

JSONC allows comments. Omitted settings keep their defaults, including omitted
fields inside `keymap` and `diff`. Configuration is read on launch; quit and
reopen the workspace after editing it. `r` reloads repository status only.

## Settings reference

| Setting | Accepted value | Effect |
| --- | --- | --- |
| `theme` | String; built-ins `dark`, `light`, `high_contrast` | Native window colors |
| `split_ratio` | Finite number from `0` through `1` | Native sidebar's share of the split pane; default `0.35` |
| `keymap.stage` | Non-empty string | Key binding for toggling the selected file; default `space` |
| `keymap.commit` | Non-empty string | Commit action binding; default `c` |
| `diff.context` | Non-negative integer | Context lines around changes in the displayed diff; default `3` |
| `diff.highlight` | `true` or `false` | Syntax highlighting in the native diff view |

Theme, split ratio, and syntax highlighting do not change the printed terminal
view. `diff.context: 0` is accepted, but the workspace currently uses three
context lines for that value. Hunk staging uses three context lines regardless
of this display setting.

Unknown keys at any of these levels, invalid types, and out-of-range values are
rejected before workspace input begins. Theme names are resolved when the native
view opens; an unknown name prevents that view from opening.

## Keyboard bindings

To use `t` for staging while keeping the commit-message prompt:

```jsonc
{
  "keymap": {
    "stage": "t",
    "commit": "c"
  }
}
```

Use a single character in the terminal workspace, or `space` for Space. Avoid
keys already used by [other workspace actions](usage.md#keyboard-shortcuts).
Only `stage` and `commit` can be configured; movement, hunk staging, filtering,
reload, discard, help, and quit have fixed bindings.

The commit action accepts a custom binding, but the terminal only opens its
message prompt for literal `c`. A different commit key cannot collect a message
in the current TUI. The native window has no commit-message input either, so use
the default terminal binding or `izar commit -m "Your message"`.

## Custom themes

If the optional [Auva](https://github.com/noxdea/auva) gem is installed, `theme`
can also name an Auva JSONC token file:

```jsonc
{
  "theme": "/absolute/path/to/theme.jsonc"
}
```

Use an absolute path to avoid ambiguity: a relative theme path is resolved from
the process's working directory, including when `-C` selects another repository.
Without Auva, use the built-in `dark`, `light`, or `high_contrast` themes.
