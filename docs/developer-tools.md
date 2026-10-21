# Folder signals from developer tools

Wabbit picks the Project for a Watched App from its front document (Project folders), then window-title rules, then the app's default Project. In a terminal, that document is the shell's folder, which a multiplexer like herdr hides, and a Claude Code session may be working somewhere else. Folder signals tell Wabbit which folder you're working in.

## Turn it on

Watched Apps → Developer tools → **Use folder signals from developer tools (herdr, Claude Code hook)**. It's off by default.

- Signals only refine a Watched terminal in front (Terminal, iTerm, Ghostty, Warp, WezTerm, kitty, Alacritty). Other apps ignore them, and apps that aren't Watched Apps are never observed.
- For a Watched terminal in front: a fresh signal > the window's document (AXDocument) > title rules > the default Project. The newest signal wins, whatever it came from.
- A signal expires 5 minutes after it arrived unless a new one comes, so a forgotten session doesn't keep suggesting a Project.
- A signal never starts tracking. It only changes which Project the usual "Track time for <App>?" prompt offers, and only when the folder is inside a Project folder.
- Everything stays on the Mac.

## herdr

Nothing to set up. When a Watched terminal comes to the front, or its window title changes (herdr retitles it when you focus another pane), and a `herdr` process runs inside that terminal, Wabbit runs `herdr api snapshot` once and uses the focused pane's `foreground_cwd` (else `cwd`). It never polls and never changes your herdr session. The CLI is looked up in `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`; if it's missing or fails, Wabbit falls back silently.

Limits: Wabbit checks that herdr runs in the terminal, not in its front tab, so a plain tab next to a herdr tab gets herdr's folder. Only the default herdr session is read (not `herdr --session <name>`).

## Claude Code

While the setting is on, Wabbit listens on a Unix socket only you can open:

```
~/Library/Application Support/Wabbit/signal.sock
```

A client writes one line, an absolute path to an existing folder (at most 1024 bytes), then closes. Anything else is ignored. The socket is removed when you turn the setting off or quit Wabbit.

Add a `UserPromptSubmit` hook to `~/.claude/settings.json` (merge it into any `hooks` you already have):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "printf '%s\\n' \"${CLAUDE_PROJECT_DIR:-$PWD}\" | nc -U \"$HOME/Library/Application Support/Wabbit/signal.sock\" >/dev/null 2>&1; exit 0",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Each prompt you send then tells Wabbit the session's project folder. `nc` ships with macOS. When Wabbit isn't running or the setting is off, the socket isn't there and the hook does nothing (`exit 0`, so Claude Code never shows an error).

Test it by hand with the setting on:

```sh
printf '%s\n' "$PWD" | nc -U "$HOME/Library/Application Support/Wabbit/signal.sock"
```

`$CLAUDE_PROJECT_DIR` is the folder the session started in; it doesn't follow `cd` or worktrees.
