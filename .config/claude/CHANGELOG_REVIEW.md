# Claude Code changelog review

Last reviewed: **2.1.281** (released 2026-09-23), reviewed 2026-09-24.
Next review starts at the first `## ` heading above `## 2.1.281`.

Sources:

- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- https://code.claude.com/docs/en/env-vars.md, https://code.claude.com/docs/en/settings.md
- the installed binary: `strings -n 3 "$(readlink -f "$(which claude)")"`, for the
  settings key order in `claude_switch` and anything the docs leave out

## 2.1.277 to 2.1.281

Applied:

- `taskOutputMaxChars` removed from every profile and from the `claude_switch` baseline.
  It has been a no-op since 2.1.277, when the TaskOutput tool was removed; the binary
  schema describes it as "Deprecated: no longer has any effect".
- `attribution` switched to the `false` shorthand (2.1.281) in every profile. The binary
  expands it to `{commit: "", pr: "", sessionUrl: false}`. Older CLI versions skip a
  settings file that holds it, which does not matter here: every machine installs Claude
  Code through mise with `claude = "latest"`.
- The settings key order in the 2.1.281 binary is the same as in 2.1.280.

Checked and left as they are:

- `MCP_PROTOCOL_NEGOTIATION=auto` is still needed. Without it, only HTTP servers are
  probed. stdio servers (terraform, the aws-mcp proxy) are probed only with `auto`.
- Auto mode on Bedrock and Claude Platform on AWS has used the server-side classifier
  by default since 2.1.278, so it adds no classifier token cost. `CLAUDE_CODE_AUTO_MODE_SERVER`
  stays unset. `/status` shows this in its "Auto mode server" row.
- Commit 56f8396 (2026-09-23) already covers Opus 5.5 and the per-model effort change (2.1.280).
- `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH` (2.1.280, default 2048) stays unset. Measured
  on 2026-09-24: only terraform's server instructions (4295 chars) are truncated, and the
  lost half covers HCP Terraform/TFE workspace, run and variable tools, which are not
  exposed without a TFE token. The only tool description over the cap is aws-mcp
  `read_documentation` (2118 chars), which loses the end of its error-code list.
  Atlassian, Bitbucket and context7 are all under the cap. If HCP Terraform is ever
  enabled, set it to about 4500.
