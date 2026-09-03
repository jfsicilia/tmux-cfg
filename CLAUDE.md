# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Tmux dotfiles managed via GNU Stow. The stow package root is `tmux/`, so stowing from the parent dotfiles directory symlinks `.config/tmux/` into the user's home.

The live config is at `~/.config/tmux/tmux.conf` — edits to either location affect the same file.

## Key Configuration Decisions

- **Prefix**: `Alt+b` (not the default `Ctrl+b`)
- **Terminal**: foot (Wayland), with `tmux-256color` inside tmux and RGB/undercurl overrides for foot
- **Theme**: catppuccin mocha, loaded via `run` (not TPM) — catppuccin options must appear **before** the `run` line
- **Window display**: Uses `#W` (window name) not `#T` (pane title) in catppuccin — `allow-rename off` and `automatic-rename off` prevent the shell from overriding manual window names
- **Pane navigation**: vim-tmux-navigator pattern using `Alt+h/j/k/l` with vim-aware `if-shell` detection — these same keys work in copy-mode-vi
- **Indexing**: Windows and panes start at 1, with `renumber-windows on`
- **Status bar**: Single line at top. Left = green session pill `[#S]` (`@catppuccin_status_session` module in `status-left`, set **after** `run` since the module string doesn't exist until then) followed by the window pills; right = a **hand-written** sapphire clock pill in `status-right` (`` cap + clock icon + `%H:%M · %Y-%m-%d` + `` cap, all on `#74c7ec`) — hand-written because the catppuccin module has no per-module separators and the session pill wants a different cap. Session `[#S]` text + its **hardcoded mocha** green/crust colors (`@catppuccin_status_session_text_bg` / `_text_fg`; `#{E:@thm_green}` would resolve empty here, before the theme loads) are set **before** `run`. `@catppuccin_status_connect_separator no` keeps caps/trailing-space on the bar bg, not filled with the pill color. `status-left` has a trailing space to gap the session pill from the first window pill
- **Command prompt**: `message-line 0` — a `:` prompt / message takes over the whole status line. `message-style` / `message-command-style` are re-asserted **after** `run`: `align=left` (catppuccin sets `align=centre`, which offsets the prompt) and `fill=<colour>` — without `fill`, tmux 3.7 only paints the prompt's own width and the window pills / session / clock stay visible behind it

## Plugins

Plugins live in `plugins/` and are loaded directly (no plugin manager like TPM):

- **catppuccin/tmux** — Theme. Configured via `@catppuccin_*` options set before `run catppuccin.tmux`

## When Editing

- Catppuccin `@catppuccin_*` options must be set **before** `run ~/.config/tmux/plugins/catppuccin/tmux/catppuccin.tmux`
- The vim-tmux-navigator block (lines ~52-68) has version-conditional bindings for `C-\` — preserve both the `< 3.0` and `>= 3.0` branches
- Reload config with: `tmux source-file ~/.config/tmux/tmux.conf`
