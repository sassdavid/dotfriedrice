#!/bin/bash
# Claude Code statusline - multi-line with ANSI colors and progress bar
input=$(cat)

# Single jq call to extract all fields at once
eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name)",
  @sh "CURRENT_DIR=\(.workspace.current_dir)",
  @sh "SESSION_ID=\(.session_id // "default")",
  @sh "COST_TOTAL=\(.cost.total_cost_usd // 0)",
  @sh "DURATION_MS=\(.cost.total_duration_ms // 0)",
  @sh "API_DURATION_MS=\(.cost.total_api_duration_ms // 0)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0)",
  @sh "CONTEXT_SIZE=\(.context_window.context_window_size // 0)",
  @sh "USED_PCT=\(.context_window.used_percentage // 0)",
  @sh "EFFORT_LEVEL=\(.effort.level // "")",
  @sh "RATE_5H_PCT=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "RATE_5H_RESET=\(.rate_limits.five_hour.resets_at // "")",
  @sh "RATE_7D_PCT=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "RATE_7D_RESET=\(.rate_limits.seven_day.resets_at // "")",
  @sh "EXCEEDS_200K=\(.exceeds_200k_tokens // false)",
  @sh "SESSION_NAME=\(.session_name // "")",
  @sh "PR_NUMBER=\(.pr.number // "")",
  @sh "PR_URL=\(.pr.url // "")",
  @sh "PR_STATE=\(.pr.review_state // "")",
  @sh "COST_NONZERO=\(if (.cost.total_cost_usd // 0) > 0 then 1 else 0 end)"
')"

# ANSI colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

# --- Git info with cache (refreshes every 5s, scoped per session) ---

CACHE_FILE="/tmp/statusline-git-cache-$SESSION_ID"
CACHE_MAX_AGE=5

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] ||
    # stat -f %m is macOS, stat -c %Y is Linux
    [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0))) -gt "$CACHE_MAX_AGE" ]
}

if cache_is_stale; then
  if git -C "$CURRENT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null)
    STAGED=$(git -C "$CURRENT_DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$CURRENT_DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    echo "$BRANCH|$STAGED|$MODIFIED" >"$CACHE_FILE"
  else
    echo "||" >"$CACHE_FILE"
  fi
fi

IFS='|' read -r BRANCH STAGED MODIFIED <"$CACHE_FILE"

GIT_INFO=""
if [ -n "$BRANCH" ]; then
  GIT_INFO=" | ${DIM}${BRANCH}${RESET}"
  [ "$STAGED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${GREEN}+${STAGED}${RESET}"
  [ "$MODIFIED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${YELLOW}~${MODIFIED}${RESET}"
fi

# --- Line 1: model [· effort], session name, directory, git, PR ---

MODEL_DISPLAY="${CYAN}[${MODEL}"
[ -n "$EFFORT_LEVEL" ] && MODEL_DISPLAY="${MODEL_DISPLAY} · ${EFFORT_LEVEL}"
MODEL_DISPLAY="${MODEL_DISPLAY}]${RESET}"

# Custom session name (set via --name or /rename); absent otherwise
SESSION_LABEL=""
[ -n "$SESSION_NAME" ] && SESSION_LABEL=" ${DIM}‹${SESSION_NAME}›${RESET}"

# PR badge: Claude Code populates .pr via the gh CLI, so this lights up on
# GitHub repos only. On Bitbucket the field is absent and nothing is shown.
PR_INFO=""
if [ -n "$PR_NUMBER" ]; then
  case "$PR_STATE" in
  approved)
    PR_COLOR="$GREEN"
    PR_ICON="✓"
    ;;
  changes_requested)
    PR_COLOR="$RED"
    PR_ICON="✗"
    ;;
  draft)
    PR_COLOR="$DIM"
    PR_ICON="◐"
    ;;
  *)
    PR_COLOR="$YELLOW"
    PR_ICON="•"
    ;;
  esac
  if [ -n "$PR_URL" ]; then
    # OSC 8 clickable link (Cmd/Ctrl+click) wrapping the PR number
    printf -v PR_LINK '\033]8;;%s\aPR#%s\033]8;;\a' "$PR_URL" "$PR_NUMBER"
  else
    PR_LINK="PR#${PR_NUMBER}"
  fi
  PR_INFO=" ${DIM}|${RESET} ${PR_COLOR}${PR_LINK} ${PR_ICON}${RESET}"
fi

echo -e "${MODEL_DISPLAY}${SESSION_LABEL} ${CURRENT_DIR##*/}${GIT_INFO}${PR_INFO}"

# --- Line 2: context progress bar, cost, duration, api duration, code changes ---

# Truncate to integer
PCT=${USED_PCT%.*}
: "${PCT:=0}"

# Color-coded progress bar: green <70%, yellow 70-89%, red 90%+
if [ "$PCT" -ge 90 ]; then
  BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then
  BAR_COLOR="$YELLOW"
else
  BAR_COLOR="$GREEN"
fi

BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100))
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
for ((i = 0; i < FILLED; i++)); do BAR="${BAR}█"; done
for ((i = 0; i < EMPTY; i++)); do BAR="${BAR}░"; done

if [ "$CONTEXT_SIZE" -ge 900000 ]; then
  CTX_LABEL="1m"
else
  CTX_LABEL="200k"
fi

LINE2="${BAR_COLOR}${BAR}${RESET} ${PCT}% ${DIM}${CTX_LABEL}${RESET}"
[ "$EXCEEDS_200K" = "true" ] && LINE2="${LINE2} ${RED}>200k${RESET}"

# Cost (only if > 0; comparison done in the jq pass to avoid a bc dependency)
if [ "$COST_NONZERO" = "1" ]; then
  COST_FMT=$(printf '$%.4f' "$COST_TOTAL")
  LINE2="${LINE2} ${DIM}|${RESET} ${YELLOW}${COST_FMT}${RESET}"
fi

# Wall-clock duration with API time alongside (only if > 0)
if [ "$DURATION_MS" -gt 0 ]; then
  MINS=$((DURATION_MS / 60000))
  SECS=$(((DURATION_MS % 60000) / 1000))
  LINE2="${LINE2} ${DIM}|${RESET} ${MINS}m${SECS}s"
  if [ "$API_DURATION_MS" -gt 0 ]; then
    API_MINS=$((API_DURATION_MS / 60000))
    API_SECS=$(((API_DURATION_MS % 60000) / 1000))
    LINE2="${LINE2} ${DIM}(api ${API_MINS}m${API_SECS}s)${RESET}"
  fi
fi

# Code changes (only if any)
if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
  LINE2="${LINE2} ${DIM}|${RESET} ${GREEN}+${LINES_ADDED}${RESET}/${RED}-${LINES_REMOVED}${RESET}"
fi

echo -e "$LINE2"

# --- Line 3: rate limits (Claude.ai subscription only; absent on Bedrock/Vertex) ---

if [ -n "$RATE_5H_PCT" ] || [ -n "$RATE_7D_PCT" ]; then
  LINE3=""

  if [ -n "$RATE_5H_PCT" ]; then
    PCT_5H=$(printf '%.0f' "$RATE_5H_PCT")
    if [ "$PCT_5H" -ge 90 ]; then
      COLOR_5H="$RED"
    elif [ "$PCT_5H" -ge 70 ]; then
      COLOR_5H="$YELLOW"
    else
      COLOR_5H="$GREEN"
    fi
    # stat -r is macOS, date -d @ is Linux
    RESET_5H=$(date -r "$RATE_5H_RESET" "+%H:%M" 2>/dev/null || date -d "@$RATE_5H_RESET" "+%H:%M" 2>/dev/null)
    PART_5H="${COLOR_5H}5h ${PCT_5H}%${RESET}"
    [ -n "$RESET_5H" ] && PART_5H="${PART_5H} ${DIM}→ ${RESET_5H}${RESET}"
    LINE3="$PART_5H"
  fi

  if [ -n "$RATE_7D_PCT" ]; then
    PCT_7D=$(printf '%.0f' "$RATE_7D_PCT")
    if [ "$PCT_7D" -ge 90 ]; then
      COLOR_7D="$RED"
    elif [ "$PCT_7D" -ge 70 ]; then
      COLOR_7D="$YELLOW"
    else
      COLOR_7D="$GREEN"
    fi
    RESET_7D=$(date -r "$RATE_7D_RESET" "+%a %H:%M" 2>/dev/null || date -d "@$RATE_7D_RESET" "+%a %H:%M" 2>/dev/null)
    PART_7D="${COLOR_7D}7d ${PCT_7D}%${RESET}"
    [ -n "$RESET_7D" ] && PART_7D="${PART_7D} ${DIM}→ ${RESET_7D}${RESET}"
    [ -n "$LINE3" ] && LINE3="${LINE3} ${DIM}|${RESET} ${PART_7D}" || LINE3="$PART_7D"
  fi

  echo -e "$LINE3"
fi
