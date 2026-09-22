@AGENTS.md

<!--
Deliberately a two-line import, not a copy and not a symlink.

Claude Code reads AGENTS.md natively, but only from v2.1.277 and not on Bedrock or
third-party providers, with telemetry disabled, or on the first session after an upgrade.
This import covers those cases. It never causes double-loading: Claude Code skips an
AGENTS.md it has already read.

A symlink here would break instead — Edit and Write refuse to write through one, and a
Windows clone with core.symlinks=false turns it into a nine-byte text file containing the
literal string "AGENTS.md", with a clean git status to hide it.

Put Claude-specific instructions below this line if you ever need them. Everything that
applies to all agents belongs in AGENTS.md.
-->
