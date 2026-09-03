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
- **Status bar**: Single line at top. Window pills on the left (`status-left ""`); green session pill `[#S]` + clock + date on the right, built from catppuccin's `@catppuccin_status_session` / `@catppuccin_status_date_time` module strings (referenced in `status-right` **after** the `run` line, since the modules don't exist until then)
- **Command prompt**: `message-line 0` — a `:` prompt / message takes over the whole status line (full-width bar, text from the left). `message-style` / `message-command-style` are re-asserted **after** `run` with `align=left` because catppuccin sets them `align=centre`, which otherwise centers the prompt

## Plugins

Plugins live in `plugins/` and are loaded directly (no plugin manager like TPM):

- **catppuccin/tmux** — Theme. Configured via `@catppuccin_*` options set before `run catppuccin.tmux`

## When Editing

- Catppuccin `@catppuccin_*` options must be set **before** `run ~/.config/tmux/plugins/catppuccin/tmux/catppuccin.tmux`
- The vim-tmux-navigator block (lines ~52-68) has version-conditional bindings for `C-\` — preserve both the `< 3.0` and `>= 3.0` branches
- Reload config with: `tmux source-file ~/.config/tmux/tmux.conf`
