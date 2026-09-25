---
name: herdr-remote-build
description: >-
  Run and monitor a long job (build, test suite, release or upload script, anything that
  needs an unlocked login keychain) inside a persistent herdr pane on a remote Mac over SSH,
  so it survives the local terminal closing and can skip the keychain password prompt. Use
  when the user wants to build or release on a remote machine "through herdr", without
  typing a password, or wants an agent to start and watch a remote job.
---

# Remote jobs through a herdr pane

herdr (`herdr --help`) is a terminal multiplexer whose server keeps running on the remote
machine. A job started in one of its panes:

- **survives your SSH session**, so closing the local terminal does not kill it midway;
- **runs in the herdr server's session**, where the login keychain can stay unlocked, so
  codesigning or credential access needs no password per run;
- **can be read and waited on from anywhere** with `herdr pane read` / `wait-output`.

You drive the remote server from outside herdr, over SSH. Every `herdr` command below runs
**on the remote machine** (`ssh <host> 'herdr …'`). herdr's own skill says to stop when
`HERDR_ENV` is unset; that rule is about the *local* session, not a remote one you address
explicitly over SSH.

Placeholders: `<host>` is the SSH target, `<repo>` the project path on the remote,
`<label>` a name for the space, `<pane>` the pane ID you create, `<job>` the command to run.

## Hard rules

- **Never type, store or pipe the user's password.** If the keychain is locked, the job
  prompts inside the pane and the user types it there.
- **Never touch panes you did not create.** The user may have agents running in other
  panes. Create your own workspace and address it by ID; never target "the focused pane".
- **Never start a second run while one is going.** Check first (`pgrep -f <job>`).
- **Verify the outcome at its source** (the service it published to, the artifact it built),
  not from the job's last line of output.

## 1. Check the remote server

```bash
ssh <host> 'command -v herdr && herdr status && herdr workspace list'
```

`server: status: running` is required. herdr never starts a server for you over the API.
If it is not running, ask the user; a server started from an SSH login inherits that login.

## 2. Create a dedicated space (once)

```bash
ssh <host> 'herdr workspace create --cwd <repo> --label <label> --env SSH_CONNECTION= --no-focus'
```

Read `.result.workspace.workspace_id`, `.result.tab.tab_id` and
`.result.root_pane.pane_id` from the JSON; do not guess them. Optionally rename the tab
(`herdr tab rename <tab_id> <name>`). Pane IDs are stable while the tab lives and are never
reused, so record the pane ID in the project's agent docs for the next agent.

**Why `SSH_CONNECTION=`:** if the herdr server was started from an SSH login, every pane
inherits `SSH_CONNECTION`. Scripts often read that as "remote session, always unlock the
keychain", which prompts for a password every run. Clearing it lets such a script fall back
to checking whether the keychain is actually locked. Only do this if the script still
prompts when the keychain really is locked; read its check first.

## 3. Confirm the keychain is unlocked in that pane

Skip this if the job needs no keychain.

```bash
ssh <host> 'herdr pane run <pane> "clear; security show-keychain-info ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 && echo KEYCHAIN=unlocked || echo KEYCHAIN=locked"'
ssh <host> 'herdr pane wait-output <pane> --match KEYCHAIN= --timeout 10000 >/dev/null; herdr pane read <pane> --source recent --lines 3'
```

`locked` means it relocked (sleep, reboot, lock timeout). The user unlocks it once inside
that pane (`security unlock-keychain`), after which later runs reuse it.

## 4. Start the job

```bash
ssh <host> 'herdr pane run <pane> "clear; <job>"'
```

`pane run` types the command into the pane's shell and returns immediately.

## 5. Monitor it

Poll in the background rather than holding a long SSH session open:

```bash
for i in $(seq 1 90); do
  out=$(ssh -o ConnectTimeout=10 -o BatchMode=yes <host> \
    'pgrep -f "<job>" >/dev/null && echo RUNNING || echo STOPPED;
     herdr pane read <pane> --source recent-unwrapped --lines 400 | grep -E "<progress-or-error-pattern>" | tail -4')
  echo "[$(date +%H:%M)] $(echo "$out" | tr "\n" " ")"
  echo "$out" | grep -q STOPPED && break
  sleep 60
done
```

Or block on one line: `herdr pane wait-output <pane> --regex "<success>|<failure>" --timeout <ms>`.

- **If the job writes its own log file, grep that instead of the pane.** A verbose tool
  pushes progress lines out of the pane's scrollback quickly, so a pane grep goes quiet
  while the job is fine.
- **`pgrep` is the authority on whether it is still running**, not the absence of output.

When it stops, read the tail (`--lines 60`) and report the real outcome. The user can watch
live by attaching (`ssh -t <host> herdr`) and opening the space.

## Finishing a failed run by hand

If a late step fails (a network timeout, say), re-run just that step in the same pane, then
the remaining steps. **Target the exact artifact by its version or build number, never
"latest" and never an ID an earlier step printed.** Remote services often process uploads
asynchronously, so "latest" can still be the *previous* artifact, and a check against the
wrong ID will pass. Confirm the new artifact exists at the source before recording success.

## Traps

- **`--source recent-unwrapped` for grepping.** `recent` wraps long lines at the pane
  width, which splits the text you are matching.
- **zsh globs square brackets** in `pane run` text: `echo X=[$Y]` fails with
  `no matches found` and aborts the whole line. Avoid `[ ]`, or quote them.
- **Quoting is two shells deep** (local → SSH → pane). Escape `$` meant for the pane
  (`\$?`), and keep the pane command in double quotes inside single-quoted SSH.
- **External-drive reads hang with `Interrupted system call` (macOS).** If `stat` works
  but reading files blocks, and the kernel log shows
  `watchdog expired for approval entry … kTCCServiceSystemPolicyRemovableVolumes`,
  `sandboxd` is wedged. The owner runs `sudo kill -9 $(pgrep -x sandboxd)`; launchd
  restarts it. Plain `killall` may not stop it. Check with
  `log show --last 5m --predicate 'eventMessage CONTAINS "watchdog expired for approval"'`.
- **Machine profiles are optional.** `herdr --machine <label> …` forwards API calls from a
  local herdr, but plain `ssh <host> 'herdr …'` needs no saved profile.
