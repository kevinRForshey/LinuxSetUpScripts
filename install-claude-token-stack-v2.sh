#!/usr/bin/env bash
# install-claude-token-stack-v2.sh
#
# Claude Code Token Stack — Generation 2 for enterprise .NET work.
#
# This is a modular installer: each module is independently idempotent and can
# be understood or changed without relying on the others.  It deliberately
# optimizes context growth rather than trying to police every tool invocation.
# In particular it migrates away from the Generation 1 CBM gate, raw-tool ban,
# context-mode, automatic Caveman use, and 10k-token output limits.
#
# Modules:
#   00 preflight       01 Gen 1 migration       02 core configuration
#   03 statusline      04 .NET repository memory 05 optional helpers
#   06 verification    07 diagnostics            08 uninstall
#
# Usage:
#   ./install-claude-token-stack-v2.sh
#   ./install-claude-token-stack-v2.sh --project /path/to/dotnet-repo
#   ./install-claude-token-stack-v2.sh --with-headroom --with-cbm
#   ./install-claude-token-stack-v2.sh --doctor
#   ./install-claude-token-stack-v2.sh --uninstall
#
# Optional helpers are never made mandatory.  This script does not install
# context-mode or Caveman, and does not add blocking Claude Code hooks.

set -Eeuo pipefail

readonly VERSION="2.0.0"
readonly STACK_MARKER="claude-token-stack-v2"
readonly CLAUDE_DIR="${HOME}/.claude"
readonly HOOKS_DIR="${CLAUDE_DIR}/hooks"
readonly LOCAL_BIN="${HOME}/.local/bin"
readonly SETTINGS_PATH="${CLAUDE_DIR}/settings.json"
readonly STATE_DIR="${CLAUDE_DIR}/token-stack-v2"

PROJECT_DIR=""
WITH_HEADROOM=0
WITH_CBM=0
DOCTOR=0
UNINSTALL=0
DRY_RUN=0
WARNINGS=()
CHANGES=()

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '  + %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; WARNINGS+=("$*"); }
die()  { printf 'Error: %s\n' "$*" >&2; exit 1; }
changed() { CHANGES+=("$*"); ok "$*"; }

usage() {
  cat <<'EOF'
Claude Code Token Stack — Generation 2

Usage:
  ./install-claude-token-stack-v2.sh [options]

Options:
  --project PATH       Generate a compact repository memory and managed .NET
                       CLAUDE.md block for PATH.
  --with-headroom      Install Headroom as an optional experiment.  No shell
                       wrapper is added; evaluate its value before using it.
  --with-cbm           Install CBM as an optional large-repository helper.
                       It is never gated or required.
  --doctor             Diagnose the installed stack without changing files.
  --uninstall          Remove only configuration and helpers owned by v2.
  --dry-run            Show planned actions; do not write or install anything.
  -h, --help           Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --project)
      shift; (($#)) || die "--project requires a directory"
      PROJECT_DIR="$1"
      ;;
    --with-headroom) WITH_HEADROOM=1 ;;
    --with-cbm) WITH_CBM=1 ;;
    --doctor) DOCTOR=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

run_or_show() {
  # The only commands passed here are fixed commands assembled by this script.
  if ((DRY_RUN)); then
    note "Would run: $*"
  else
    "$@"
  fi
}

backup_file() {
  local file="$1" backup
  [[ -f "$file" ]] || return 0
  backup="${file}.bak.$(date +%Y%m%dT%H%M%S)"
  if ((DRY_RUN)); then
    note "Would back up $file -> $backup"
  else
    cp -p -- "$file" "$backup"
    note "Backed up $(basename "$file") -> $(basename "$backup")"
  fi
}

module_preflight() {
  log "00 — Preflight"
  local missing=() command
  for command in python3 jq; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  ((${#missing[@]} == 0)) || die "Missing required tools: ${missing[*]}"
  ok "python3 and jq are available"
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code CLI: $(command -v claude)"
  else
    warn "Claude Code CLI is not on PATH; settings can be prepared, but plugin migration cannot run."
  fi
  if [[ -n "$PROJECT_DIR" ]]; then
    [[ -d "$PROJECT_DIR" ]] || die "Project directory does not exist: $PROJECT_DIR"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ok "Project: $PROJECT_DIR"
  fi
}

remove_gen1_hook_files() {
  local file removed=0
  for file in bash-ban-raw-tools cbm-code-discovery-gate cbm-mcp-marker cbm-session-reminder; do
    if [[ -e "${HOOKS_DIR}/${file}" ]]; then
      if ((DRY_RUN)); then
        note "Would remove Gen 1 hook ${HOOKS_DIR}/${file}"
      else
        rm -f -- "${HOOKS_DIR}/${file}"
      fi
      removed=1
      changed "Removed Gen 1 hook: $file"
    fi
  done
  ((removed)) || note "No Gen 1 hook files found"
}

remove_gen1_headroom_wrapper() {
  # Gen 1 automatically shadowed claude() in the user's shell.  Headroom is
  # retained as an experiment, but an automatic wrapper makes its overhead
  # unavoidable.  Remove only the exact comment-labelled Gen 1 snippets.
  local rc
  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.config/fish/config.fish"; do
    [[ -f "$rc" ]] || continue
    if ! rg -q '^# Headroom wraps Claude Code for API-layer token compression$' "$rc"; then
      continue
    fi
    if ((DRY_RUN)); then
      note "Would remove labelled Gen 1 Headroom wrapper from $rc"
      continue
    fi
    backup_file "$rc"
    RC_PATH="$rc" python3 - <<'PY'
import os, re
path = os.environ['RC_PATH']
text = open(path, encoding='utf-8').read()
text = re.sub(r'\n?# Headroom wraps Claude Code for API-layer token compression\nclaude\(\) \{ command headroom wrap claude "\$@"; \}\n?', '\n', text)
text = re.sub(r'\n?# Headroom wraps Claude Code for API-layer token compression\nfunction claude\n    command headroom wrap claude \$argv\nend\n?', '\n', text)
open(path, 'w', encoding='utf-8').write(text)
PY
    changed "Removed automatic Gen 1 Headroom wrapper from $rc"
  done
}

module_migrate_gen1() {
  log "01 — Migrate Generation 1 behavior"
  if ((DRY_RUN)); then
    note "Would ensure hook directory exists: $HOOKS_DIR"
  else
    mkdir -p "$HOOKS_DIR"
  fi
  remove_gen1_hook_files
  remove_gen1_headroom_wrapper
  if command -v claude >/dev/null 2>&1; then
    if ((DRY_RUN)); then
      note "Would uninstall context-mode if installed"
    else
      claude plugin uninstall context-mode@context-mode >/dev/null 2>&1 || true
    fi
    changed "Disabled context-mode (uninstalled when present)"
  fi
  note "Caveman is left installed, if present, but is disabled by settings and never auto-activated"
}

module_settings() {
  log "02 — Merge token-efficient Claude Code settings"
  ((DRY_RUN)) && { note "Would merge $SETTINGS_PATH"; return; }
  env SETTINGS_PATH="$SETTINGS_PATH" python3 - <<'PY'
import json, os, shutil, time

path = os.environ['SETTINGS_PATH']
os.makedirs(os.path.dirname(path), exist_ok=True)
raw = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
try:
    data = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError as exc:
    backup = f'{path}.corrupt.{time.strftime("%Y%m%dT%H%M%S")}'
    shutil.copy2(path, backup)
    print(f'  ! Invalid settings.json preserved at {backup}: {exc}')
    data = {}

# Delete only hooks that the old installer owned.  Retain every other hook and
# matcher exactly as the user configured it.
legacy_names = {
    'bash-ban-raw-tools', 'cbm-code-discovery-gate', 'cbm-mcp-marker',
    'cbm-session-reminder'
}
for event, blocks in list(data.get('hooks', {}).items()):
    retained_blocks = []
    for block in blocks:
        retained_hooks = []
        for hook in block.get('hooks', []):
            command = hook.get('command', '')
            last = command.split()[-1] if command else ''
            if os.path.basename(last) not in legacy_names:
                retained_hooks.append(hook)
        if retained_hooks:
            clone = dict(block); clone['hooks'] = retained_hooks
            retained_blocks.append(clone)
    if retained_blocks:
        data['hooks'][event] = retained_blocks
    else:
        data['hooks'].pop(event, None)
if not data.get('hooks'):
    data.pop('hooks', None)

plugins = data.setdefault('enabledPlugins', {})
plugins['context-mode@context-mode'] = False
plugins['caveman@caveman'] = False

# These values intentionally replace Gen 1's 10k caps.  A 2k MCP result and a
# 2.5k Bash result allow useful diagnostics without silently flooding context.
env = data.setdefault('env', {})
env['BASH_MAX_OUTPUT_LENGTH'] = '2500'
env['MAX_MCP_OUTPUT_TOKENS'] = '2000'
data.setdefault('statusLine', {
    'type': 'command', 'command': 'bash ~/.claude/statusline-command.sh'
})

new = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
if new != raw:
    if raw:
        backup = f'{path}.bak.{time.strftime("%Y%m%dT%H%M%S")}'
        with open(backup, 'w', encoding='utf-8') as f: f.write(raw)
        print(f'  + Backed up settings.json -> {backup}')
    with open(path, 'w', encoding='utf-8') as f: f.write(new)
    print(f'  + Updated {path}')
else:
    print('  + settings.json already has Generation 2 values')
PY
  changed "Merged settings without replacing user-owned keys"
}

module_global_instructions() {
  log "02 — Add compact global .NET workflow guidance"
  ((DRY_RUN)) && { note "Would merge ${CLAUDE_DIR}/CLAUDE.md"; return; }
  env CLAUDE_DIR="$CLAUDE_DIR" python3 - <<'PY'
import os, re, shutil, time

path = os.path.join(os.environ['CLAUDE_DIR'], 'CLAUDE.md')
os.makedirs(os.path.dirname(path), exist_ok=True)
old = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
# The Gen 1 marked block had mandatory CBM and tool-banning instructions.
old = re.sub(r'<!-- token-stack:start -->.*?<!-- token-stack:end -->\n*', '', old, flags=re.S)
start, end = '<!-- token-stack-v2:start -->', '<!-- token-stack-v2:end -->'
block = '''<!-- token-stack-v2:start -->
## Token-efficient .NET workflow
- Keep context small: inspect the requested symbol, containing file, and direct dependencies first. Expand outward only when evidence requires it; never reread unchanged files.
- Use targeted Read/Grep/Glob or `rg`/`find`; avoid broad solution dumps and generated `bin/`/`obj/` content. Cap command output and use focused project builds/tests.
- Navigate C# symbol-first. For ASP.NET Core, Blazor, Dapper, SDK, or repository work, inspect the endpoint/component/repository plus interface/model before following extra layers.
- Treat `Program.cs`, `appsettings*.json`, `Directory.Build.*`, `global.json`, and launch settings as stable context: read once only when relevant, then retain their facts.
- Compact only near genuine context capacity, after a material task change, or at the user's request—not at session start. Use concise Mermaid only when a diagram clarifies architecture.
<!-- token-stack-v2:end -->'''
new = re.sub(re.escape(start) + r'.*?' + re.escape(end), block, old, flags=re.S) if start in old else block + ('\n\n' + old if old.strip() else '\n')
if new != old:
    if old:
        backup = f'{path}.bak.{time.strftime("%Y%m%dT%H%M%S")}'
        shutil.copy2(path, backup)
        print(f'  + Backed up CLAUDE.md -> {backup}')
    with open(path, 'w', encoding='utf-8') as f: f.write(new)
    print(f'  + Updated {path}')
else:
    print('  + Global CLAUDE.md already has Generation 2 guidance')
PY
  changed "Added progressive-context .NET guidance"
}

module_statusline() {
  log "03 — Install context-health statusline"
  local target="${CLAUDE_DIR}/statusline-command.sh"
  if [[ -e "$target" ]]; then
    note "Existing statusline retained: $target"
    return
  fi
  ((DRY_RUN)) && { note "Would install $target"; return; }
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
# claude-token-stack-v2 statusline
set -uo pipefail
input=$(cat)
model=$(jq -r '.model.display_name // "Claude"' <<<"$input")
dir=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$input")
context=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
five=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
week=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$input")
branch=""
if [[ -n "$dir" ]] && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)
fi
short="${dir/#$HOME/~}"
short=$(awk -F/ '{if (NF > 3) print "…/" $(NF-1) "/" $NF; else print}' <<<"$short")
pct() { [[ -n "$1" ]] && printf '%s%%' "$(printf '%.0f' "$1")"; }
out="$model · $short"
[[ -n "$branch" ]] && out+=" ($branch)"
[[ -n "$context" ]] && out+=" · ctx $(pct "$context")"
[[ -n "$five" ]] && out+=" · 5h $(pct "$five")"
[[ -n "$week" ]] && out+=" · 7d $(pct "$week")"
printf '%s' "$out"
EOF
  chmod +x "$target"
  changed "Installed compact context/rate statusline"
}

write_summary_command() {
  local target="${LOCAL_BIN}/claude-dotnet-summary"
  ((DRY_RUN)) && { note "Would install $target"; return; }
  mkdir -p "$LOCAL_BIN"
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
# Generate a compact architecture cache; it never modifies CLAUDE.md.
set -Eeuo pipefail
repo="${1:-$PWD}"
repo="$(cd "$repo" && pwd)"
out="$repo/.claude/token-stack-v2/solution-summary.md"
mkdir -p "$(dirname "$out")"
find_files() { find "$repo" -path '*/bin' -prune -o -path '*/obj' -prune -o "$@" -type f -printf '  - %P\n'; }
{
  echo '# .NET solution summary (generated)'
  echo
  echo "- Root: $repo"
  if [[ -f "$repo/global.json" ]]; then
    echo "- SDK: $(jq -r '.sdk.version // "unspecified"' "$repo/global.json" 2>/dev/null || echo 'see global.json')"
  fi
  echo '- Solutions:'; find_files -name '*.sln' | sort | head -20
  echo '- Projects:'; find_files -name '*.csproj' | sort | head -80
  echo '- Stable root files:'
  for f in Program.cs Directory.Build.props Directory.Build.targets global.json appsettings.json; do
    [[ -f "$repo/$f" ]] && echo "  - $f"
  done
  echo
  echo 'Refresh after solution-layout changes. Promote only durable facts into CLAUDE.md.'
} > "$out"
printf 'Wrote %s\n' "$out"
EOF
  chmod +x "$target"
  changed "Installed claude-dotnet-summary helper"
}

write_doctor_command() {
  local target="${LOCAL_BIN}/claude-token-stack-v2-doctor"
  ((DRY_RUN)) && { note "Would install $target"; return; }
  mkdir -p "$LOCAL_BIN"
  cat > "$target" <<'EOF'
#!/usr/bin/env bash
# Thin stable entrypoint: use the installer location printed in its output for
# full remediation. This helper only reports current configuration.
set -Eeuo pipefail
settings="$HOME/.claude/settings.json"
echo 'Claude Token Stack v2 diagnostic'
if [[ -f "$settings" ]] && jq empty "$settings" >/dev/null 2>&1; then
  echo "  settings: valid JSON"
  echo "  Bash cap: $(jq -r '.env.BASH_MAX_OUTPUT_LENGTH // "unset"' "$settings")"
  echo "  MCP cap:  $(jq -r '.env.MAX_MCP_OUTPUT_TOKENS // "unset"' "$settings")"
  echo "  context-mode: $(jq -r '.enabledPlugins["context-mode@context-mode"] // "unset"' "$settings")"
else
  echo '  settings: missing or invalid'
fi
for hook in bash-ban-raw-tools cbm-code-discovery-gate cbm-mcp-marker cbm-session-reminder; do
  [[ -e "$HOME/.claude/hooks/$hook" ]] && echo "  warning: legacy hook remains: $hook"
done
command -v claude >/dev/null 2>&1 && echo "  Claude CLI: $(claude --version 2>/dev/null | head -1)" || echo '  Claude CLI: not on PATH'
EOF
  chmod +x "$target"
  changed "Installed claude-token-stack-v2-doctor helper"
}

module_project_memory() {
  log "04 — .NET repository memory"
  write_summary_command
  [[ -n "$PROJECT_DIR" ]] || { note "No --project supplied; repository-specific memory skipped"; return; }
  if ((DRY_RUN)); then
    note "Would generate $PROJECT_DIR/.claude/token-stack-v2/solution-summary.md"
    note "Would merge a managed .NET block into $PROJECT_DIR/CLAUDE.md"
    return
  fi
  "$LOCAL_BIN/claude-dotnet-summary" "$PROJECT_DIR"
  env PROJECT_DIR="$PROJECT_DIR" python3 - <<'PY'
import os, re, shutil, time
repo = os.environ['PROJECT_DIR']
path = os.path.join(repo, 'CLAUDE.md')
old = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
start, end = '<!-- token-stack-v2-dotnet:start -->', '<!-- token-stack-v2-dotnet:end -->'
block = '''<!-- token-stack-v2-dotnet:start -->
## Repository context protocol
- Start with `.claude/token-stack-v2/solution-summary.md`; refresh it only after project-layout changes.
- Read the affected project, symbol, and direct contract before broader searches. Do not load generated output, migrations, or unrelated projects unless the task requires them.
- Make minimal diffs and validate the smallest affected project/test target first. State when a full solution build is genuinely required.
<!-- token-stack-v2-dotnet:end -->'''
new = re.sub(re.escape(start) + r'.*?' + re.escape(end), block, old, flags=re.S) if start in old else block + ('\n\n' + old if old.strip() else '\n')
if new != old:
    if old:
        backup = f'{path}.bak.{time.strftime("%Y%m%dT%H%M%S")}'
        shutil.copy2(path, backup)
        print(f'  + Backed up repository CLAUDE.md -> {backup}')
    open(path, 'w', encoding='utf-8').write(new)
    print(f'  + Updated {path}')
else:
    print('  + Repository CLAUDE.md already has v2 protocol')
PY
  changed "Generated repository summary and .NET CLAUDE.md protocol"
}

module_optional_helpers() {
  log "05 — Optional helpers"
  if ((WITH_HEADROOM)); then
    if command -v headroom >/dev/null 2>&1; then
      ok "Headroom already installed"
    elif command -v pip3 >/dev/null 2>&1; then
      if ((DRY_RUN)); then note "Would install headroom-ai[all] with pip3 --user"
      elif pip3 install --user 'headroom-ai[all]'; then changed "Installed optional Headroom"
      else warn "Headroom installation failed; core configuration is unaffected"; fi
    else
      warn "pip3 unavailable; skipped optional Headroom"
    fi
    note "No shell wrapper was added. Measure Headroom on representative work before adopting it."
  else
    note "Headroom not requested (recommended default)"
  fi
  if ((WITH_CBM)); then
    if command -v codebase-memory-mcp >/dev/null 2>&1; then
      ok "codebase-memory-mcp already installed"
    elif ((DRY_RUN)); then
      note "Would try an available AUR helper for codebase-memory-mcp-bin"
    elif command -v paru >/dev/null 2>&1 && paru -S --noconfirm codebase-memory-mcp-bin; then
      changed "Installed optional CBM via paru"
    elif command -v yay >/dev/null 2>&1 && yay -S --noconfirm codebase-memory-mcp-bin; then
      changed "Installed optional CBM via yay"
    else
      warn "No AUR helper installed CBM; install it later if symbol navigation in a very large repository justifies it"
    fi
    note "CBM is advisory only; normal Read/Grep/Glob/rg/find remain available."
  else
    note "CBM not requested (recommended unless repository navigation is demonstrably costly)"
  fi
}

module_verify() {
  log "06 — Verify configuration"
  local legacy=0 hook
  if [[ -f "$SETTINGS_PATH" ]] && jq empty "$SETTINGS_PATH" >/dev/null 2>&1; then
    ok "settings.json is valid JSON"
    [[ "$(jq -r '.env.BASH_MAX_OUTPUT_LENGTH // empty' "$SETTINGS_PATH")" == 2500 ]] && ok "Bash output cap is 2500" || warn "Bash output cap is not 2500"
    [[ "$(jq -r '.env.MAX_MCP_OUTPUT_TOKENS // empty' "$SETTINGS_PATH")" == 2000 ]] && ok "MCP output cap is 2000" || warn "MCP output cap is not 2000"
    [[ "$(jq -r '.enabledPlugins["context-mode@context-mode"] // empty' "$SETTINGS_PATH")" == false ]] && ok "context-mode is disabled" || warn "context-mode is not explicitly disabled"
  else
    warn "settings.json is missing or invalid"
  fi
  for hook in bash-ban-raw-tools cbm-code-discovery-gate cbm-mcp-marker cbm-session-reminder; do
    [[ -e "${HOOKS_DIR}/${hook}" ]] && { warn "Legacy hook remains: $hook"; legacy=1; }
  done
  ((legacy == 0)) && ok "No Generation 1 enforcement hooks remain"
  [[ -x "${LOCAL_BIN}/claude-dotnet-summary" ]] && ok "Repository-summary helper is executable" || warn "Repository-summary helper is missing"
  [[ -x "${LOCAL_BIN}/claude-token-stack-v2-doctor" ]] && ok "Diagnostic helper is executable" || warn "Diagnostic helper is missing"
}

module_doctor() {
  log "07 — Diagnostic report"
  [[ -f "$SETTINGS_PATH" ]] && jq empty "$SETTINGS_PATH" >/dev/null 2>&1 && ok "settings.json parses" || warn "settings.json missing or invalid"
  [[ -f "${CLAUDE_DIR}/CLAUDE.md" ]] && rg -q '<!-- token-stack-v2:start -->' "${CLAUDE_DIR}/CLAUDE.md" && ok "Global v2 instructions found" || warn "Global v2 instructions not found"
  if [[ -n "$PROJECT_DIR" ]]; then
    [[ -f "${PROJECT_DIR}/.claude/token-stack-v2/solution-summary.md" ]] && ok "Project summary found" || warn "Project summary not found; run with --project PATH"
    [[ -f "${PROJECT_DIR}/CLAUDE.md" ]] && rg -q '<!-- token-stack-v2-dotnet:start -->' "${PROJECT_DIR}/CLAUDE.md" && ok "Project protocol found" || warn "Project protocol not found"
  fi
  module_verify
  cat <<'EOF'

Interpretation:
  - The meaningful savings come from selective exploration, bounded output, and
    avoiding premature compaction—not from forcing an MCP call before every read.
  - If output is still too large, reduce the command scope first; do not blindly
    lower limits until common build/test diagnostics become unusable.
  - Use CBM only when it measurably avoids repeated navigation in a large repo.
EOF
}

module_uninstall() {
  log "08 — Remove Generation 2 managed configuration"
  if ((DRY_RUN)); then
    note "Would remove v2 instruction blocks, helper commands, and v2 output caps"
    return
  fi
  env SETTINGS_PATH="$SETTINGS_PATH" CLAUDE_DIR="$CLAUDE_DIR" PROJECT_DIR="$PROJECT_DIR" python3 - <<'PY'
import json, os, re, shutil, time
def backup(path):
    shutil.copy2(path, f'{path}.bak.{time.strftime("%Y%m%dT%H%M%S")}')
def strip_block(path, start, end):
    if not os.path.exists(path): return
    old = open(path, encoding='utf-8').read()
    new = re.sub(re.escape(start) + r'.*?' + re.escape(end) + r'\n*', '', old, flags=re.S)
    if new != old:
        backup(path); open(path, 'w', encoding='utf-8').write(new); print(f'  + Removed managed block from {path}')
settings = os.environ['SETTINGS_PATH']
if os.path.exists(settings):
    old = open(settings, encoding='utf-8').read()
    try: data = json.loads(old)
    except json.JSONDecodeError: data = None
    if data is not None:
        for key in ('BASH_MAX_OUTPUT_LENGTH', 'MAX_MCP_OUTPUT_TOKENS'):
            data.get('env', {}).pop(key, None)
        new = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
        if new != old:
            backup(settings); open(settings, 'w', encoding='utf-8').write(new); print('  + Removed v2 output caps')
strip_block(os.path.join(os.environ['CLAUDE_DIR'], 'CLAUDE.md'), '<!-- token-stack-v2:start -->', '<!-- token-stack-v2:end -->')
repo = os.environ.get('PROJECT_DIR', '')
if repo:
    strip_block(os.path.join(repo, 'CLAUDE.md'), '<!-- token-stack-v2-dotnet:start -->', '<!-- token-stack-v2-dotnet:end -->')
PY
  rm -f -- "${LOCAL_BIN}/claude-dotnet-summary" "${LOCAL_BIN}/claude-token-stack-v2-doctor"
  # Preserve user customizations and optional third-party tools.  A statusline
  # is removed only when it has the v2 marker.
  if [[ -f "${CLAUDE_DIR}/statusline-command.sh" ]] && rg -q '^# claude-token-stack-v2 statusline$' "${CLAUDE_DIR}/statusline-command.sh"; then
    rm -f -- "${CLAUDE_DIR}/statusline-command.sh"
    changed "Removed v2-owned statusline"
  fi
  changed "Removed v2 helpers and managed configuration"
  note "Optional Headroom/CBM installations and plugin state were intentionally left unchanged."
}

main() {
  module_preflight
  if ((DOCTOR)); then module_doctor; return; fi
  if ((UNINSTALL)); then module_uninstall; return; fi

  module_migrate_gen1
  module_settings
  module_global_instructions
  module_statusline
  module_project_memory
  write_doctor_command
  module_optional_helpers
  module_verify

  log "Generation 2 installation complete"
  printf 'Version: %s\n' "$VERSION"
  printf 'Changed: %d item(s)\n' "${#CHANGES[@]}"
  cat <<'EOF'

Next steps:
  1. Restart Claude Code so it reloads settings and removes stale hook state.
  2. For a repository, run this installer once with --project PATH; refresh its
     summary after solution-layout changes with: claude-dotnet-summary PATH
  3. Use focused symbol/file exploration and project-scoped builds.  Do not use
     /caveman or CBM by default; enable each only when it improves a real task.
  4. Run claude-token-stack-v2-doctor after upgrades or if behavior regresses.
EOF
  if ((${#WARNINGS[@]})); then
    printf '\nCompleted with %d warning(s):\n' "${#WARNINGS[@]}"
    printf '  - %s\n' "${WARNINGS[@]}"
  fi
}

main
