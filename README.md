# Pitstop

A menu bar app that shows how much AI quota you have left and when it refills,
plus a `pitstop` command that tells execute-jira whether a ticket fits before it starts.

v0.2: Claude Code and Codex, multiple accounts, reset notifications, quota check, ticket calibration.
No API keys. Starts at login by default; turn that off from the menu.

## Install
Requires macOS 14+ and [Homebrew](https://brew.sh).

```bash
brew install claide/tap/pitstop
pitstop app install
pitstop status
```
Update later with `brew update && brew upgrade pitstop && pitstop app install`.

`pitstop app install` copies the app into Applications and launches it. Run it again after
every `brew upgrade pitstop`. On the first Claude refresh, macOS asks whether `security` may
read "Claude Code-credentials", click **Always Allow**. Allow notifications when asked.

Homebrew builds Pitstop from source on your Mac (it's not signed yet), so:
- The first install takes a minute or two to compile. A warning about "tap trust" for other,
  unrelated taps is normal, ignore it.
- If it fails with "Your Command Line Tools are too outdated," run
  `sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install`, let that
  finish, then retry the two commands above.
- If Pitstop doesn't appear in your menu bar after `pitstop app install`, check
  **System Settings → Control Center** for a Pitstop entry set to hidden, and if you'd recently
  tried building it another way, restart your Mac once, then reopen it from Applications.

For local development instead of Homebrew, `./scripts/bundle.sh --install` builds from this
folder. Releasing new versions is covered in [RELEASING.md](RELEASING.md).

## The menu bar
- The number is your tightest session or weekly limit across all accounts.
- Each account shows its limits, a countdown, and the reset time.
- "Notify when limits reset" pings you when a window you'd used at least half of refills.

## The command
```bash
pitstop check --points 3 --size heavy          # 0 go/tight, 1 wait, 2 unknown, 3 split
pitstop check --need session:40,weekly:8 --json
pitstop mark start GEEK-11699 --points 3 --size heavy
pitstop mark end GEEK-11699
pitstop calibrate            # compare real costs with the table
pitstop calibrate --apply    # after 10 finished tickets
pitstop accounts
```

## Accounts
`~/Library/Application Support/Pitstop/accounts.json` (menu: Edit accounts). Defaults:

```json
[
  { "id": "claude-personal", "name": "Personal", "provider": "claude" },
  { "id": "codex-personal", "name": "Personal", "provider": "codex" }
]
```

Adding a second account later:
- **Codex:** sign in with `CODEX_HOME=~/.codex-client codex`, then add
  `{ "id": "codex-client", "name": "Client", "provider": "codex", "configDir": "~/.codex-client" }`.
- **Claude Code:** sign in with `CLAUDE_CONFIG_DIR=~/.claude-client claude`, find its Keychain entry with
  `security dump-keychain | grep -o '"Claude Code-credentials[^"]*"' | sort -u`, then add
  `{ "id": "claude-client", "name": "Client", "provider": "claude", "configDir": "~/.claude-client", "keychainService": "<that name>" }`.

Set `"enabled": false` to hide an account without deleting it.

## Files
```
Sources/PitstopCore/   shared: accounts, providers, estimator, quota check, ticket log
Sources/Pitstop/       menu bar app
Sources/PitstopCLI/    `pitstop` command
```
Data lives in `~/Library/Application Support/Pitstop/`: accounts.json, snapshot.json,
tickets.jsonl, estimate-table.json (after calibrating).

## Known limits
- Claude's usage endpoint is undocumented and may change.
- Pitstop never refreshes Claude's token (that could sign Claude Code out). If it says
  "login expired", run `claude` once.
- Codex numbers are as of your last Codex request.
- Ticket costs are before/after differences, so other work done at the same time inflates them,
  and tickets that cross a reset are skipped.