---
name: herdr-remote-build
description: >-
  Run and monitor a long remote build, test or release script (TestFlight, App Store,
  codesigned archive, any job that needs an unlocked login keychain) inside a persistent
  herdr pane on a remote Mac over SSH, so it survives the local terminal closing and skips
  the keychain password prompt. Use when the user wants to ship or build on a remote Mac
  "through herdr", without typing a password, or wants an agent to start and watch a
  remote build.
---

# Remote builds through a herdr pane

herdr (`herdr --help`) is a terminal multiplexer for coding agents whose server keeps
running on the remote Mac. A job started in one of its panes:

- **survives your SSH session**, so closing the local terminal no longer kills a half-done
  upload (it did, before this skill existed);
- **runs in the herdr server's security session**, where the login keychain can stay
  unlocked, so codesigning needs no password per run;
- **can be read and waited on from anywhere** with `herdr pane read` / `wait-output`.

You drive the remote server from outside herdr, over SSH. Every `herdr` command below runs
**on the remote Mac** (`ssh <host> 'herdr …'`). herdr's own skill says to stop when
`HERDR_ENV` is unset; that rule is about the *local* session, not a remote one you address
explicitly over SSH.

## Hard rules

- **Never type, store or pipe the user's password.** If the keychain is locked, the job
  prompts inside the pane; the user types it there, or uses their normal SSH ship command.
- **Never touch panes you did not create.** The user may have agents running in other
  panes. Create your own workspace/tab and address it by ID; never target "the focused pane".
- **Never start a second run while one is going.** Check first (`pgrep -f <script>`).
- **Verify the outcome at its source** (App Store Connect, the artifact), not from the
  script's last line.

## 1. Check the remote server

```bash
ssh <host> 'command -v herdr && herdr status && herdr workspace list'
```

`server: status: running` is required. herdr never starts a server for you over the API.
If it is not running, ask the user; starting one from an SSH login ties it to that login.

## 2. Create a dedicated space (once)

```bash
ssh <host> 'herdr workspace create --cwd ~/path/to/repo --label <project> \
  --env SSH_CONNECTION= --no-focus'
```

Read `.result.workspace.workspace_id`, `.result.tab.tab_id` and
`.result.root_pane.pane_id` from the JSON; do not guess them. Rename the tab
(`herdr tab rename <tab_id> ship`). Pane IDs are stable while the tab lives and are never
reused, so record the pane ID in the project's agent docs.

**Why `SSH_CONNECTION=`:** if the herdr server was started from an SSH login, every pane
inherits `SSH_CONNECTION`, and release scripts commonly treat that as "always unlock the
keychain, prompt for the password". Clearing it lets such a script take its
"already unlocked" path. Only do this if the script's own check is sound (it should still
prompt when the keychain really is locked).

## 3. Confirm the keychain is unlocked in that pane

```bash
ssh <host> 'herdr pane run <pane> "clear; security show-keychain-info ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 && echo KEYCHAIN=unlocked || echo KEYCHAIN=locked"'
sleep 2
ssh <host> 'herdr pane read <pane> --source recent --lines 3'
```

`locked` means it relocked (sleep, reboot, `lock-on-sleep`). The user unlocks it once
inside that pane (`security unlock-keychain`), after which it stays unlocked for later runs.

## 4. Start the job

```bash
ssh <host> 'herdr pane run <pane> "clear; ./scripts/<release-script>.sh"'
```

`pane run` types the command into the pane's shell and returns immediately.

## 5. Monitor it

Poll in the background rather than holding a long SSH session open:

```bash
for i in $(seq 1 90); do
  out=$(ssh -o ConnectTimeout=10 -o BatchMode=yes <host> \
    'pgrep -f <release-script>.sh >/dev/null && echo RUNNING || echo STOPPED;
     herdr pane read <pane> --source recent-unwrapped --lines 400 | grep -E "^==>|ERROR|error:" | tail -4')
  echo "[$(date +%H:%M)] $(echo "$out" | tr "\n" " ")"
  echo "$out" | grep -q STOPPED && break
  sleep 60
done
```

Match on the script's step markers and its final success line. **If the script writes its
own log file, grep that instead of the pane:** a verbose `xcodebuild` pushes the step
markers out of the pane's scrollback within minutes, so the pane grep goes quiet while the
job is fine. `pgrep` stays the authority on whether it is still running. Or block on one line:
`herdr pane wait-output <pane> --regex "Done:|ERROR" --timeout 3600000`.

When it stops, read the tail (`--lines 60`) and report the real outcome. The user can
watch live by attaching (`ssh -t <host> herdr`) and opening the space.

## Traps

- **`--source recent-unwrapped` for grepping.** `recent` wraps long lines at the pane
  width, which splits the text you are matching.
- **zsh globs square brackets** in `pane run` text: `echo X=[$Y]` fails with
  `no matches found` and aborts the whole line. Avoid `[ ]`, or quote them.
- **Quoting is two shells deep** (local → SSH → pane). Escape `$` meant for the pane
  (`\$?`), and keep the pane command in double quotes inside single-quoted SSH.
- **A stuck file-permission service stalls everything.** If reads of an external drive
  hang with `Interrupted system call` and the kernel log shows
  `watchdog expired for approval entry … kTCCServiceSystemPolicyRemovableVolumes`,
  `sandboxd` is wedged. The owner runs `sudo kill -9 $(pgrep -x sandboxd)`; launchd
  restarts it. (Plain `killall` may not stop it.)
- **Machine profiles are optional.** `herdr --machine <label> …` forwards API calls from a
  local herdr, but plain `ssh <host> 'herdr …'` needs no saved profile.
