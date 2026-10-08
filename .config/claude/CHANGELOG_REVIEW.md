# Claude Code changelog review

Last reviewed: **2.1.293**, reviewed 2026-10-07.
Next review starts at the first `## ` heading above `## 2.1.293`.

Sources:

- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- https://code.claude.com/docs/en/env-vars.md, https://code.claude.com/docs/en/settings.md
- https://code.claude.com/docs/en/statusline.md, for the status line input fields
- the installed binary: `strings -n 3 "$(readlink -f "$(which claude)")"`, for the
  settings key order in `claude_switch` and anything the docs leave out

## 2.1.285 to 2.1.293

Applied:

- Haiku 5.5 (2.1.293) is now the Haiku pin in every provider mode. `models.json` has a new
  rank-1 Haiku row, with Haiku 4.5 moved to rank 2. That row gives
  `global.anthropic.claude-haiku-5-5` and the Terraform profile `map-haiku-5-5`, which
  already existed. Platform mode hard-codes `claude-haiku-5-5`. Checked live on 2026-10-07:
  us-west-2 has both `global.` and `us.` system profiles. In the binary catalog it is
  `native_1m` with no `supports_1m_suffix`, so `longContext` is false. It defaults to
  `medium` effort and always uses adaptive thinking. Its Bedrock `fallback_3p` is Haiku 4.5.
  Smoke-tested in `bedrock` and `platform` modes. `bedrock-app` mode still gets the
  `application-inference-profile/*` 403 from the permission set.
- The `models.json` `longContext` comment and the `--no-long-context` help now list
  Haiku 5.5 and Fable as natively 1M. 2.1.287 moved Opus 4.7+ and Fable to a native 1M
  window on Bedrock. The catalog now marks Opus 4.7+ as `native_1m` and still marks them
  `supports_1m_suffix`, so their `[1m]` pin stays. The docs still say to add the suffix
  to enable 1M on a pinned model.
- `subagent-statusline.sh` shows the new `agentType` (2.1.293) in cyan brackets after the
  name. It skips the field when it is absent, when it is `general-purpose`, or when it
  repeats the name.
- The settings key order in the 2.1.293 binary is the same as in 2.1.280.

Checked and left as they are:

- No `modelSettings["claude-haiku-5-5"].effortLevel`. Haiku runs the Explore subagent and
  background work, where the Claude Code default of `medium` is the better trade.
  Opus 5.5 and Sonnet 5.5 stay at `high`.
- `MCP_PROTOCOL_NEGOTIATION=auto` stays. 2.1.292 made stdio servers negotiate by default
  on every provider. The mcp docs still say claude.ai connector servers are probed in
  sessions without feature flags only with `auto`, and every profile has
  `DO_NOT_TRACK=1`.
- `CLAUDE_ENABLE_BYTE_WATCHDOG_BEDROCK` and `API_FORCE_IDLE_TIMEOUT=0` are unchanged. The
  watchdog is still off by default on Bedrock. 2.1.290 fixed computer sleep being treated
  as a stalled stream on Bedrock.
- Since 2.1.288 the client-side auto mode classifier ignores a Sonnet 5.5 or Opus 5.5
  `ANTHROPIC_DEFAULT_SONNET_MODEL` pin and uses Sonnet 5 instead. This does not apply
  here, because Bedrock and Platform use the server-side classifier.
- New opt-in knobs stay unset: `CLAUDE_CODE_OVERLOADED_RETRY_BASE_DELAY_MS` (2.1.292),
  `CLAUDE_CODE_DISABLE_STRUCTURED_OUTPUTS` (2.1.288, only for `--mantle` if session titles
  fail), `CLAUDE_CODE_DISABLE_WEB_FETCH`, `CLAUDE_CODE_NONSTREAMING_TIMEOUT_RETRIES` and
  `CLAUDE_CODE_SKIP_MODEL_ACCESS_MEMORY` (2.1.285), `CLAUDE_CODE_DISABLE_AUTH_REFRESH_LOCK`
  (2.1.286) and `CLAUDE_CODE_WEB_SEARCH_REFILLS_PER_HOUR` (2.1.290).
  `modelSettings.<model>.autoCompactWindow` (2.1.288) also stays unset.
- `allowedProviders` (2.1.285) is a managed-only setting.
- You should know (2.1.287) needs first-party telemetry, so it is unavailable with
  `DO_NOT_TRACK=1`.
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` stays unset. 2.1.290 added the startup
  connection warm-up to what it skips.
- The status line needs no change. Its fields are unchanged since 2.1.284.

## 2.1.282 to 2.1.284

Applied:

- Sonnet 5.5 (2.1.284) is now the Sonnet pin in every provider mode. `models.json` has a
  new rank-1 Sonnet row, with Sonnet 5, 4.6 and 4.5 moved down one rank. That row gives
  `global.anthropic.claude-sonnet-5-5` and the Terraform profile `map-sonnet-5-5`.
  Platform mode hard-codes `claude-sonnet-5-5`. Checked live on 2026-09-29: us-west-2 has
  only the `global.` system profile for Sonnet 5.5, with no `us.` or `eu.` profile. The
  binary catalog marks it `native_1m_3p.bedrock`, so `longContext` is false and it has no
  `[1m]` suffix, the same as Sonnet 5. The docs cover native 1M for Sonnet 5 only on
  Bedrock. Smoke-tested in `bedrock` mode. In `bedrock-app` mode it gets a 403 because the
  permission set does not allow `application-inference-profile/*` yet.
- The second `fallbackModel` entry is now `claude-sonnet-5-5`. It comes from the Sonnet
  rank-1 row, or is hard-coded in platform mode.
- `modelSettings["claude-sonnet-5-5"].effortLevel = "high"` is in the baseline and in every
  profile. Claude Code defaults Sonnet 5.5 to `medium` (catalog `default_effort`), while
  the API default is `high`.
- The settings key order in the 2.1.284 binary is the same as in 2.1.280.

Checked and left as they are:

- Safety-flag fallback on Bedrock does not reach Sonnet 5 from Sonnet 5.5. The binary maps
  a Sonnet 5.5 `cyber` flag to `claude-sonnet-5`. It resolves that target through
  `ANTHROPIC_DEFAULT_SONNET_MODEL`, which is Sonnet 5.5, the model that refused, so the
  refusal stands. The Opus 5.5 pin already works this way for `cyber` (target Opus 4.8).
  Accepted: pinning the older model to keep the fallback would demote the alias.
- The status line needs no change. Every field it reads is still documented. The only new
  input is `rate_limits.spend_limit.{used_usd,limit_usd,period}` (2.1.284). It is present
  only behind a Claude apps gateway, which no profile uses. The `statusLine` options are
  unchanged: `padding`, `refreshInterval` and `hideVimModeIndicator`.
- `permissions.defaultMode: "auto"` stays explicit, although 2.1.284 now starts in auto mode
  when it is unset.
- `maxProseWidth` (2.1.282) stays unset. `availableModelsMatch` and `deniedModels`
  (2.1.283) are managed-only settings.

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
