#!/usr/bin/env bash
# Claude Code statusline. Needs bash 4+, jq, git. macOS and Linux.
# No `set -e`: a partial line beats no line.
# shellcheck disable=SC2154,SC2153  # uppercase vars come from the eval below

# printf parses floats via locale-aware strtod: a comma-decimal locale renders
# $1,0000 for 1.2345. LC_ALL outranks LC_NUMERIC.
unset LC_ALL
export LC_NUMERIC=C

input=$(cat)

# One jq call for every field; ratios computed here to avoid a bc dependency.
eval "$(jq -r '
  (.context_window.current_usage // {}) as $u |
  (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0)
     + ($u.cache_creation_input_tokens // 0)) as $prompt_tokens |
  @sh "MODEL=\(.model.display_name // "")",
  @sh "MODEL_ID=\(.model.id // "")",
  @sh "FAST_MODE=\(.fast_mode // false)",
  @sh "THINKING=\(.thinking.enabled // false)",
  @sh "CACHE_PCT=\(if $prompt_tokens > 0
                   then (($u.cache_read_input_tokens // 0) * 100 / $prompt_tokens | floor)
                   else -1 end)",
  @sh "PROMPT_TOKENS=\(if $prompt_tokens >= 1000
                       then (($prompt_tokens / 1000 | floor | tostring) + "k")
                       elif $prompt_tokens > 0 then ($prompt_tokens | tostring)
                       else "" end)",
  @sh "CURRENT_DIR=\(.workspace.current_dir // "")",
  @sh "PROJECT_DIR=\(.workspace.project_dir // "")",
  @sh "ADDED_DIRS=\(.workspace.added_dirs // [] | length)",
  @sh "OUTPUT_STYLE=\(.output_style.name // "")",
  @sh "SESSION_ID=\(.session_id // "default")",
  @sh "SESSION_NAME=\(.session_name // "")",
  @sh "VERSION=\(.version // "")",
  @sh "COST_TOTAL=\(.cost.total_cost_usd // 0)",
  @sh "COST_NONZERO=\(if (.cost.total_cost_usd // 0) > 0 then 1 else 0 end)",
  @sh "DURATION_MS=\(.cost.total_duration_ms // 0)",
  @sh "API_DURATION_MS=\(.cost.total_api_duration_ms // 0)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0)",
  @sh "CONTEXT_SIZE=\(.context_window.context_window_size // 0)",
  @sh "USED_PCT=\(.context_window.used_percentage // 0)",
  @sh "EXCEEDS_200K=\(.exceeds_200k_tokens // false)",
  @sh "EFFORT_LEVEL=\(.effort.level // "")",
  @sh "CACHE_HIT=\(if (.prompt_cache.hit_ratio // null) == null
                   then -1 else (.prompt_cache.hit_ratio * 100 | floor) end)",
  @sh "CACHE_OBSERVED=\(.prompt_cache.caching_observed // false)",
  @sh "CACHE_WARM=\(.prompt_cache.warm // false)",
  @sh "CACHE_TTL=\(.prompt_cache.ttl // "")",
  @sh "CACHE_MISSES=\(.prompt_cache.misses // 0)",
  @sh "CACHE_MISS_CAUSE=\(.prompt_cache.last_miss_cause.causes // [] | first // "")",
  @sh "RATE_5H_PCT=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "RATE_5H_RESET=\(.rate_limits.five_hour.resets_at // "")",
  @sh "RATE_7D_PCT=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "RATE_7D_RESET=\(.rate_limits.seven_day.resets_at // "")",
  @sh "RATE_SPEND_PCT=\(.rate_limits.spend_limit.used_percentage // "")",
  @sh "RATE_SPEND_RESET=\(.rate_limits.spend_limit.resets_at // "")",
  @sh "PR_NUMBER=\(.pr.number // "")",
  @sh "PR_URL=\(.pr.url // "")",
  @sh "PR_STATE=\(.pr.review_state // "")",
  @sh "PR_KIND=\(.pr.kind // "")",
  @sh "REPO_HOST=\(.workspace.repo.host // "")",
  @sh "REPO_OWNER=\(.workspace.repo.owner // "")",
  @sh "REPO_NAME=\(.workspace.repo.name // "")",
  @sh "AGENT_NAME=\(.agent.name // "")",
  @sh "WORKTREE_NAME=\(.worktree.name // "")",
  @sh "GIT_WORKTREE=\(.workspace.git_worktree // "")"
' <<<"${input}")"

CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Glyphs in one block. Nerd Font PUA by default; STATUSLINE_GLYPHS=unicode
# falls back to East Asian Width Neutral glyphs from the same font.
if [[ ${STATUSLINE_GLYPHS:-nerd} == nerd ]]; then
  # bolt, clone, robot, lightbulb, home, git-branch, pr-draft, refresh.
  G_THINK=$'\uf0e7' G_ARN=$'\uf24d' G_AGENT=$'\uebb1' G_STYLE=$'\uf0eb'
  G_PROJ=$'\uf015' G_WT=$'\uf418' G_PR_DRAFT=$'\uebaa' G_MISS=$'\ueb37'
else
  G_THINK='⚡' G_ARN='◫' G_AGENT='✶' G_STYLE='◆'
  G_PROJ='⌂' G_WT='↪' G_PR_DRAFT='◔' G_MISS='✕'
fi

# stdout is captured, so tput cannot read the width; COLUMNS is exported instead.
COLS=${COLUMNS:-80}

clip() {
  local s=$1 max=$2
  if ((max >= 4)) && ((${#s} > max)); then
    printf '%s…' "${s:0:max-1}"
  else
    printf '%s' "${s}"
  fi
}

DIRNAME=$(clip "${CURRENT_DIR##*/}" $((COLS / 3)))
SESSION_DISPLAY=$(clip "${SESSION_NAME}" $((COLS / 4)))

# --- Git info, cached for 5s per session ---

# Not /tmp: the name is predictable and /tmp is world-writable on Linux, so a
# planted symlink would redirect the write below.
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/claude-statusline"
CACHE_FILE="${CACHE_DIR}/git-${SESSION_ID}"
# Matches statusLine.refreshInterval, so a timer tick runs git at most once.
CACHE_MAX_AGE=10

[[ -d ${CACHE_DIR} ]] || { mkdir -p "${CACHE_DIR}" && chmod 700 "${CACHE_DIR}"; } 2>/dev/null

# ~/.cache survives reboots; prune once per session.
[[ -f ${CACHE_FILE} ]] ||
  find "${CACHE_DIR}" -maxdepth 1 -type f -name 'git-*' -mtime +1 -delete 2>/dev/null

# Probed once, not chained with ||: on Linux `stat -f %m FILE` prints a filesystem
# report to stdout before failing, which would land in the command substitution
# and break the arithmetic below. `date` differs the same way, so it shares the probe.
if stat -c %Y . >/dev/null 2>&1; then
  cache_mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
  fmt_reset() { date -d "@$1" "+$2" 2>/dev/null; }
else
  cache_mtime() { stat -f %m "$1" 2>/dev/null || echo 0; }
  fmt_reset() { date -r "$1" "+$2" 2>/dev/null; }
fi

cache_is_stale() {
  [[ ! -f ${CACHE_FILE} ]] || (($(date +%s) - $(cache_mtime "${CACHE_FILE}") > CACHE_MAX_AGE))
}

if cache_is_stale; then
  # `git -C ""` would silently use the process cwd.
  if [[ -d ${CURRENT_DIR} ]] && git -C "${CURRENT_DIR}" rev-parse --git-dir &>/dev/null; then
    BRANCH=$(git -C "${CURRENT_DIR}" branch --show-current 2>/dev/null)
    # Empty on a detached HEAD, which would hide the git segment.
    if [[ -z ${BRANCH} ]]; then
      BRANCH=$(git -C "${CURRENT_DIR}" rev-parse --short HEAD 2>/dev/null)
      [[ -n ${BRANCH} ]] && BRANCH="@${BRANCH}"
    fi
    STAGED=$(git -C "${CURRENT_DIR}" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "${CURRENT_DIR}" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    printf '%s|%s|%s\n' "${BRANCH}" "${STAGED}" "${MODIFIED}" >"${CACHE_FILE}"
  else
    echo "||" >"${CACHE_FILE}"
  fi
fi

IFS='|' read -r BRANCH STAGED MODIFIED <"${CACHE_FILE}"

GIT_INFO=""
if [[ -n ${BRANCH} ]]; then
  REPO_LABEL=${BRANCH}
  if [[ -n ${REPO_OWNER} && -n ${REPO_NAME} ]]; then
    REPO_LABEL="${REPO_OWNER}/${REPO_NAME}:${BRANCH}"
    # Host only when not GitHub, so self-hosted remotes stay distinguishable.
    [[ -n ${REPO_HOST} && ${REPO_HOST} != "github.com" ]] && REPO_LABEL="${REPO_HOST}/${REPO_LABEL}"
  fi
  GIT_INFO=" | ${DIM}${REPO_LABEL}${RESET}"
  ((STAGED > 0)) && GIT_INFO+=" ${GREEN}+${STAGED}${RESET}"
  ((MODIFIED > 0)) && GIT_INFO+=" ${YELLOW}~${MODIFIED}${RESET}"
fi

# --- Line 1: model, session, agent, dir, git, worktree, PR ---

MODEL_DISPLAY="${CYAN}[${MODEL}"
[[ -n ${EFFORT_LEVEL} ]] && MODEL_DISPLAY+=" · ${EFFORT_LEVEL}"
[[ ${THINKING} == true ]] && MODEL_DISPLAY+=" · ${G_THINK}thk"
[[ ${FAST_MODE} == true ]] && MODEL_DISPLAY+=" · fast"
MODEL_DISPLAY+="]${RESET}"

# Confirms the session bills through a MAP-attributed profile (bedrock-app mode).
if [[ ${MODEL_ID} == *application-inference-profile/* ]]; then
  PROFILE_ID=${MODEL_ID##*/}
  MODEL_DISPLAY+=" ${DIM}${G_ARN}${PROFILE_ID%\[1m\]}${RESET}"
fi

SESSION_LABEL=""
[[ -n ${SESSION_DISPLAY} ]] && SESSION_LABEL=" ${DIM}‹${SESSION_DISPLAY}›${RESET}"

AGENT_INFO=""
[[ -n ${AGENT_NAME} ]] && AGENT_INFO=" ${DIM}${G_AGENT}${AGENT_NAME}${RESET}"

STYLE_INFO=""
[[ -n ${OUTPUT_STYLE} && ${OUTPUT_STYLE} != "default" ]] &&
  STYLE_INFO=" ${DIM}${G_STYLE}${OUTPUT_STYLE}${RESET}"

DIRS_INFO=""
((ADDED_DIRS > 0)) && DIRS_INFO=" ${DIM}+${ADDED_DIRS}d${RESET}"

# Set only after /cd moved the session out of its original directory.
PROJECT_INFO=""
[[ -n ${PROJECT_DIR} && ${PROJECT_DIR} != "${CURRENT_DIR}" ]] &&
  PROJECT_INFO=" ${DIM}${G_PROJ}${PROJECT_DIR##*/}${RESET}"

# .worktree.name is --worktree only; .workspace.git_worktree covers any worktree.
WORKTREE_LABEL=${WORKTREE_NAME:-${GIT_WORKTREE}}
WORKTREE_INFO=""
[[ -n ${WORKTREE_LABEL} ]] && WORKTREE_INFO=" ${DIM}${G_WT}${WORKTREE_LABEL}${RESET}"

# .pr.kind is "mr" for GitLab. Absent on Bitbucket.
PR_INFO=""
if [[ -n ${PR_NUMBER} ]]; then
  [[ ${PR_KIND} == mr ]] && PR_ABBR=MR || PR_ABBR=PR
  case ${PR_STATE} in
  approved) PR_COLOR=${GREEN} PR_ICON="✓" ;;
  changes_requested) PR_COLOR=${RED} PR_ICON="✗" ;;
  draft) PR_COLOR=${DIM} PR_ICON="${G_PR_DRAFT}" ;;
  *) PR_COLOR=${YELLOW} PR_ICON="•" ;;
  esac
  if [[ -n ${PR_URL} ]]; then
    printf -v PR_LINK '\033]8;;%s\a%s#%s\033]8;;\a' "${PR_URL}" "${PR_ABBR}" "${PR_NUMBER}"
  else
    PR_LINK="${PR_ABBR}#${PR_NUMBER}"
  fi
  PR_INFO=" ${DIM}|${RESET} ${PR_COLOR}${PR_LINK} ${PR_ICON}${RESET}"
fi

printf '%s\n' "${MODEL_DISPLAY}${SESSION_LABEL}${AGENT_INFO}${STYLE_INFO} ${DIRNAME}${PROJECT_INFO}${DIRS_INFO}${GIT_INFO}${WORKTREE_INFO}${PR_INFO}"

# --- Line 2: context bar, cache ratio, cost, duration, code changes ---

PCT=${USED_PCT%.*}
: "${PCT:=0}"

if ((PCT >= 90)); then
  BAR_COLOR=${RED}
elif ((PCT >= 70)); then
  BAR_COLOR=${YELLOW}
else
  BAR_COLOR=${GREEN}
fi

BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
printf -v FILL '%*s' "${FILLED}" ''
printf -v REST '%*s' "$((BAR_WIDTH - FILLED))" ''
BAR="${FILL// /█}${REST// /░}"

((CONTEXT_SIZE >= 900000)) && CTX_LABEL=1m || CTX_LABEL=200k

LINE2="${BAR_COLOR}${BAR}${RESET} ${PCT}% ${DIM}${CTX_LABEL}${RESET}"
# Re-sent each turn, so this is the cost driver.
[[ -n ${PROMPT_TOKENS} ]] && LINE2+=" ${DIM}·${PROMPT_TOKENS}${RESET}"

# Red at 200K means compaction is imminent; on 1M it is informational.
if [[ ${EXCEEDS_200K} == true ]]; then
  ((CONTEXT_SIZE < 900000)) && LINE2+=" ${RED}>200k${RESET}" || LINE2+=" ${YELLOW}>200k${RESET}"
fi

# .prompt_cache is the session-wide view (2.1.251+; miss causes 2.1.260+).
# CACHE_PCT, the last request's read ratio, stands in until the first response
# fills it and on providers that report no cache tokens.
CACHE_SHOWN=${CACHE_HIT}
if [[ ${CACHE_OBSERVED} == true ]] && ((CACHE_HIT >= 0)); then
  CACHE_TEXT="cache ${CACHE_HIT}%"
  # The TTL the provider actually granted; on Bedrock 1h is per-model.
  [[ -n ${CACHE_TTL} ]] && CACHE_TEXT+="·${CACHE_TTL}"
  [[ ${CACHE_WARM} != true ]] && CACHE_TEXT+=" cold"
  if ((CACHE_MISSES > 0)); then
    CACHE_TEXT+=" ${G_MISS}${CACHE_MISSES}"
    [[ -n ${CACHE_MISS_CAUSE} ]] && ((COLS >= 110)) && CACHE_TEXT+=" ${CACHE_MISS_CAUSE}"
  fi
else
  CACHE_TEXT="cache ${CACHE_PCT}%"
  CACHE_SHOWN=${CACHE_PCT}
fi

if ((CACHE_SHOWN >= 0)); then
  if [[ ${CACHE_OBSERVED} == true && ${CACHE_WARM} != true ]]; then
    CACHE_COLOR=${RED}
  elif ((CACHE_SHOWN >= 70)); then
    CACHE_COLOR=${GREEN}
  elif ((CACHE_SHOWN >= 30)); then
    CACHE_COLOR=${YELLOW}
  else
    CACHE_COLOR=${DIM}
  fi
  LINE2+=" ${DIM}|${RESET} ${CACHE_COLOR}${CACHE_TEXT}${RESET}"
fi

if [[ ${COST_NONZERO} == 1 ]]; then
  printf -v COST_FMT '$%.4f' "${COST_TOTAL}"
  LINE2+=" ${DIM}|${RESET} ${YELLOW}${COST_FMT}${RESET}"
fi

if ((DURATION_MS > 0)); then
  LINE2+=" ${DIM}|${RESET} $((DURATION_MS / 60000))m$((DURATION_MS % 60000 / 1000))s"
  ((API_DURATION_MS > 0)) &&
    LINE2+=" ${DIM}(api $((API_DURATION_MS / 60000))m$((API_DURATION_MS % 60000 / 1000))s)${RESET}"
fi

if ((LINES_ADDED > 0 || LINES_REMOVED > 0)); then
  LINE2+=" ${DIM}|${RESET} ${GREEN}+${LINES_ADDED}${RESET}/${RED}-${LINES_REMOVED}${RESET}"
fi

[[ -n ${VERSION} ]] && LINE2+=" ${DIM}| v${VERSION}${RESET}"

printf '%s\n' "${LINE2}"

# --- Line 3: rate limits (subscription windows, or a gateway spend limit) ---

if [[ -n ${RATE_5H_PCT} || -n ${RATE_7D_PCT} || -n ${RATE_SPEND_PCT} ]]; then
  # fmt_reset() comes from the platform probe above.
  rate_part() {
    local label=$1 pct=$2 epoch=$3 fmt=$4 color reset
    printf -v pct '%.0f' "${pct}"
    if ((pct >= 90)); then
      color=${RED}
    elif ((pct >= 70)); then
      color=${YELLOW}
    else
      color=${GREEN}
    fi
    printf '%s' "${color}${label} ${pct}%${RESET}"
    reset=$(fmt_reset "${epoch}" "${fmt}")
    [[ -n ${reset} ]] && printf '%s' " ${DIM}→ ${reset}${RESET}"
  }

  rate_append() {
    local part=$1
    [[ -z ${part} ]] && return 0
    [[ -n ${LINE3} ]] && LINE3+=" ${DIM}|${RESET} ${part}" || LINE3=${part}
  }

  LINE3=""
  [[ -n ${RATE_5H_PCT} ]] &&
    rate_append "$(rate_part 5h "${RATE_5H_PCT}" "${RATE_5H_RESET}" '%H:%M')"
  [[ -n ${RATE_7D_PCT} ]] &&
    rate_append "$(rate_part 7d "${RATE_7D_PCT}" "${RATE_7D_RESET}" '%a %H:%M')"
  # Console accounts and apps-gateway sessions get this window instead.
  [[ -n ${RATE_SPEND_PCT} ]] &&
    rate_append "$(rate_part '$' "${RATE_SPEND_PCT}" "${RATE_SPEND_RESET}" '%b %d')"

  printf '%s\n' "${LINE3}"
fi
