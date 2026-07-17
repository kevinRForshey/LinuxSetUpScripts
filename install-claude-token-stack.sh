#!/bin/bash
# install-claude-token-stack.sh
#
# Builds a Claude Code token-optimization stack (CachyOS / Arch, but works
# on any distro with bash + jq + python3):
#
#   - Headroom (+ bundled RTK): API-layer compression, wrapped around `claude`
#   - codebase-memory-mcp (CBM): knowledge-graph code discovery, replaces
#     grep/read sweeps
#   - context-mode + caveman: Claude Code plugins for output sandboxing and
#     terser responses
#   - enforcement hooks: block raw cat/head/tail/find/grep/rg in Bash, and
#     nudge the first Grep/Glob/Read/Search of a session toward CBM
#   - settings.json / CLAUDE.md: merged in place, never overwritten wholesale
#
# Error handling: every step that can fail for a reason that ISN'T "the
# script itself is broken" (network hiccup, missing AUR helper, plugin
# already installed, corrupt existing settings.json, no write permission on
# one file) is explicitly caught, logged as a warning, and the script keeps
# going. Only missing core tools (git/curl/jq/python3) are treated as fatal,
# because nothing past that point can work without them. `set -e` stays on
# as a backstop for genuinely unexpected failures, not as the primary error
# handling mechanism — see the guarded blocks below for why.
#
# Idempotent: safe to re-run. Existing settings.json / CLAUDE.md content is
# preserved; only the keys this script owns are added or updated, and a
# timestamped .bak is written whenever a file actually changes.
#
# Review this script before running it — it installs a third-party binary
# (CBM) and two third-party Claude Code plugins (context-mode, caveman) via
# their own install paths. Sources are printed at the end.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
WARNINGS=()

log()  { printf '\n==> %s\n' "$1"; }
ok()   { printf '  + %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1" >&2; WARNINGS+=("$1"); }

# ── 0. Preflight — the only fatal-if-missing tools ───────────────────────
log "Checking required tools"
missing=()
for cmd in git curl jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing (fatal, can't proceed): ${missing[*]}" >&2
  echo "CachyOS/Arch: sudo pacman -S ${missing[*]}" >&2
  exit 1
fi
ok "git, curl, jq, python3 present"

if command -v claude >/dev/null 2>&1; then
  ok "Claude Code CLI found: $(command -v claude)"
  HAVE_CLAUDE_CLI=1
else
  warn "'claude' CLI not found — plugin installs (context-mode, caveman) will be skipped."
  HAVE_CLAUDE_CLI=0
fi

mkdir -p "$HOOKS_DIR"

# ── 1. Headroom (+ bundled RTK) ───────────────────────────────────────────
log "Checking Headroom"
if command -v headroom >/dev/null 2>&1; then
  ok "Headroom already installed: $(command -v headroom)"
else
  warn "Headroom not found — installing"
  PIP_CMD=""
  if command -v pip3 >/dev/null 2>&1; then PIP_CMD="pip3"
  elif command -v pip  >/dev/null 2>&1; then PIP_CMD="pip"
  fi
  if [ -n "$PIP_CMD" ]; then
    if "$PIP_CMD" install --user "headroom-ai[all]" > /tmp/headroom-install.log 2>&1; then
      ok "Headroom installed"
    else
      warn "Headroom install failed (see /tmp/headroom-install.log) — continuing without it. Retry manually: $PIP_CMD install --user 'headroom-ai[all]'"
    fi
  else
    warn "No pip/pip3 found — install Python's pip, then: pip install --user 'headroom-ai[all]'. Continuing without Headroom."
  fi
fi
export PATH="$HOME/.local/bin:$PATH"

if command -v rtk >/dev/null 2>&1; then
  ok "RTK found: $(command -v rtk)"
else
  warn "RTK not found on PATH. It ships bundled inside Headroom, so this is likely fine — not installed separately."
fi

# Wire the shell wrapper so `claude` actually routes through Headroom.
# Only touches the rc file for your current $SHELL; idempotent (checks for
# the marker string first); silently no-ops (with a warning) on shells it
# doesn't recognize rather than guessing wrong.
log "Checking Headroom shell wrapper"
USER_SHELL="$(basename "${SHELL:-/bin/bash}")"
case "$USER_SHELL" in
  fish) RC="$HOME/.config/fish/config.fish" ;;
  zsh)  RC="$HOME/.zshrc" ;;
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="" ;;
esac
if [ -n "$RC" ]; then
  mkdir -p "$(dirname "$RC")" 2>/dev/null || warn "Could not create $(dirname "$RC")"
  touch "$RC" 2>/dev/null || warn "Could not create/touch $RC"
  if [ -f "$RC" ] && grep -q 'headroom wrap claude' "$RC" 2>/dev/null; then
    ok "Headroom wrapper already present in $RC"
  else
    if [ "$USER_SHELL" = "fish" ]; then
      { printf '\n# Headroom wraps Claude Code for API-layer token compression\n'
        printf 'function claude\n    command headroom wrap claude $argv\nend\n'
      } >> "$RC" 2>/dev/null && ok "Added Headroom wrapper to $RC (restart shell to apply)" \
        || warn "Could not write wrapper to $RC — add manually: function claude; command headroom wrap claude \$argv; end"
    else
      { printf '\n# Headroom wraps Claude Code for API-layer token compression\n'
        printf 'claude() { command headroom wrap claude "$@"; }\n'
      } >> "$RC" 2>/dev/null && ok "Added Headroom wrapper to $RC (restart shell to apply)" \
        || warn "Could not write wrapper to $RC — add manually: claude() { command headroom wrap claude \"\$@\"; }"
    fi
  fi
else
  warn "Unrecognized shell '$USER_SHELL' — add manually: claude() { command headroom wrap claude \"\$@\"; }"
fi

# ── 2. codebase-memory-mcp (CBM) ─────────────────────────────────────────
log "Installing codebase-memory-mcp"
CBM_OK=0
if command -v codebase-memory-mcp >/dev/null 2>&1; then
  ok "codebase-memory-mcp already installed: $(command -v codebase-memory-mcp)"
  CBM_OK=1
elif command -v paru >/dev/null 2>&1; then
  if paru -S --noconfirm codebase-memory-mcp-bin; then
    ok "installed via paru (AUR)"
    CBM_OK=1
  else
    warn "paru install of codebase-memory-mcp-bin failed — trying upstream installer next"
  fi
fi

if [ "$CBM_OK" -eq 0 ] && command -v yay >/dev/null 2>&1; then
  if yay -S --noconfirm codebase-memory-mcp-bin; then
    ok "installed via yay (AUR)"
    CBM_OK=1
  else
    warn "yay install of codebase-memory-mcp-bin failed — trying upstream installer next"
  fi
fi

if [ "$CBM_OK" -eq 0 ]; then
  warn "No AUR helper succeeded — falling back to upstream install script (SLSA3 provenance + VirusTotal-scanned releases, but still: inspect /tmp/cbm-install.sh before trusting it)."
  if curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh -o /tmp/cbm-install.sh; then
    if bash /tmp/cbm-install.sh; then
      ok "codebase-memory-mcp installed"
      CBM_OK=1
    else
      warn "CBM upstream installer failed — skipping CBM. The enforcement hooks below will still install; they just won't have anything to gate toward until you install CBM manually: https://github.com/DeusData/codebase-memory-mcp"
    fi
    rm -f /tmp/cbm-install.sh
  else
    warn "Could not download CBM installer (network issue?) — skipping CBM. Run manually later: curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash"
  fi
fi
export PATH="$HOME/.local/bin:$PATH"

# CBM's own installer wires a *non-blocking* Claude Code hook named
# cbm-code-discovery-gate. We deliberately overwrite it in step 4 with a
# stricter, blocking version — CBM install happens first, our hooks second,
# so ours is what's left on disk.

# ── 3. Claude Code plugins: context-mode + caveman ───────────────────────
log "Installing context-mode + caveman plugins"
if [ "$HAVE_CLAUDE_CLI" -eq 1 ]; then
  claude plugin marketplace add mksglu/context-mode 2>/dev/null \
    || warn "context-mode marketplace add failed or already added"
  claude plugin install context-mode@context-mode 2>/dev/null \
    || warn "context-mode install failed or already installed"
  claude plugin marketplace add JuliusBrussee/caveman 2>/dev/null \
    || warn "caveman marketplace add failed or already added"
  claude plugin install caveman@caveman 2>/dev/null \
    || warn "caveman install failed or already installed"
  ok "plugin install commands run (see warnings above for anything skipped)"
else
  warn "Skipped plugin install — no 'claude' CLI on PATH"
fi

# ── 4. Enforcement hooks ──────────────────────────────────────────────────
# Each write is guarded individually (not as one block) so a failure on file
# 2 of 4 doesn't erase whether file 1 succeeded, and doesn't abort the script.
log "Writing enforcement hooks to $HOOKS_DIR"
HOOKS_OK=1

cat > "$HOOKS_DIR/bash-ban-raw-tools" <<'HOOKEOF' || HOOKS_OK=0
#!/bin/bash
# PreToolUse Bash gate: block cat/head/tail/find/grep/rg/wc invocations.
# CLAUDE.md bans these in favour of Read/Grep/Glob/rtk. RTK wrappers pass.
# Escape hatch: touch /tmp/bash-raw-unlock-$PPID.
set -uo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
[ "$TOOL" = "Bash" ] || exit 0

UNLOCK=/tmp/bash-raw-unlock
check_unlock() {
  local f=$1
  [ -f "$f" ] || return 1
  local mtime
  mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  local age=$(( $(date +%s) - mtime ))
  if [ "$age" -ge 0 ] && [ "$age" -lt 600 ]; then return 0; fi
  rm -f "$f"; return 1
}
check_unlock "$UNLOCK" && exit 0
check_unlock "/tmp/bash-raw-unlock-$PPID" && exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
TRIMMED=$(echo "$CMD" | sed -E 's/^[[:space:]]*//')
FIRST=$(echo "$TRIMMED" | awk '{print $1}')

banned=0
case "$FIRST" in
  cat|head|tail|find|grep|rg|wc) banned=1 ;;
  rtk) exit 0 ;;
esac

if echo "$CMD" | grep -qE '\|\s*(tail|head)\b' && echo "$FIRST" | grep -qE '^(cat|grep|rg|find)$'; then
  echo "BLOCKED: '| tail'/'| head' pipeline truncates but doesn't reduce tokens read. Use context-mode's ctx_batch_execute/ctx_execute instead, or drop the pipe for short (<20 line) output. Override: touch $UNLOCK" >&2
  exit 2
fi

[ "$banned" -eq 0 ] && exit 0

case "$FIRST" in
  cat|head|tail) echo "BLOCKED Bash '$FIRST'. Use the Read tool. Override: touch $UNLOCK." >&2 ;;
  find)          echo "BLOCKED Bash 'find'. Use the Glob tool. Override: touch $UNLOCK." >&2 ;;
  grep|rg)       echo "BLOCKED Bash '$FIRST'. Use the Grep tool. Override: touch $UNLOCK." >&2 ;;
  wc)            echo "BLOCKED Bash 'wc'. Read the file or pipe via rtk. Override: touch $UNLOCK." >&2 ;;
esac
exit 2
HOOKEOF

cat > "$HOOKS_DIR/cbm-code-discovery-gate" <<'HOOKEOF' || HOOKS_OK=0
#!/bin/bash
# Blocks the FIRST Grep/Glob/Read/Search per session, nudging toward CBM.
# Every call after that (or after any CBM tool runs) passes through.
GATE=/tmp/cbm-code-discovery-gate-$PPID
MARKER=/tmp/cbm-mcp-used-$PPID
if [ -f "$MARKER" ] || [ -f "$GATE" ]; then
    exit 0
fi
touch "$GATE"
echo 'BLOCKED: For code discovery, use codebase-memory-mcp tools first: search_graph(name_pattern) to find functions/classes, trace_path() for call chains, get_code_snippet(qualified_name) to read source. If unindexed, call index_repository first. Fall back to Grep/Glob/Read only for text content search. Retry now.' >&2
exit 2
HOOKEOF

cat > "$HOOKS_DIR/cbm-mcp-marker" <<'HOOKEOF' || HOOKS_OK=0
#!/bin/bash
# PostToolUse: touch the marker whenever a codebase-memory-mcp tool runs.
# Paired with cbm-code-discovery-gate, which checks the marker's freshness.
set -euo pipefail
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL" == mcp__codebase-memory-mcp__* ]]; then
  touch /tmp/cbm-mcp-used-$PPID
fi
exit 0
HOOKEOF

cat > "$HOOKS_DIR/cbm-session-reminder" <<'HOOKEOF' || HOOKS_OK=0
#!/bin/bash
# SessionStart hook: remind the agent to use codebase-memory-mcp tools.
cat << 'REMINDER'
CRITICAL - Code Discovery Protocol:
1. ALWAYS use codebase-memory-mcp tools FIRST for ANY code exploration:
   - search_graph(name_pattern/label) to find functions/classes/routes
   - trace_path(function_name, mode) for call chains
   - get_code_snippet(qualified_name) to read source (NOT Read/cat)
   - get_architecture(aspects) for project structure
2. Fall back to Grep/Glob/Read ONLY for text content, config, non-code files.
3. If the project is not indexed yet, run index_repository FIRST.
REMINDER
HOOKEOF

chmod +x "$HOOKS_DIR"/bash-ban-raw-tools "$HOOKS_DIR"/cbm-code-discovery-gate \
         "$HOOKS_DIR"/cbm-mcp-marker "$HOOKS_DIR"/cbm-session-reminder 2>/dev/null || HOOKS_OK=0

if [ "$HOOKS_OK" -eq 1 ]; then
  ok "4 hook scripts written and made executable"
else
  warn "One or more hook scripts failed to write or chmod (permissions on $HOOKS_DIR?) — enforcement may be incomplete. Check: ls -la $HOOKS_DIR"
fi

# ── 5. Statusline (only if none already customized) ──────────────────────
log "Installing statusline"
STATUSLINE="$CLAUDE_DIR/statusline-command.sh"
if [ -f "$STATUSLINE" ]; then
  ok "statusline-command.sh already exists — leaving it alone"
else
  STATUS_OK=1
  cat > "$STATUSLINE" <<'STATUSEOF' || STATUS_OK=0
#!/usr/bin/env bash
input=$(cat)
RESET='\033[0m'; BOLD='\033[1m'
WHITE='\033[97m'; CYAN='\033[96m'; GREEN='\033[92m'; YELLOW='\033[93m'
ORANGE='\033[38;5;208m'; RED='\033[91m'; BLUE='\033[94m'; MAGENTA='\033[95m'; GRAY='\033[90m'
SEP="${GRAY} | ${RESET}"
user=$(whoami)
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_full="${dir//$HOME/~}"
dir_short=$(echo "$dir_full" | awk -F'/' '{n=NF; if(n<=3){print $0}else{print "…/" $(n-1) "/" $n}}')
raw_model=$(echo "$input" | jq -r '.model.display_name // ""')
model=""
if [ -n "$raw_model" ]; then
  prefix=$(echo "$raw_model" | grep -ioE 'Haiku|Sonnet|Opus' | head -1 | cut -c1 | tr '[:upper:]' '[:lower:]')
  version=$(echo "$raw_model" | grep -oE '[0-9]+\.[0-9]+' | tail -1)
  [ -n "$prefix" ] && [ -n "$version" ] && model="${prefix}${version}"
  [ -z "$model" ] && model="$raw_model"
fi
git_branch=""
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
fi
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
make_bar() { local pct=$1 width=${2:-10}; local filled; filled=$(echo "$pct $width" | awk '{printf "%d", ($1/100)*$2+0.5}'); local empty=$((width-filled)); local bar=""; for ((i=0;i<filled;i++)); do bar+="#"; done; for ((i=0;i<empty;i++)); do bar+="."; done; printf '%s' "$bar"; }
pct_color() { local pct=$1; if (( $(echo "$pct < 50" | bc -l) )); then printf '%s' "$GREEN"; elif (( $(echo "$pct < 75" | bc -l) )); then printf '%s' "$YELLOW"; elif (( $(echo "$pct < 90" | bc -l) )); then printf '%s' "$ORANGE"; else printf '%s' "$RED"; fi; }
out=""
out+="${BOLD}${CYAN}${user}${RESET}${GRAY} in ${RESET}${WHITE}${dir_short}${RESET}"
[ -n "$git_branch" ] && out+="${GRAY} on ${RESET}${MAGENTA}${git_branch}${RESET}"
[ -n "$model" ] && out+="${SEP}${BLUE}${model}${RESET}"
if [ -n "$used_pct" ]; then pct_int=$(printf '%.0f' "$used_pct"); col=$(pct_color "$used_pct"); bar=$(make_bar "$pct_int" 4); out+="${SEP}${GRAY}ctx ${col}${bar} ${pct_int}%${RESET}"; fi
if [ -n "$five_pct" ]; then
  pct_int=$(printf '%.0f' "$five_pct"); col=$(pct_color "$five_pct"); bar=$(make_bar "$pct_int" 4)
  reset_str=""
  if [ -n "$five_resets" ]; then
    now_epoch=$(date +%s); secs_left=$((five_resets-now_epoch))
    if [ "$secs_left" -gt 0 ]; then mins_left=$((secs_left/60)); h=$((mins_left/60)); m=$((mins_left%60)); if [ "$h" -gt 0 ]; then reset_str=" ${GRAY}(${h}h${m}m)${RESET}"; else reset_str=" ${GRAY}(${m}m)${RESET}"; fi; fi
  fi
  out+="${SEP}${GRAY}5h ${col}${bar} ${pct_int}%${reset_str}${RESET}"
fi
if [ -n "$week_pct" ]; then pct_int=$(printf '%.0f' "$week_pct"); col=$(pct_color "$week_pct"); bar=$(make_bar "$pct_int" 4); out+="${SEP}${GRAY}7d ${col}${bar} ${pct_int}%${RESET}"; fi
printf '%b' "$out"
STATUSEOF
  if [ "$STATUS_OK" -eq 1 ]; then
    chmod +x "$STATUSLINE" 2>/dev/null && ok "statusline-command.sh installed" \
      || warn "statusline-command.sh written but chmod +x failed — run: chmod +x $STATUSLINE"
  else
    warn "Failed to write $STATUSLINE (permissions?) — skipping statusline"
  fi
fi

# ── 6. Merge settings.json + CLAUDE.md (idempotent, non-destructive) ────
log "Merging ~/.claude/settings.json and ~/.claude/CLAUDE.md"
if HOME="$HOME" python3 - <<'PYEOF'
import json, os, re, time

home = os.path.expanduser("~")
claude_dir = os.path.join(home, ".claude")
os.makedirs(claude_dir, exist_ok=True)

def load_json_safely(path):
    """Read+parse JSON, tolerating a corrupt file instead of crashing.
    Returns (data, raw_text_or_empty). On parse failure, the corrupt file
    is preserved under a .corrupt.<timestamp> suffix and we proceed as if
    it didn't exist — a bad hand-edit shouldn't take down the whole run."""
    if not os.path.exists(path):
        return {}, ""
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    if not raw.strip():
        return {}, raw
    try:
        return json.loads(raw), raw
    except json.JSONDecodeError as e:
        corrupt_backup = path + f".corrupt.{time.strftime('%Y%m%dT%H%M%S')}"
        with open(corrupt_backup, "w", encoding="utf-8") as f:
            f.write(raw)
        print(f"  ! existing {os.path.basename(path)} is not valid JSON ({e}); "
              f"saved as {corrupt_backup} and starting fresh")
        return {}, ""

# ---- settings.json ----
settings_path = os.path.join(claude_dir, "settings.json")
data, raw = load_json_safely(settings_path)

data.setdefault("hooks", {})

def basename_of(cmd):
    if not cmd:
        return ""
    return cmd.strip().split()[-1].split("/")[-1]

def set_hook(event, matcher, command):
    entries = data["hooks"].setdefault(event, [])
    target = basename_of(command)
    for block in entries:
        block["hooks"] = [h for h in block.get("hooks", [])
                           if basename_of(h.get("command", "")) != target]
    entries[:] = [b for b in entries if b.get("hooks")]
    block = next((b for b in entries if b.get("matcher") == matcher), None)
    if block is None:
        block = {"hooks": []}
        if matcher is not None:
            block["matcher"] = matcher
        entries.append(block)
    block["hooks"].append({"type": "command", "command": command})

set_hook("PreToolUse", "Bash", "bash ~/.claude/hooks/bash-ban-raw-tools")
set_hook("PreToolUse", "Grep|Glob|Read|Search", "bash ~/.claude/hooks/cbm-code-discovery-gate")
set_hook("PostToolUse", None, "bash ~/.claude/hooks/cbm-mcp-marker")
set_hook("SessionStart", None, "bash ~/.claude/hooks/cbm-session-reminder")

data.setdefault("statusLine", {"type": "command", "command": "bash ~/.claude/statusline-command.sh"})

plugins = data.setdefault("enabledPlugins", {})
plugins["context-mode@context-mode"] = True
plugins["caveman@caveman"] = True

markets = data.setdefault("extraKnownMarketplaces", {})
markets["context-mode"] = {"source": {"source": "github", "repo": "mksglu/context-mode"}}
markets["caveman"] = {"source": {"source": "github", "repo": "JuliusBrussee/caveman"}}

env = data.setdefault("env", {})
env.setdefault("BASH_MAX_OUTPUT_LENGTH", "10000")
env.setdefault("MAX_MCP_OUTPUT_TOKENS", "10000")

new_raw = json.dumps(data, indent=2) + "\n"
if new_raw != raw:
    if raw:
        backup = settings_path + f".bak.{time.strftime('%Y%m%dT%H%M%S')}"
        with open(backup, "w", encoding="utf-8") as f:
            f.write(raw)
        print(f"  + backed up previous settings.json -> {backup}")
    with open(settings_path, "w", encoding="utf-8") as f:
        f.write(new_raw)
    print(f"  + settings.json updated: {settings_path}")
else:
    print("  + settings.json already up to date")

# ---- CLAUDE.md ----
claude_md = os.path.join(claude_dir, "CLAUDE.md")
start = "<!-- token-stack:start -->"
end = "<!-- token-stack:end -->"
block = f"""{start}
## Token-optimization stack
- Code discovery: use codebase-memory-mcp tools first (`search_graph`, `trace_path`, `get_code_snippet`, `get_architecture`). Fall back to Grep/Glob/Read only for text search, non-code files, or before the project is indexed (run `index_repository` first).
- Shell: raw `cat`/`head`/`tail`/`find`/`grep`/`rg` in Bash are blocked by a hook — use the Read/Glob/Grep tools, or rtk-wrapped commands.
- Large command output (logs, test runs): prefer context-mode's sandboxed execution over `| head`/`| tail` piping.
- Mermaid diagrams over prose for architecture explanations.
{end}"""

content = ""
if os.path.exists(claude_md):
    with open(claude_md, encoding="utf-8") as f:
        content = f.read()

if start in content and end in content:
    new_content = re.sub(re.escape(start) + r".*?" + re.escape(end), block, content, flags=re.S)
else:
    new_content = block + ("\n\n" + content if content.strip() else "\n")

if new_content != content:
    if content:
        backup = claude_md + f".bak.{time.strftime('%Y%m%dT%H%M%S')}"
        with open(backup, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"  + backed up previous CLAUDE.md -> {backup}")
    with open(claude_md, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"  + CLAUDE.md updated: {claude_md}")
else:
    print("  + CLAUDE.md already up to date")
PYEOF
then
  ok "settings.json / CLAUDE.md merge complete"
else
  warn "settings.json / CLAUDE.md merge hit an error (see python output above) — everything else installed above is unaffected. Re-run this script to retry just the merge."
fi

# ── Done ──────────────────────────────────────────────────────────────
log "Install complete"
cat <<SUMMARY
Installed / configured:
  - Headroom + RTK (checked/installed, shell wrapper wired)
  - codebase-memory-mcp (code discovery)$([ "$CBM_OK" -eq 1 ] || echo " — NOT installed, see warnings")
  - context-mode + caveman Claude Code plugins
  - enforcement hooks in ~/.claude/hooks/
  - ~/.claude/settings.json  (merged, backup written if changed)
  - ~/.claude/CLAUDE.md      (merged, backup written if changed)
  - ~/.claude/statusline-command.sh (only if you had none)

Next steps:
  1. Restart your shell: exec \$SHELL
  2. cd into a project and run 'claude' — on first code question it will
     prompt to index the repo (or run: codebase-memory-mcp cli index_repository)
  3. Run '/caveman' inside a session to activate terse output mode
  4. Watch the statusline for ctx%/5h/7d usage

Sources (read before trusting a curl|bash install):
  CBM:          https://github.com/DeusData/codebase-memory-mcp
  context-mode: https://github.com/mksglu/context-mode
  caveman:      https://github.com/JuliusBrussee/caveman
  hook design adapted from: https://github.com/sgaabdu4/claude-code-tips
SUMMARY

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo ""
  echo "Completed with ${#WARNINGS[@]} non-fatal warning(s):"
  for w in "${WARNINGS[@]}"; do
    echo "  - $w"
  done
fi
