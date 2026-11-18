#!/usr/bin/env bash
# Deterministic smoke test for this devcontainer.
#
# Destructive modes (build/up/pre/idempotent/recreate/fresh/tz) run against a disposable
# copy of the repo under $HOME and use prefixed volume names for the repo's own
# mounts. Named volumes declared outside devcontainer.json are not rewritten;
# the smoke tests do not write to them. The real repo's container and volumes
# are never modified by this script.
#
# Usage: test/devcontainer-smoke.sh [guard|static|app-token|build|pre|up|smoke|smoke-real|paste|paste-real|idempotent|recreate|fresh|tz|cleanup|all]
# Set CID=<container-id> for smoke-real and paste-real.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MODE="${1:-all}"
SMOKE_ROOT="${SMOKE_ROOT:-$HOME/.dc-smoke}"
RUN_ID="$(date +%s)-$$"
PREFIX="dcsmoke-${RUN_ID}-"
COPY="$SMOKE_ROOT/proj-${RUN_ID}"
LAST_COPY_FILE="$SMOKE_ROOT/last-copy"

say() { printf '\n== %s ==\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check_eq_host() {
  local n="$1" e="$2" a="$3"
  [ "$e" = "$a" ] || die "$n (expected '$e', got '$a')"
  printf 'PASS %s\n' "$n"
}

parse_up_json() {
  python3 - "$1" <<'PY'
import json, sys
text = open(sys.argv[1], encoding='utf-8', errors='replace').read()
dec = json.JSONDecoder()
best = None
for i, ch in enumerate(text):
    if ch != '{':
        continue
    try:
        obj, end = dec.raw_decode(text[i:])
    except Exception:
        continue
    if isinstance(obj, dict) and ('outcome' in obj or 'containerId' in obj):
        best = obj
if best is None:
    sys.exit('no JSON result found in devcontainer output')
print(json.dumps(best))
PY
}

extract_container_id() {
  python3 - "$1" <<'PY'
import json, sys
try:
    obj = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
cid = obj.get('containerId', '')
if cid:
    print(cid)
PY
}

prepare_copy() {
  case "$COPY" in
    "$SMOKE_ROOT"/proj-*) ;;
    *) die "unsafe copy path: $COPY" ;;
  esac
  say "Preparing disposable copy at $COPY"
  mkdir -p "$SMOKE_ROOT"
  rm -rf -- "$COPY"
  mkdir -p "$COPY"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude .git --exclude test --exclude repos "$REPO/" "$COPY/"
  else
    (cd "$REPO" && tar --exclude .git --exclude test --exclude repos -cf - .) | (cd "$COPY" && tar -xf -)
  fi
  python3 - "$COPY/.devcontainer/devcontainer.json" "$PREFIX" "$COPY" <<'PY'
import json, sys
path, prefix, copy = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
mounts = []
for mount in data.get('mounts', []):
    parts = mount.split(',')
    is_volume = any(p == 'type=volume' for p in parts)
    m = dict(part.split('=', 1) for part in parts if '=' in part)
    target = m.get('target') or m.get('dst') or ''
    out = []
    for part in parts:
        if is_volume and (part.startswith('source=') or part.startswith('src=')):
            key, value = part.split('=', 1)
            part = f'{key}={prefix}{value}'
        elif target == '/etc/opencode' and (part.startswith('source=') or part.startswith('src=')):
            key, _ = part.split('=', 1)
            part = f'{key}={copy}/host-opencode'
        elif target == '/home/developer/.dc/github' and (part.startswith('source=') or part.startswith('src=')):
            key, _ = part.split('=', 1)
            part = f'{key}={copy}/host-github'
        elif target == '/home/developer/.dc/brave/.env' and (part.startswith('source=') or part.startswith('src=')):
            key, _ = part.split('=', 1)
            part = f'{key}={copy}/host-brave.env'
        out.append(part)
    mounts.append(','.join(out))
data['mounts'] = mounts
data['initializeCommand'] = 'true'
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
  mkdir -p "$COPY/host-opencode/agents"
  mkdir -p "$COPY/host-github"
  cat >"$COPY/host-github/.env" <<'ENV'
GITHUB_TOKEN=placeholder-smoke-token
ENV
  cat >"$COPY/host-brave.env" <<'ENV'
BRAVE_API_KEY=placeholder-smoke-key
ENV
  cat >"$COPY/host-opencode/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "permissions": [
    { "action": "mcp.use", "resource": "probe-disabled", "effect": "allow" }
  ],
  "mcp": {
    "servers": {
      "probe-disabled": {
        "type": "local",
        "command": ["true"],
        "disabled": true
      }
    }
  }
}
JSON
  cat >"$COPY/host-opencode/agents/research.md" <<'MD'
---
description: Host test research override
mode: subagent
permissions:
  - action: edit
    resource: "research/host/**"
    effect: allow
---
Host test research override body. Use the test host MCP server for research and
mark unsupported claims unverified.
MD
  say "Preparing hermetic repo remote at $COPY/test-remote.git"
  rm -rf -- "$COPY/test-remote.git"
  git init -q --bare "$COPY/test-remote.git"
  git -C "$COPY/test-remote.git" symbolic-ref HEAD refs/heads/main
  local_repo="$SMOKE_ROOT/repo-src-${RUN_ID}"
  rm -rf -- "$local_repo"
  git init -q "$local_repo"
  git -C "$local_repo" config user.name "Dev Container Smoke"
  git -C "$local_repo" config user.email "smoke@example.invalid"
  printf 'hello\n' >"$local_repo/README.md"
  git -C "$local_repo" add README.md
  git -C "$local_repo" commit -q -m 'smoke: initial commit'
  git -C "$local_repo" branch -M main
  git -C "$local_repo" remote add origin "$COPY/test-remote.git"
  git -C "$local_repo" push -q origin main
  rm -rf -- "$local_repo"
  printf '%s' "$PREFIX" >"$COPY/.dc-smoke-prefix"
  printf '%s' "$COPY" >"$LAST_COPY_FILE"
  echo "PASS: disposable copy and volume prefix $PREFIX"
}

last_copy() {
  [ -f "$LAST_COPY_FILE" ] || die "no disposable copy; run build (or all) first"
  COPY="$(cat "$LAST_COPY_FILE")"
  case "$COPY" in
    "$SMOKE_ROOT"/proj-*) ;;
    *) die "unsafe copy path: $COPY" ;;
  esac
  [ -d "$COPY" ] || die "disposable copy missing: $COPY"
  PREFIX="$(cat "$COPY/.dc-smoke-prefix" 2>/dev/null || true)"
  case "$PREFIX" in
    dcsmoke-[0-9]*-[0-9]*-) ;;
    *) die "unsafe volume prefix: '$PREFIX'" ;;
  esac
}

container_id() {
  if [ -n "${CID:-}" ]; then
    printf '%s' "$CID"
    return 0
  fi
  local file="$COPY/.dc-smoke-container-id"
  [ -f "$file" ] || die "no container id; run up/pre first"
  cat "$file"
}

run_guard_test() {
  say "T0 destructive-guard self-test"
  mkdir -p "$SMOKE_ROOT"
  local dir="$SMOKE_ROOT/proj-guard-$$"
  local guard_file="$SMOKE_ROOT/guard-last-copy-$$"
  rm -rf -- "$dir"
  rm -f -- "$guard_file"
  mkdir -p "$dir"
  : >"$dir/.dc-smoke-prefix"

  if ( LAST_COPY_FILE="$guard_file"; printf '%s' "$dir" >"$LAST_COPY_FILE"; last_copy ) 2>/dev/null; then
    rm -rf -- "$dir" "$guard_file"
    die "guard accepted an empty volume prefix"
  fi
  if ( LAST_COPY_FILE="$guard_file"; printf '%s' "/tmp" >"$LAST_COPY_FILE"; last_copy ) 2>/dev/null; then
    rm -rf -- "$dir" "$guard_file"
    die "guard accepted an unsafe copy path"
  fi
  rm -rf -- "$dir" "$guard_file"
  echo 'PASS: guard rejects unsafe prefixes and copy paths'
}

run_up() {
  local skip_post="${1:-}"
  local args=(--workspace-folder "$COPY" --remove-existing-container --frozen-lockfile)
  if [ -n "$skip_post" ]; then
    args+=(--skip-post-create)
  fi
  say "devcontainer up ${skip_post:+(--skip-post-create)}"
  local result cid
  if ! devcontainer up "${args[@]}" >"$COPY/up.stdout" 2>"$COPY/up.stderr"; then
    # The CLI may still report a containerId on failure; record it so cleanup
    # can remove the partial container.
    if result="$(parse_up_json "$COPY/up.stdout" 2>/dev/null)"; then
      cid="$(extract_container_id "$result" || true)"
      [ -n "$cid" ] && printf '%s' "$cid" >"$COPY/.dc-smoke-container-id"
    fi
    tail -80 "$COPY/up.stderr" >&2 || true
    tail -80 "$COPY/up.stdout" >&2 || true
    die "devcontainer up failed"
  fi
  if ! result="$(parse_up_json "$COPY/up.stdout")"; then
    tail -80 "$COPY/up.stderr" >&2 || true
    tail -80 "$COPY/up.stdout" >&2 || true
    die "could not parse devcontainer output"
  fi
  cid="$(python3 - "$result" <<'PY'
import json, sys
o = json.loads(sys.argv[1])
if o.get('outcome') != 'success':
    sys.exit(f'outcome={o.get("outcome")!r}: {o.get("message", "")}')
if not o.get('containerId'):
    sys.exit('no containerId in result')
print(o['containerId'])
PY
)"
  printf '%s' "$cid" >"$COPY/.dc-smoke-container-id"
  echo "PASS: devcontainer up, container ${cid:0:12}"
}

run_static() {
  say "T1 static contract"
  python3 - "$REPO" <<'PY'
import fnmatch, json, os, pathlib, re, sys
repo = pathlib.Path(sys.argv[1])
dc_path = repo / '.devcontainer' / 'devcontainer.json'
lock_path = repo / '.devcontainer' / 'devcontainer-lock.json'
dockerfile_path = repo / '.devcontainer' / 'Dockerfile'
post_path = repo / '.devcontainer' / 'post-create.sh'
errors = []

def check(cond, msg):
    if not cond:
        errors.append(msg)

try:
    dc = json.loads(dc_path.read_text())
    lock = json.loads(lock_path.read_text())
except Exception as e:
    print(f'FAIL: invalid JSON: {e}')
    sys.exit(1)

features = set(dc.get('features', {}))
locked = set(lock.get('features', {}))
check(features == locked, f'feature/lock mismatch: missing={sorted(features-locked)} extra={sorted(locked-features)}')
feature = 'ghcr.io/devcontainers/features/kubectl-helm-minikube:1'
check(feature not in features, f'{feature} must be absent from devcontainer.json features')
check(feature not in locked, f'{feature} must be absent from devcontainer-lock.json features')
check(dc.get('remoteUser') == 'developer', 'remoteUser must be developer')
check(dc.get('postCreateCommand') == 'bash .devcontainer/post-create.sh', 'postCreateCommand must run post-create.sh')
check(dc.get('waitFor') == 'postCreateCommand', 'waitFor must be postCreateCommand')
check((repo / '.devcontainer' / 'post-create.sh').is_file(), 'post-create.sh missing')

container_env = dc.get('containerEnv', {})
check(container_env.get('LANG') == 'en_US.UTF-8', 'containerEnv.LANG must be en_US.UTF-8')
check(container_env.get('LC_ALL') == 'en_US.UTF-8', 'containerEnv.LC_ALL must be en_US.UTF-8')
check(container_env.get('STARSHIP_CONFIG') == '/workspace/.devcontainer/starship.toml',
      'containerEnv.STARSHIP_CONFIG must point at the repo config')
check(container_env.get('EDITOR') == 'nvim', 'containerEnv.EDITOR must be nvim')
check(container_env.get('VISUAL') == 'nvim', 'containerEnv.VISUAL must be nvim')

remote_path = dc.get('remoteEnv', {}).get('PATH', '')
check('/home/developer/.opencode/bin' in remote_path, 'remoteEnv.PATH missing opencode bin')
check('/home/developer/.local/bin' in remote_path, 'remoteEnv.PATH missing local bin')
remote_kubeconfig = dc.get('remoteEnv', {}).get('KUBECONFIG', '')
check(remote_kubeconfig == '/home/developer/.kube/config',
      'remoteEnv.KUBECONFIG must be the container-local kubeconfig')
check('/workspace/.kube/config' not in remote_kubeconfig,
      'remoteEnv.KUBECONFIG must not include the VirtioFS workspace path')
check('OPENCODE_CONFIG' not in dc.get('remoteEnv', {}),
      'remoteEnv must not set OPENCODE_CONFIG; OpenCode discovers opencode.jsonc')
opencode_path = repo / 'opencode.jsonc'
check(opencode_path.is_file(), 'opencode.jsonc missing')

# --- opencode control plane ---
global_path = repo / '.opencode' / 'opencode.global.json'
check(global_path.is_file(), 'opencode.global.json missing')
if global_path.is_file():
    g = json.loads(global_path.read_text())
    check(g.get('default_agent') == 'orchestrator', 'default_agent must be orchestrator')
    check(g.get('model') == 'opencode-go/deepseek-v4.1-flash', 'default model mismatch')
    check(g.get('plugins') == ['/workspace/.opencode/superpowers'], 'local plugin path missing')
    check(g.get('experimental', {}).get('subagent_depth') == 1, 'subagent_depth must be 1')
    check(g.get('worktree', {}).get('directory') == '/workspace/repos/.worktrees', 'worktree directory mismatch')
    check(g.get('agents', {}).get('build', {}).get('disabled') is True, 'build must be disabled')
    check(g.get('agents', {}).get('plan', {}).get('disabled') is True, 'plan must be disabled')
    check('/workspace/.opencode/AGENTS.md' in g.get('instructions', []), 'AGENTS.md instruction missing')
    global_perms = g.get('permissions', [])
    def has_global_perm(action, resource, effect):
        return any(
            rule.get('action') == action
            and rule.get('resource') == resource
            and rule.get('effect') == effect
            for rule in global_perms)
    check(has_global_perm('mcp.use', '*', 'deny'),
          'global config must deny mcp.use *')
    check(has_global_perm('plugin.use', '*', 'deny'),
          'global config must deny plugin.use *')
    check(has_global_perm('plugin.use', '/workspace/.opencode/superpowers', 'allow'),
          'global config must allow the local Superpowers plugin')
    if global_perms:
        deny_index = global_perms.index({'action': 'plugin.use', 'resource': '*', 'effect': 'deny'}) \
            if {'action': 'plugin.use', 'resource': '*', 'effect': 'deny'} in global_perms else -1
        allow_index = global_perms.index(
            {'action': 'plugin.use', 'resource': '/workspace/.opencode/superpowers', 'effect': 'allow'}) \
            if {'action': 'plugin.use', 'resource': '/workspace/.opencode/superpowers', 'effect': 'allow'} in global_perms else -1
        check(deny_index != -1 and allow_index > deny_index,
              'global plugin allow must follow the plugin deny')

project = json.loads(opencode_path.read_text()) if opencode_path.is_file() else {}
check('plugins' not in project, 'opencode.jsonc must not load a plugin')
check('mcp' not in project, 'opencode.jsonc must not define MCP servers; use the host overlay')

for rel in (
    '.opencode/superpowers/index.js',
    '.opencode/superpowers/.opencode/plugins/superpowers.js',
    '.opencode/superpowers/skills/using-superpowers/SKILL.md',
    '.opencode/superpowers/LICENSE',
    '.opencode/superpowers/package.json',
    '.opencode/superpowers/UPSTREAM.md',
    '.opencode/superpowers.lock',
    '.opencode/superpowers-local.patch',
    'scripts/update-superpowers.sh',
    '.opencode/AGENTS.md',
):
    check((repo / rel).is_file(), f'{rel} missing')

lock_path = repo / '.opencode/superpowers.lock'
if lock_path.is_file():
    lock = lock_path.read_text()
    check('ref=v7.0.2' in lock, 'superpowers.lock must pin v7.0.2')
    check('commit=c62ffea8267a70de07583e153544d355b6748a56' in lock, 'superpowers.lock commit mismatch')

tdd_skill = repo / '.opencode' / 'superpowers' / 'skills' / 'test-driven-development' / 'SKILL.md'
check(tdd_skill.is_file(), 'vendored TDD skill missing')
if tdd_skill.is_file():
    tdd_text = tdd_skill.read_text()
    for url in (
        'https://newsletter.kentbeck.com/p/canon-tdd',
        'https://martinfowler.com/bliki/TestDrivenDevelopment.html',
        'https://www.jamesshore.com/v2/blog/2005/red-green-refactor',
    ):
        check(url in tdd_text,
              f'vendored TDD skill missing canonical reference {url}')

sdd_refs = repo / '.opencode' / 'superpowers' / 'skills' / 'subagent-driven-development' / 'references'
reviewer_prompt = (repo / '.opencode' / 'superpowers' / 'skills' /
                   'requesting-code-review' / 'code-reviewer.md')
vendored_prompts = (
    ('subagent-driven-development/references/fix-loop.md',
     sdd_refs / 'fix-loop.md'),
    ('subagent-driven-development/references/handling-reports.md',
     sdd_refs / 'handling-reports.md'),
    ('subagent-driven-development/references/final-review.md',
     sdd_refs / 'final-review.md'),
    ('requesting-code-review/code-reviewer.md', reviewer_prompt),
)
for rel, path in vendored_prompts:
    check(path.is_file(), f'{rel} missing')
    if path.is_file():
        text = path.read_text()
        for phrase in ('more capable model', 'most capable available model',
                       'Subagent (general-purpose):'):
            check(phrase not in text,
                  f'{rel} must not contain {phrase!r}')
if reviewer_prompt.is_file():
    check('agent: validator' in reviewer_prompt.read_text(),
          'code-reviewer.md must name agent: validator')

plugin_path = repo / '.opencode' / 'superpowers' / '.opencode' / 'plugins' / 'superpowers.js'
check(plugin_path.is_file(), 'vendored Superpowers plugin missing')
if plugin_path.is_file():
    plugin_text = plugin_path.read_text()
    check('agent: "general"' not in plugin_text,
          'Superpowers mapping must not dispatch agent: "general"')
    check('subagent_type: "general"' not in plugin_text,
          'Superpowers V1 mapping must not dispatch subagent_type: "general"')
    check('named control-plane agent' in plugin_text,
          'Superpowers mapping must name the control-plane agent')
for rel, agent in (('requesting-code-review/SKILL.md', 'validator'),
                   ('dispatching-parallel-agents/SKILL.md', 'implementer')):
    path = repo / '.opencode' / 'superpowers' / 'skills' / rel
    check(path.is_file(), f'vendored {rel} missing')
    if path.is_file():
        text = path.read_text()
        check(f'`{agent}`' in text or f'agent: {agent}' in text or f'{agent}:' in text,
              f'{rel} must name the control-plane agent {agent}')
        check('general-purpose' not in text,
              f'{rel} must not name a general-purpose subagent')

check('Superpowers' in (repo / 'NOTICE').read_text(), 'NOTICE must attribute Superpowers')
agents_text = (repo / '.opencode' / 'AGENTS.md').read_text()
check('enforced by policy' in agents_text,
      'AGENTS.md must say host-only MCP is enforced by policy')
check('trusted input' in agents_text,
      'AGENTS.md must say clone agent/skill definitions are trusted input')
check('Neither the\norchestrator nor an implementer may approve its own exception.' in agents_text,
      'AGENTS.md must require explicit user approval for TDD exceptions')
check('Read-only is a guardrail, not a sandbox' in agents_text,
      'AGENTS.md must say read-only is a guardrail, not a sandbox')
check('The plugin skips child sessions' in agents_text,
      'AGENTS.md must explain the worker bootstrap without a false plugin rationale')
check('# --- opencode control plane ---' in (repo / '.devcontainer/post-create.sh').read_text(),
      'post-create must install the control plane')

# Copy writer agent and vendored writing skills
opencode_config = repo / 'opencode.jsonc'
if opencode_config.is_file():
    config_text = opencode_config.read_text()
    check('elements-of-style@git' not in config_text,
          'opencode.jsonc must not load the Elements of Style plugin at runtime')
    check('technical-writer@git' not in config_text,
          'opencode.jsonc must not load a technical-writer plugin at runtime')

expected_skills = {
    'technical-writing', 'writing-design-docs', 'recording-decisions',
    'writing-changelogs', 'writing-runbooks', 'writing-issues',
    'writing-postmortems', 'documenting-legacy-codebases',
    'diagramming-processes', 'documenting-contracts',
    'reviewing-technical-prose', 'writing-clearly-and-concisely',
    'writing-commits-and-pull-requests',
}

copy_agent = repo / '.opencode' / 'agents' / 'copy-writer.md'
check(copy_agent.is_file(), 'copy-writer agent missing')
if copy_agent.is_file():
    agent_text = copy_agent.read_text()
    check('mode: subagent' in agent_text, 'copy-writer must be a subagent')
    check('model: opencode-go/deepseek-v4.1-flash' in agent_text,
          'copy-writer must use the approved model')
    check('This is a hard gate.' in agent_text,
          'copy-writer must state the skill-loading gate')
    check('SKILLS_LOADED:' in agent_text,
          'copy-writer must report loaded skills')
    check('  - action: edit\n    resource: "*"\n    effect: deny' in agent_text,
          'copy-writer must deny edits outside prose files')
    for skill_id in sorted(expected_skills):
        check(f'resource: "{skill_id}"' in agent_text,
              f'copy-writer must allow skill {skill_id}')
    for denied in ('.opencode/**', '.git/**', 'node_modules/**'):
        check(f'resource: "{denied}"' in agent_text,
              f'copy-writer must not edit {denied}')
    for server in ('parallel-search', 'brave-search-mcp-server'):
        check(f'action: "{server}_*"' in agent_text,
              f'copy-writer must deny MCP server {server}')
    check('resource: "*--output*"' in agent_text,
          'copy-writer must deny shell --output writes')
    check('resource: "*>*"' in agent_text,
          'copy-writer must deny shell redirection writes')
    check('resource: "*.excalidraw"' in agent_text,
          'copy-writer must allow Excalidraw source edits')
    check('resource: "scripts/render-excalidraw.sh *"' in agent_text,
          'copy-writer must allow the diagram renderer')

    permissions_text = agent_text.split('permissions:', 1)[1].split('\n---', 1)[0]
    permission_rules = []
    current = None
    for line in permissions_text.splitlines():
        m = re.match(r'\s*- action:\s*(.+?)\s*$', line)
        if m:
            current = {'action': m.group(1).strip().strip('"')}
            permission_rules.append(current)
            continue
        m = re.match(r'\s+resource:\s*(.+?)\s*$', line)
        if m and current is not None:
            current['resource'] = m.group(1).strip().strip('"')
            continue
        m = re.match(r'\s+effect:\s*(.+?)\s*$', line)
        if m and current is not None:
            current['effect'] = m.group(1).strip().strip('"')

    def effective(action, resource):
        result = 'allow'
        for rule in permission_rules:
            if (fnmatch.fnmatchcase(action, rule['action'])
                    and fnmatch.fnmatchcase(resource, rule['resource'])):
                result = rule['effect']
        return result

    permission_cases = [
        ('edit', 'README.md', 'allow'),
        ('edit', 'docs/guide.md', 'allow'),
        ('edit', 'src/app.py', 'deny'),
        ('edit', '.opencode/agents/copy-writer.md', 'deny'),
        ('shell', 'git diff --staged', 'allow'),
        ('shell', 'git diff --output=app.py', 'deny'),
        ('shell', 'git diff > app.py', 'deny'),
        ('shell', 'git commit -m x', 'deny'),
        ('edit', 'docs/diagrams/process.excalidraw', 'allow'),
        ('shell', 'scripts/render-excalidraw.sh docs/diagrams/process.excalidraw', 'allow'),
        ('skill', 'writing-commits-and-pull-requests', 'allow'),
        ('skill', 'run-research', 'deny'),
        ('parallel-search_web_search', '*', 'deny'),
        ('brave-search-mcp-server_brave_web_search', '*', 'deny'),
        ('experimental_image_generate', 'opencode-go/deepseek-v4.1-flash', 'deny'),
    ]
    for action, resource, expected in permission_cases:
        actual = effective(action, resource)
        check(actual == expected,
              f'permission matrix: {action} {resource} expected {expected}, got {actual}')

found_skills = {}
for skill_md in (repo / '.opencode' / 'skills').rglob('SKILL.md'):
    skill_id = skill_md.parent.name
    check(skill_id not in found_skills,
          f'duplicate skill id: {skill_id}')
    found_skills[skill_id] = skill_md
    text = skill_md.read_text()
    check(text.startswith('---\n'), f'{skill_md}: missing frontmatter')
    check('\nname:' in text, f'{skill_md}: missing frontmatter name')
    check('\ndescription:' in text, f'{skill_md}: missing frontmatter description')

for skill_id in sorted(expected_skills):
    check(skill_id in found_skills, f'missing skill: {skill_id}')

diagram_skill = repo / '.opencode' / 'skills' / 'diagramming-processes'
check(diagram_skill.is_dir(), 'local diagramming-processes skill missing')
for rel in ('SKILL.md', 'LICENSE', 'UPSTREAM.md',
            'references/excalidraw-schema.md', 'references/element-types.md',
            'templates/flowchart.excalidraw', 'templates/sequence.excalidraw',
            'templates/swimlane.excalidraw'):
    check((diagram_skill / rel).is_file(),
          f'diagramming-processes missing {rel}')
for png in ('flowchart.png', 'sequence.png', 'swimlane.png'):
    path = diagram_skill / 'templates' / png
    check(path.is_file() and path.stat().st_size > 1000,
          f'diagramming-processes missing render {png}')

flowchart = diagram_skill / 'templates' / 'flowchart.excalidraw'
if flowchart.is_file():
    data = json.loads(flowchart.read_text())
    elements = {e['id']: e for e in data.get('elements', [])}
    arrows = [e for e in elements.values() if e.get('type') == 'arrow']
    check(len(arrows) >= 3, 'flowchart must have arrows')
    for arrow in arrows:
        start = arrow.get('startBinding') or {}
        end = arrow.get('endBinding') or {}
        check(start.get('elementId'),
              f'flowchart arrow {arrow["id"]} missing start binding')
        check(end.get('elementId'),
              f'flowchart arrow {arrow["id"]} missing end binding')

swimlane = diagram_skill / 'templates' / 'swimlane.excalidraw'
if swimlane.is_file():
    swimlane_data = json.loads(swimlane.read_text())
    for element in swimlane_data.get('elements', []):
        if element.get('type') == 'arrow':
            start = element.get('startBinding') or {}
            end = element.get('endBinding') or {}
            check(start.get('elementId') and end.get('elementId'),
                  f'swimlane arrow {element["id"]} missing a shape binding')

for template, minimum in (('flowchart', 2), ('sequence', 4), ('swimlane', 3)):
    path = diagram_skill / 'templates' / f'{template}.excalidraw'
    if not path.is_file():
        continue
    template_data = json.loads(path.read_text())
    active = [e for e in template_data.get('elements', [])
              if not e.get('isDeleted')]
    by_id = {e['id']: e for e in active}
    arrow_ids = {e['id'] for e in active if e.get('type') == 'arrow'}
    for arrow in (e for e in active if e.get('type') == 'arrow'):
        for bound in arrow.get('boundElements') or []:
            if bound.get('type') == 'text':
                label = by_id.get(bound.get('id'))
                check(label is not None and label.get('containerId') == arrow['id'],
                      f'{template} arrow label {bound.get("id")} not bound to {arrow["id"]}')
    arrow_labels = [e for e in active if e.get('type') == 'text'
                    and e.get('containerId') in arrow_ids]
    check(len(arrow_labels) >= minimum,
          f'{template} must bind at least {minimum} arrow labels')

if (diagram_skill / 'SKILL.md').is_file():
    diagram_text = (diagram_skill / 'SKILL.md').read_text()
    for marker in ('Excalidraw is the only diagram tool', 'fontFamily: 5',
                   'scripts/render-excalidraw.sh', '.excalidraw', '.png'):
        check(marker in diagram_text,
              f'diagramming-processes missing {marker}')

check((repo / '.opencode' / 'skills' / 'technical-writer' / 'LICENSE').is_file(),
      'technical-writer LICENSE missing')
upstream_pins = {
    repo / '.opencode' / 'skills' / 'technical-writer' / 'UPSTREAM.md':
        '85e53729dd959a2795d593d6769068e342cf3486',
    repo / '.opencode' / 'skills' / 'elements-of-style' / 'UPSTREAM.md':
        '05fc4f0d2b97b7c042dd9949ad658568e4a1324e',
}
for upstream, pin in upstream_pins.items():
    check(upstream.is_file(), f'{upstream}: missing')
    if upstream.is_file():
        check(pin in upstream.read_text(), f'{upstream}: missing pinned commit')

eos_ref = (repo / '.opencode' / 'skills' / 'elements-of-style' /
           'writing-clearly-and-concisely' / 'elements-of-style.md')
check(eos_ref.is_file() and eos_ref.stat().st_size > 50000,
      'Elements of Style reference is missing or truncated')
notice_path = repo / 'NOTICE'
check(notice_path.is_file(), 'NOTICE missing')
if notice_path.is_file():
    notice_text = notice_path.read_text()
    check('awesome-copilot' in notice_text,
          'NOTICE missing awesome-copilot attribution')
    check('@excalidraw/cli' in notice_text,
          'NOTICE missing renderer attribution')
    check('Firefox' in notice_text,
          'NOTICE missing Firefox attribution')

readme_path = repo / 'README.md'
check(readme_path.is_file(), 'README.md missing')
if readme_path.is_file():
    readme_text = readme_path.read_text()
    for marker in ('### Copy writer subagent', 'riekelt/technical-writer',
                   'obra/the-elements-of-style', '#### Diagrams',
                   'render-excalidraw.sh', 'diagramming-processes'):
        check(marker in readme_text, f'README.md missing {marker}')
    check('### Host MCP and agent overrides' in readme_text,
          'README.md missing the Host MCP and agent overrides section')
    check('~/.devcontainer/opencode/opencode.json' in readme_text,
          'README.md must say Parallel and Brave are configured in the host overlay')
    check('/etc/opencode' in readme_text,
          'README.md must document the host-only MCP overlay at /etc/opencode')
    check('enforced by policy' in readme_text,
          'README.md must say host-only MCP is enforced by policy')
    check('trusted input' in readme_text,
          'README.md must say clone agent/skill definitions are trusted input')
    check('@brave/brave-search-mcp-server@2.1.5' in readme_text,
          'README.md must pin the Brave MCP package')
    check('a guardrail, not a sandbox' in readme_text,
          'README.md must say read-only is a guardrail, not a sandbox')
    check('Three read-only bind mounts' in readme_text,
          'README.md must not claim only two read-only bind mounts')
    check('`/etc/opencode` to be mounted and read-only' in readme_text,
          'README.md smoke-real note must mention the /etc/opencode overlay')

    def readme_section(heading):
        start = readme_text.find(heading)
        if start == -1:
            return None
        rest = readme_text[start + len(heading):]
        following = re.search(r'(?m)^#{3} ', rest)
        return rest[:following.start()] if following else rest

    control_section = readme_section('### Control plane and agent workflow')
    check(control_section is not None,
          'README.md missing the Control plane and agent workflow section')
    if control_section is not None:
        for role in ('orchestrator', 'research', 'copy-writer', 'design',
                     'rubber-duck', 'task-enumerator', 'implementer',
                     'validator', 'security-reviewer'):
            check(role in control_section,
                  f'README.md control plane section must name {role}')

    model_section = readme_section('### Change an agent model')
    check(model_section is not None,
          'README.md missing the Change an agent model section')
    if model_section is not None:
        for marker in ('model:', 'test/devcontainer-smoke.sh', 'same change'):
            check(marker in model_section,
                  f'README.md model section missing {marker!r}')

    tdd_section = readme_section('### Test-driven development')
    check(tdd_section is not None,
          'README.md missing the Test-driven development section')
    if tdd_section is not None:
        for marker in ('red-green-refactor', 'explicit user approval'):
            check(marker in tdd_section,
                  f'README.md TDD section missing {marker!r}')

    for command in ('scripts/update-superpowers.sh --check',
                    'scripts/update-writing-skills.sh --check'):
        check(command in readme_text,
              f'README.md missing update command {command!r}')

    code_review_skill = repo / '.opencode' / 'skills' / 'code-review' / 'SKILL.md'
    check(code_review_skill.is_file(), 'code-review skill missing')
    if code_review_skill.is_file():
        banned = 'Ask the orchestrator for anything missing before you start.'
        check(banned not in code_review_skill.read_text(),
              'code-review skill must not tell reviewers to ask the orchestrator before starting')

    orchestration_skill = repo / '.opencode' / 'skills' / 'orchestration' / 'SKILL.md'
    check(orchestration_skill.is_file(), 'orchestration skill missing')
    if orchestration_skill.is_file():
        orchestration_text = orchestration_skill.read_text()
        check('readlink -f' in orchestration_text and 'symlink' in orchestration_text,
              'orchestration skill must resolve copy-writer paths and reject symlinks')

update_script = repo / 'scripts' / 'update-writing-skills.sh'
check(update_script.is_file(), 'writing skills update script missing')
if update_script.is_file():
    script_text = update_script.read_text()
    for pin in upstream_pins.values():
        check(pin in script_text, f'update script missing pinned commit {pin}')
    check('TW_EXCLUDE="diagramming-processes"' in script_text,
          'update script must exclude the local diagramming skill')
    check('--exclude "$TW_EXCLUDE"' in script_text,
          'update script --check must exclude the local diagramming skill')
    tw_rm_lines = [line.strip() for line in script_text.splitlines()
                   if 'rm -rf' in line and 'TW_DEST' in line]
    check(tw_rm_lines == ['rm -rf "$TW_DEST"/*/',
                          'rm -rf "$TW_DEST/$TW_EXCLUDE"'],
          f'update script must remove only vendored skill directories: {tw_rm_lines}')
    eos_rm_lines = [line.strip() for line in script_text.splitlines()
                    if 'rm -rf' in line and 'EOS_DEST' in line]
    check(not eos_rm_lines,
          f'update script must not remove the EOS tree: {eos_rm_lines}')
    check('cp "$tmp/elements-of-style/skills/writing-clearly-and-concisely/elements-of-style.md"' in script_text,
          'update script must copy only the EOS reference text')

renderer = repo / 'scripts' / 'render-excalidraw.sh'
check(renderer.is_file(), 'Excalidraw renderer missing')
if renderer.is_file():
    renderer_text = renderer.read_text()
    check('0.3.0' in renderer_text, 'Excalidraw renderer must pin 0.3.0')
    check('@excalidraw/cli' in renderer_text,
          'Excalidraw renderer must use the official CLI')
    check('--scale' in renderer_text, 'Excalidraw renderer must set a scale')
    check('--out' in renderer_text, 'Excalidraw renderer must set an output path')
    check('--browser-path' in renderer_text,
          'Excalidraw renderer must pass the browser path')

for mount in dc.get('mounts', []):
    m = dict(part.split('=', 1) for part in mount.split(',') if '=' in part)
    target = m.get('target') or m.get('dst') or ''
    check(target.startswith('/home/developer') or target == '/etc/opencode',
          f'mount target outside developer home: {target}')
    check('/home/vscode' not in target, f'vscode mount target: {target}')
check(any('source=kubeconfig' in mount and 'target=/home/developer/.kube' in mount
          for mount in dc.get('mounts', [])),
      'devcontainer.json must mount the kubeconfig volume at /home/developer/.kube')

# --- host MCP overlay ---
check(dc.get('initializeCommand') == 'bash .devcontainer/host-init.sh',
      'initializeCommand must run bash .devcontainer/host-init.sh')
check(dc.get('updateRemoteUserUID') is True,
      'updateRemoteUserUID must be true')
overlay_mounts = []
for mount in dc.get('mounts', []):
    parts = mount.split(',')
    m = dict(part.split('=', 1) for part in parts if '=' in part)
    target = m.get('target') or m.get('dst') or ''
    if target == '/etc/opencode':
        overlay_mounts.append((parts, m))
check(len(overlay_mounts) == 1,
      'devcontainer.json must mount the host overlay at /etc/opencode once')
if overlay_mounts:
    parts, m = overlay_mounts[0]
    check((m.get('src') or m.get('source')) == '${localEnv:HOME}/.devcontainer/opencode',
          'host overlay mount must use the host config directory')
    check(m.get('type') == 'bind', 'host overlay mount must be a bind mount')
    check('ro' in parts, 'host overlay mount must be read-only')
    check('bind-create-src' not in parts,
          'host overlay mount must not use bind-create-src')

host_init = repo / '.devcontainer' / 'host-init.sh'
check(host_init.is_file(), 'host-init.sh missing')
example_dir = repo / '.devcontainer' / 'examples' / 'opencode'
example_config = example_dir / 'opencode.json'
example_agent = example_dir / 'agents' / 'research.md'
check(example_config.is_file(), 'host overlay example opencode.json missing')
check(example_agent.is_file(), 'host overlay example research.md missing')
if example_config.is_file():
    example_text = example_config.read_text()
    for server in ('parallel-search', 'brave-search-mcp-server'):
        check(f'"{server}"' in example_text,
              f'host overlay example must define {server}')
    example = json.loads(example_text)
    example_perms = example.get('permissions', [])
    for server in ('parallel-search', 'brave-search-mcp-server'):
        check(any(rule.get('action') == 'mcp.use'
                  and rule.get('resource') == server
                  and rule.get('effect') == 'allow'
                  for rule in example_perms),
              f'host overlay example must allow mcp.use {server}')
    brave = example.get('mcp', {}).get('servers', {}).get('brave-search-mcp-server', {})
    check('@brave/brave-search-mcp-server@2.1.5' in brave.get('command', []),
          'host overlay example must pin @brave/brave-search-mcp-server@2.1.5')
if example_agent.is_file():
    check('description:' in example_agent.read_text(),
          'host overlay example research override must define a description')

smoke_text = (repo / 'test' / 'devcontainer-smoke.sh').read_text()
overlay_heredoc = re.search(
    r'cat >"\$COPY/host-opencode/opencode\.json" <<\'JSON\'\n(.*?)\nJSON',
    smoke_text, re.S)
check(overlay_heredoc is not None, 'hermetic host overlay heredoc missing')
if overlay_heredoc:
    heredoc = overlay_heredoc.group(1)
    check('"disabled": true' in heredoc,
          'hermetic host overlay probe must use "disabled": true')
    check('"enabled":' not in heredoc,
          'hermetic host overlay probe must not use "enabled":')
    overlay_json = json.loads(heredoc)
    overlay_perms = overlay_json.get('permissions', [])
    check(any(rule.get('action') == 'mcp.use'
              and rule.get('resource') == 'probe-disabled'
              and rule.get('effect') == 'allow'
              for rule in overlay_perms),
          'hermetic host overlay must allow mcp.use probe-disabled')
run_smoke_pos = smoke_text.find('\nrun_smoke() {')
smoke_body = smoke_text[run_smoke_pos:] if run_smoke_pos != -1 else ''
marker_pos = smoke_body.find('/workspace/.dc-smoke-prefix')
guard_pos = smoke_body.find('if [ "$hermetic" -eq 1 ]')
desc_pos = smoke_body.find('Host test research override')
probe_pos = smoke_body.find('check "host overlay: probe-disabled listed"')
gate_end_pos = smoke_body.find('check "host overlay: /etc/opencode read-only"')
repo_clone_pos = smoke_body.find('repo clone: local remote')
repo_worktree_pos = smoke_body.find('repo worktree: path exists')
check(marker_pos != -1, 'run_smoke must detect the disposable copy marker')
check(guard_pos != -1 and marker_pos < guard_pos,
      'run_smoke must gate hermetic checks on the disposable copy')
check(guard_pos != -1 and desc_pos > guard_pos,
      'research override assertion must be inside the hermetic gate')
for marker in ("research.get('system'", 'Host test research override body',
               'research/host/**', "research.get('model'"):
    check(marker in smoke_body,
          f'host override test must assert {marker!r}')
check(guard_pos != -1 and probe_pos > guard_pos,
      'probe-disabled assertion must be inside the hermetic gate')
check(guard_pos != -1 and gate_end_pos != -1 and guard_pos < repo_clone_pos < gate_end_pos,
      'repo clone test must be inside the disposable-copy gate')
check(guard_pos != -1 and gate_end_pos != -1 and guard_pos < repo_worktree_pos < gate_end_pos,
      'repo worktree test must be inside the disposable-copy gate')
check('hermetic repo remote missing' not in smoke_body,
      'repo test must skip, not fail, when the hermetic remote is absent')
check('cd "$clone_dir" && opencode --standalone debug agents' in smoke_body,
      'clone inheritance test must run OpenCode from the clone')
check('clone inheritance: global link' in smoke_body
      and '$HOME/.config/opencode/' in smoke_body,
      'clone inheritance test must assert the global agent symlink')

copy_start = smoke_text.find('prepare_copy() {')
copy_end = smoke_text.find('\n}\n\nlast_copy() {', copy_start)
copy_body = smoke_text[copy_start:copy_end] if copy_start != -1 and copy_end != -1 else ''
check(copy_body != '', 'prepare_copy function missing')
if copy_body:
    copy_lines = copy_body.splitlines()
    rsync_line = next((line for line in copy_lines if re.match(r'\s*rsync\b', line)), '')
    tar_line = next((line for line in copy_lines if re.search(r'\btar\b', line)
                     and '--exclude' in line), '')
    check('--exclude repos' in rsync_line,
          'prepare_copy rsync must exclude repos/')
    check('--exclude repos' in tar_line,
          'prepare_copy tar fallback must exclude repos/')
    check('${localEnv:HOME}' not in copy_body,
          'prepare_copy must not leave ${localEnv:HOME} bind mounts in the copy')
    check("target == '/home/developer/.dc/github'" in copy_body,
          'prepare_copy must rewrite the GitHub credential mount')
    check("target == '/home/developer/.dc/brave/.env'" in copy_body,
          'prepare_copy must rewrite the Brave credential mount')
    check('$COPY/host-github' in copy_body,
          'prepare_copy must create a disposable GitHub fixture')
    check('$COPY/host-brave.env' in copy_body,
          'prepare_copy must create a disposable Brave fixture')

dockerfile = dockerfile_path.read_text()
check(re.search(r'useradd\b[^\n]*--shell\s+/bin/bash', dockerfile) is not None,
      'Dockerfile useradd must set --shell /bin/bash')
apt_block = re.search(r'(?ms)^RUN apt-get update.*?rm -rf /var/lib/apt/lists/\*', dockerfile)
check(apt_block is not None, 'Dockerfile apt package block not found')
if apt_block:
    for pkg in ('libatomic1', 'openssh-client', 'openssl', 'firefox-esr', 'ripgrep', 'less',
                'locales', 'unzip', 'zip', 'bash-completion', 'python3', 'python3-venv', 'pipx'):
        check(re.search(rf'(?m)^\s*{re.escape(pkg)}\s*(?:\\\s*)?$', apt_block.group(0)) is not None,
              f'Dockerfile apt package block must install {pkg}')
check(re.search(r'^ENV LANG=en_US\.UTF-8', dockerfile, re.M) is not None,
      'Dockerfile must set ENV LANG=en_US.UTF-8')
check('chown -R $USERNAME:$USERNAME' in dockerfile,
      'Dockerfile must chown pre-created volume mount targets')
check('/home/$USERNAME/.local' in dockerfile and '/home/$USERNAME/.config' in dockerfile,
      'Dockerfile must chown the .local and .config parents')
chown_block = re.search(r'chown -R \$USERNAME:\$USERNAME(.*?)(?:\n\s*&&|\n\n)', dockerfile, re.S)
check(chown_block is None or '/worktrees' not in chown_block.group(0),
      'Dockerfile must not chown /worktrees')
check('ln -s /workspace/repos /worktrees' in dockerfile,
      'Dockerfile must link /worktrees to /workspace/repos')
check(not re.search(r'(?m)^\s*/worktrees\s*\\?\s*$', dockerfile),
      'Dockerfile must not pre-create /worktrees as a directory')
for arg in ('NVIM_VERSION', 'STARSHIP_VERSION', 'GLOW_VERSION',
            'KUBECTL_VERSION', 'HELM_VERSION',
            'GLOW_SHA256_AMD64', 'GLOW_SHA256_ARM64',
            'KUBECTL_SHA256_AMD64', 'KUBECTL_SHA256_ARM64',
            'HELM_SHA256_AMD64', 'HELM_SHA256_ARM64'):
    check(re.search(rf'^ARG {re.escape(arg)}=\S+', dockerfile, re.M) is not None,
          f'Dockerfile must pin {arg}')
for arg in ('GLOW_SHA256_AMD64', 'GLOW_SHA256_ARM64',
            'KUBECTL_SHA256_AMD64', 'KUBECTL_SHA256_ARM64',
            'HELM_SHA256_AMD64', 'HELM_SHA256_ARM64'):
    digest = re.search(rf'^ARG {re.escape(arg)}=(\S+)\s*$', dockerfile, re.M)
    check(digest is not None and re.fullmatch(r'[0-9a-f]{64}', digest.group(1)) is not None,
          f'Dockerfile {arg} must be 64-character lowercase hex')
check(re.search(r'dl\.k8s\.io/release/\$\{KUBECTL_VERSION\}/bin/linux/\$\{arch\}/kubectl', dockerfile) is not None,
      'Dockerfile must download kubectl from dl.k8s.io with ${KUBECTL_VERSION} and ${arch}')
helm_url = re.search(
    r'https://get\.helm\.sh/(?:\$helm_asset|helm-\$\{HELM_VERSION\}-linux-\$\{arch\}\.tar\.gz)',
    dockerfile)
check(helm_url is not None
      and re.search(r'helm-\$\{HELM_VERSION\}-linux-\$\{arch\}\.tar\.gz', dockerfile) is not None,
      'Dockerfile must download the canonical Helm tarball from get.helm.sh with ${HELM_VERSION} and ${arch}')
check(dockerfile.count('sha256sum --strict -c -') >= 3,
      'Dockerfile must verify kubectl, Helm, and Glow downloads with sha256sum --strict -c -')
check("printf '%s  kubectl\\n'" in dockerfile,
      'Dockerfile must synthesize the kubectl checksum line')
check("printf '%s  %s\\n'" in dockerfile,
      'Dockerfile must synthesize the Helm checksum line')
check('nvim-linux-${nvim_arch}.tar.gz' in dockerfile, 'Dockerfile must install Neovim')
check('starship.rs/install.sh' in dockerfile, 'Dockerfile must install Starship')
check(re.search(r'https://github\.com/charmbracelet/glow/releases/download/\$\{GLOW_VERSION\}/\$glow_asset', dockerfile) is not None,
      'Dockerfile must download the Glow release tarball with ${GLOW_VERSION}')
check('glow_${glow_version}_Linux_${glow_arch}.tar.gz' in dockerfile,
      'Dockerfile must use the canonical Glow asset name')
check('amd64) glow_arch=x86_64' in dockerfile and 'arm64) glow_arch=arm64' in dockerfile,
      'Dockerfile must map amd64/arm64 to the Glow release architectures')
check('Unsupported architecture for Glow' in dockerfile,
      'Dockerfile must reject unsupported architectures for Glow')
check('glow --version' in dockerfile, 'Dockerfile must print the Glow version')
check('SPECIFY_VERSION' not in dockerfile, 'Dockerfile must not pin SPECIFY_VERSION')
check('specify' not in dockerfile.lower(), 'Dockerfile must not install Spec Kit')
check('spec-kit' not in dockerfile.lower(), 'Dockerfile must not mention Spec Kit')

post = post_path.read_text()
check('# --- opencode host secrets ---' in post,
      'post-create.sh missing opencode host secrets marker')
check('{file:' in post, 'post-create.sh must validate {file:...} host secrets')
check('done < <(' in post,
      'post-create.sh secret validation must use process substitution')
check('vscode' not in post.lower(), 'post-create.sh still references vscode')
check('YQ_VERSION' not in post, 'post-create.sh should not reinstall yq')
check('export $(' not in post, 'post-create.sh uses unsafe export $(...)')
check('[ -f "$GITHUB_ENV_FILE" ]' in post, 'post-create.sh must use -f for env files')
check('# --- github env ---' in post, 'post-create.sh missing github env marker')
check('# --- brave env ---' in post, 'post-create.sh missing brave env marker')
check('chown -R --no-dereference "$DEV_USER:$DEV_USER" "$HOME/.local" "$HOME/.config" "$HOME/.kube"' in post,
      'post-create.sh must chown .local, .config, and .kube to the runtime user')
chown_line = re.search(r'chown -R --no-dereference.*', post)
check(chown_line is not None and '/worktrees' not in chown_line.group(0),
      'post-create.sh must not chown /worktrees')
check('specify' not in post.lower(), 'post-create.sh must not verify Spec Kit')
check('glow --version' in post, 'post-create.sh must verify Glow')
check('yq --version' in post, 'post-create.sh must verify yq')
check('# --- helm completion ---' in post, 'post-create.sh missing helm completion marker')
check('helm completion bash' in post, 'post-create.sh must set up helm completion')
check('kubectl version --client' in post, 'post-create.sh must verify kubectl')
check("helm version --template '{{.Version}}'" in post,
      'post-create.sh must verify the exact Helm version')
check(post.find('# --- helm completion ---') > post.find('# --- kubectl aliases ---'),
      'helm completion must be a separate block after the kubectl block')
check('touch "$HOME/.kube/config"' in post,
      'post-create.sh must create the container-local kubeconfig')
check('chmod 600 "$HOME/.kube/config"' in post,
      'post-create.sh must secure the container-local kubeconfig')
check('rm -f "$HOME/.kube/config.lock"' in post,
      'post-create.sh must remove stale kubeconfig lock files')
check('# --- devcontainer aliases ---' in post, 'post-create.sh must load the aliases config')
check('# --- terminal paste ---' in post, 'post-create.sh must harden terminal paste handling')
check('# --- starship prompt ---' in post, 'post-create.sh must load the Starship prompt')
check((repo / '.devcontainer' / 'aliases.sh').is_file(), 'aliases.sh missing')
check((repo / '.devcontainer' / 'starship.toml').is_file(), 'starship.toml missing')

github_mounts = []
for mount in dc.get('mounts', []):
    parts = mount.split(',')
    m = dict(part.split('=', 1) for part in parts if '=' in part)
    target = m.get('target') or m.get('dst') or ''
    if target == '/home/developer/.dc/github':
        github_mounts.append((parts, m))
check(len(github_mounts) == 1, 'devcontainer.json must mount the GitHub credential directory once')
if github_mounts:
    parts, m = github_mounts[0]
    check((m.get('src') or m.get('source')) == '${localEnv:HOME}/.devcontainer/github',
          'GitHub credential mount must use the host directory')
    check(m.get('type') == 'bind', 'GitHub credential mount must be a bind mount')
    check('ro' in parts, 'GitHub credential mount must be read-only')
    check('bind-create-src' in parts, 'GitHub credential mount must use bind-create-src')
check(not any('/.dc/github/.env' in mount for mount in dc.get('mounts', [])),
      'GitHub mount must be the directory, not the single .env file')

for name in ('gh-app-token', 'gh-app'):
    helper = repo / '.devcontainer' / 'bin' / name
    check(helper.is_file(), f'{name} missing')
    check(os.access(helper, os.X_OK), f'{name} must be executable')

if apt_block:
    check(re.search(r'(?m)^\s*openssl\s*(?:\\\s*)?$', apt_block.group(0)) is not None,
          'Dockerfile apt package block must install openssl')
check('for helper in gh-app-token gh-app' in post,
      'post-create.sh must install both GitHub App helpers')
check('ln -sfn "$src" "$HOME/.local/bin/$helper"' in post,
      'post-create.sh must symlink the helpers into ~/.local/bin')

# --- multi-repo workspace ---
gitignore_path = repo / '.gitignore'
check(gitignore_path.is_file(), '.gitignore missing')
if gitignore_path.is_file():
    ignore_lines = set(gitignore_path.read_text().splitlines())
    check('/repos/' in ignore_lines, '.gitignore must contain /repos/')
    check('/.superpowers/' in ignore_lines, '.gitignore must keep /.superpowers/')

check(not any('source=worktrees' in mount for mount in dc.get('mounts', [])),
      'devcontainer.json must not mount the worktrees volume')
check(not any((dict(part.split('=', 1) for part in mount.split(',') if '=' in part).get('target')
               or dict(part.split('=', 1) for part in mount.split(',') if '=' in part).get('dst'))
              == '/worktrees' for mount in dc.get('mounts', [])),
      'devcontainer.json must not mount anything at /worktrees')

check('mkdir -p /workspace/repos' in post,
      'post-create.sh must create /workspace/repos')
check('mountpoint -q /worktrees' in post,
      'post-create.sh must guard an old /worktrees mountpoint')
check(re.search(r'ln\s+-s(?:f)?n?\s+/workspace/repos\s+/worktrees', post) is not None,
      'post-create.sh must link /worktrees to /workspace/repos')
check('ln -sfn "$src" "$HOME/.local/bin/repo"' in post,
      'post-create.sh must symlink the repo helper into ~/.local/bin')

smoke_text = (repo / 'test' / 'devcontainer-smoke.sh').read_text()
repo_helper = repo / '.devcontainer' / 'bin' / 'repo'
check(repo_helper.is_file(), '.devcontainer/bin/repo missing')
check(os.access(repo_helper, os.X_OK), '.devcontainer/bin/repo must be executable')
if repo_helper.is_file():
    repo_text = repo_helper.read_text()
    for marker in ('set -euo pipefail',
                   'ROOT="${REPO_ROOT:-/workspace/repos}"',
                   'check >/dev/null',
                   'git-credential',
                   'pr checkout',
                   'git worktree add'):
        check(marker in repo_text, f'repo helper must contain {marker!r}')
    for marker in ('validate_component', 'validate_slug', 'ensure_under',
                   'ensure_root', 'realpath -m', 'warn_clone_config',
                   'readlink -f', 'GITHUB_APP_ENV_FILE'):
        check(marker in repo_text,
              f'repo helper must validate paths and env with {marker!r}')
    for marker in ('repo worktree ../escape', 'repo fork upstream/repo ..',
                   'repo clone ../repo', 'repo pr --detach'):
        check(marker in smoke_text,
              f'smoke test must include the negative repo case {marker!r}')

check('file:///workspace/test-remote.git' in smoke_text,
      'smoke test must clone the hermetic repo remote')
check('repo worktree' in smoke_text, 'smoke test must exercise repo worktree')
if readme_path.is_file():
    check('GITHUB_APP_ENV_FILE' in readme_text,
          'README.md must document GITHUB_APP_ENV_FILE for repo and gh-app-token')
    check('repo helper reads `GITHUB_APP_ENV_FILE` first' in readme_text,
          'README.md must say the repo helper reads GITHUB_APP_ENV_FILE first')

if readme_path.is_file():
    for marker in ('Working with multiple repositories',
                   'repo clone dzmoore/provider-confluent --upstream crossplane-contrib/provider-confluent',
                   'repo switch', 'repo pr', 'repo worktree',
                   'git worktree repair', '/worktrees'):
        check(marker in readme_text, f'README.md missing multi-repo marker {marker!r}')
    check('| `worktrees` |' not in readme_text,
          'README.md persistent volumes table must not list worktrees')
    check('cp -R /tmp/devcontainer-base/.opencode/. .opencode/' in readme_text,
          'README.md copy flow must copy .opencode/')
    check('cp -R /tmp/devcontainer-base/.devcontainer/. .devcontainer/' in readme_text,
          'README.md copy flow must copy .devcontainer/ alongside .opencode/')
    check('degit' not in readme_text
          or 'npx degit dzmoore/devcontainer-base/.opencode .opencode' in readme_text,
          'README.md degit tip must copy .opencode or be absent')

# --- timezone contract ---
container_tz = container_env.get('TZ')
tz_template = '${localEnv:DEVCONTAINER_TZ:America/Los_Angeles}'
check(container_tz == tz_template or (
    container_tz is not None and re.fullmatch(
        r'[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*', str(container_tz)) is not None),
    'containerEnv.TZ must be the DEVCONTAINER_TZ template or an IANA zone name')
check('TZ' not in dc.get('remoteEnv', {}),
      'remoteEnv must not set TZ; use containerEnv.TZ or the image default')

arg_tz = re.search(r'^ARG TZ=(\S+)\s*$', dockerfile, re.M)
check(arg_tz is not None, 'Dockerfile must define ARG TZ')
if arg_tz:
    check(arg_tz.group(1) == 'America/Los_Angeles',
          f'Dockerfile ARG TZ must default to America/Los_Angeles (got {arg_tz.group(1)})')
check(re.search(r'^ENV\s+TZ=\$\{?TZ\}?\s*$', dockerfile, re.M) is not None,
      'Dockerfile must export TZ from the TZ ARG')
if apt_block:
    check(re.search(r'(?m)^\s*tzdata\s*(?:\\\s*)?$', apt_block.group(0)) is not None,
          'Dockerfile apt package block must install tzdata')
check(re.search(r'zone="/usr/share/zoneinfo/\$\{?TZ\}?"', dockerfile) is not None,
      'Dockerfile must assign the zone path to $zone')
check(re.search(r'test\s+-f\s+"?\$\{?zone\}?"?', dockerfile) is not None,
      'Dockerfile must require a regular zone file for TZ')
check(re.search(r'ln\s+-s[nf]{2}\s+"?\$\{?zone\}?"?\s+/etc/localtime',
                dockerfile) is not None,
      'Dockerfile must link /etc/localtime to the configured zone')
check('Invalid TZ' in dockerfile, 'Dockerfile must reject invalid TZ values')
check(re.search(r'head\s+-c\s+4\s+"\$resolved"', dockerfile) is not None,
      'Dockerfile must check the TZif magic header')
check('/usr/share/zoneinfo/*)' in dockerfile,
      'Dockerfile must require the resolved zone inside /usr/share/zoneinfo')
check(re.search(r'printf[^\n]*\$TZ[^\n]*>\s*/etc/timezone', dockerfile) is not None,
      'Dockerfile must write /etc/timezone')

check('# --- timezone ---' in post, 'post-create.sh missing timezone block')
check('Invalid TZ' in post, 'post-create.sh must reject invalid zones')
check('[ ! -f "$zone" ]' in post,
      'post-create.sh must require a regular zone file, not test -e')
check('sudo -n ln -sfn "$zone" /etc/localtime' in post,
      'post-create.sh must apply the zone with sudo -n')
check(re.search(r'head\s+-c\s+4\s+"\$resolved"', post) is not None,
      'post-create.sh must check the TZif magic header')
check('/usr/share/zoneinfo/*)' in post,
      'post-create.sh must require the resolved zone inside /usr/share/zoneinfo')
check(re.search(r'printf[^\n]*\$TZ[^\n]*tee\s+/etc/timezone', post) is not None,
      'post-create.sh must write /etc/timezone')

# --- timezone hardening ---
check('wc -l' in dockerfile,
      'Dockerfile must reject multiline TZ values with wc -l')
check('readlink -f' in dockerfile,
      'Dockerfile must resolve zone targets with readlink -f')
check('TZif' in dockerfile,
      'Dockerfile must require the TZif magic header')
check('localtime|leapseconds|posixrules' in dockerfile,
      'Dockerfile must deny non-zone entries (localtime|leapseconds|posixrules)')

check('[ -d /etc/localtime ]' in post,
      'post-create.sh must refuse to replace a directory /etc/localtime')
check('readlink -f -- "$zone"' in post or 'resolved=' in post,
      'post-create.sh must resolve the zone target with readlink -f -- or resolved=')
check('TZif' in post,
      'post-create.sh must require the TZif magic header')
check('localtime|leapseconds|posixrules' in post,
      'post-create.sh must deny non-zone entries (localtime|leapseconds|posixrules)')

tz_marker = post.find('# --- timezone ---')
for_dir = post.find('for dir in')
check(tz_marker != -1 and for_dir != -1 and tz_marker < for_dir,
      'timezone validation must run before directory creation')
zone_guard = post.find('if [ ! -f "$zone" ]')
check(zone_guard != -1 and for_dir != -1 and zone_guard < for_dir,
      'post-create.sh zone file guard must run before directory creation')
apply_zone = post.find('sudo -n ln -sfn "$zone"')
check(apply_zone != -1 and for_dir != -1 and apply_zone < for_dir,
      'post-create.sh must apply the zone before directory creation')

arg_tz_pos = dockerfile.find('ARG TZ=')
env_tz_pos = dockerfile.find('ENV TZ=')
tzif_pos = dockerfile.find('TZif')
check(arg_tz_pos != -1 and env_tz_pos != -1 and arg_tz_pos < env_tz_pos,
      'Dockerfile ARG TZ= must precede ENV TZ=')
check(env_tz_pos != -1 and tzif_pos != -1 and env_tz_pos < tzif_pos,
      'Dockerfile ENV TZ= must precede the TZif check')

for p in (repo / '.devcontainer').glob('*'):
    if p.is_file():
        text = p.read_text(errors='replace')
        if '/home/vscode' in text or 'vscode:vscode' in text:
            errors.append(f'vscode path/user reference in {p.relative_to(repo)}')

if errors:
    for e in errors:
        print(f'FAIL: {e}')
    sys.exit(1)
print('PASS: static contract')
PY
  say "T1c agent roster"
  python3 - "$REPO" <<'PY'
import pathlib, re, sys
repo = pathlib.Path(sys.argv[1])
agents_dir = repo / '.opencode' / 'agents'
skills_dir = repo / '.opencode' / 'skills'
errors = []

def check(cond, msg):
    if not cond:
        errors.append(msg)

model = 'opencode-go/deepseek-v4.1-flash'
agents = ['orchestrator', 'research', 'copy-writer', 'design', 'rubber-duck',
          'task-enumerator', 'implementer', 'validator', 'security-reviewer']
read_only = ('design', 'rubber-duck', 'task-enumerator', 'validator',
             'security-reviewer')
workers = agents[1:]
role_skills = ('orchestration', 'design-proposal', 'rubber-duck',
               'task-breakdown', 'code-review', 'security-review')

def frontmatter(path):
    text = path.read_text()
    if not text.startswith('---\n'):
        return None
    end = text.find('\n---', 4)
    if end == -1:
        return None
    return text[4:end]

def scalar(fm, key):
    match = re.search(rf'(?m)^{re.escape(key)}:\s*(.+?)\s*$', fm)
    return match.group(1).strip().strip('"') if match else None

def permission_rules(fm):
    rules = []
    current = None
    in_permissions = False
    for line in fm.splitlines():
        if re.match(r'^permissions:\s*$', line):
            in_permissions = True
            continue
        if not in_permissions:
            continue
        if re.match(r'^\S', line):
            break
        match = re.match(r'^\s*-\s+action:\s*(.+?)\s*$', line)
        if match:
            current = {'action': match.group(1).strip().strip('"')}
            rules.append(current)
            continue
        match = re.match(r'^\s+(resource|effect):\s*(.+?)\s*$', line)
        if match and current is not None:
            current[match.group(1)] = match.group(2).strip().strip('"')
    return rules

def has_rule(rules, action, resource, effect):
    return any(rule.get('action') == action
               and rule.get('resource') == resource
               and rule.get('effect') == effect for rule in rules)

frontmatters = {}
for name in agents:
    path = agents_dir / f'{name}.md'
    check(path.is_file(), f'agent {name} missing')
    if not path.is_file():
        continue
    fm = frontmatter(path)
    check(fm is not None, f'agent {name} missing frontmatter')
    if fm is None:
        continue
    frontmatters[name] = fm
    check(scalar(fm, 'mode') is not None, f'agent {name} missing mode')
    check(scalar(fm, 'model') == model,
          f'agent {name} model must be {model}')
    expected_mode = 'primary' if name == 'orchestrator' else 'subagent'
    check(scalar(fm, 'mode') == expected_mode,
          f'agent {name} must be mode: {expected_mode}')

orchestrator = frontmatters.get('orchestrator')
if orchestrator is not None:
    rules = permission_rules(orchestrator)
    check(has_rule(rules, 'edit', '*', 'deny'),
          'orchestrator must deny edit *')
    for resource in ('**/docs/superpowers/**', '**/.superpowers/**'):
        check(has_rule(rules, 'edit', resource, 'allow'),
              f'orchestrator must allow edit {resource}')
    check(has_rule(rules, 'subagent', '*', 'deny'),
          'orchestrator must deny subagent *')
    for worker in workers:
        check(has_rule(rules, 'subagent', worker, 'allow'),
              f'orchestrator must allow subagent {worker}')
    check(has_rule(rules, 'question', '*', 'allow'),
          'orchestrator must allow question *')
    check(has_rule(rules, 'skill', '*', 'allow'),
          'orchestrator must allow skill *')

for name in read_only:
    fm = frontmatters.get(name)
    if fm is None:
        continue
    rules = permission_rules(fm)
    check(has_rule(rules, 'edit', '*', 'deny'),
          f'{name} must deny edit *')
    check(has_rule(rules, 'question', '*', 'deny'),
          f'{name} must deny question *')
    check(has_rule(rules, 'subagent', '*', 'deny'),
          f'{name} must deny subagent *')
    for action in ('execute', 'webfetch', 'websearch', 'external_directory',
                   'opencode_*', 'worktree_*', 'session_*'):
        check(has_rule(rules, action, '*', 'deny'),
              f'{name} must deny {action} *')

strict_read_only = {'design': 'design-proposal',
                    'rubber-duck': 'rubber-duck',
                    'task-enumerator': 'task-breakdown'}
for name, skill in strict_read_only.items():
    fm = frontmatters.get(name)
    if fm is None:
        continue
    rules = permission_rules(fm)
    check(has_rule(rules, 'shell', '*', 'deny'),
          f'{name} must deny shell *')
    check(has_rule(rules, 'skill', skill, 'allow'),
          f'{name} must allow its role skill {skill}')

for name in ('validator', 'security-reviewer'):
    fm = frontmatters.get(name)
    if fm is None:
        continue
    rules = permission_rules(fm)
    check(has_rule(rules, 'shell', '*', 'allow'),
          f'{name} must allow shell for tests and git')
    for resource in ('git push*', 'git reset --hard*', 'rm -rf*'):
        check(has_rule(rules, 'shell', resource, 'deny'),
              f'{name} must deny shell {resource}')

implementer = frontmatters.get('implementer')
if implementer is not None:
    rules = permission_rules(implementer)
    check(has_rule(rules, 'edit', '*', 'allow'),
          'implementer must allow edit *')
    check(has_rule(rules, 'question', '*', 'deny'),
          'implementer must deny question *')
    check(has_rule(rules, 'subagent', '*', 'deny'),
          'implementer must deny subagent *')
    check(has_rule(rules, 'shell', '*', 'allow'),
          'implementer must allow shell *')
    check(has_rule(rules, 'shell', 'git push*', 'deny'),
          'implementer must deny git push')
    check(has_rule(rules, 'shell', 'git reset --hard*', 'deny'),
          'implementer must deny git reset --hard')
    for skill in ('test-driven-development', 'systematic-debugging',
                  'verification-before-completion', 'receiving-code-review'):
        check(has_rule(rules, 'skill', skill, 'allow'),
              f'implementer must allow skill {skill}')

research = frontmatters.get('research')
if research is not None:
    rules = permission_rules(research)
    for action, resource, effect, label in (
            ('edit', '*', 'deny', 'edit *'),
            ('edit', 'research/**', 'allow', 'edit research/**'),
            ('shell', '*', 'deny', 'shell *'),
            ('websearch', '*', 'deny', 'websearch *'),
            ('execute', '*', 'deny', 'execute *'),
            ('subagent', '*', 'deny', 'subagent *'),
            ('question', '*', 'deny', 'question *'),
            ('parallel-search_*', '*', 'allow', 'Parallel Search tools'),
            ('brave-search-mcp-server_*', '*', 'allow', 'Brave Search tools')):
        check(has_rule(rules, action, resource, effect),
              f'research must keep {label}')

copy_writer = frontmatters.get('copy-writer')
if copy_writer is not None:
    rules = permission_rules(copy_writer)
    for action, resource, effect, label in (
            ('edit', '*', 'deny', 'edit *'),
            ('edit', '.opencode/**', 'deny', 'edit .opencode/**'),
            ('parallel-search_*', '*', 'deny', 'Parallel Search deny'),
            ('brave-search-mcp-server_*', '*', 'deny', 'Brave Search deny'),
            ('subagent', '*', 'deny', 'subagent *'),
            ('question', '*', 'deny', 'question *')):
        check(has_rule(rules, action, resource, effect),
              f'copy-writer must keep {label}')

found_skills = {path.parent.name: path
                for path in skills_dir.rglob('SKILL.md')}
for skill in role_skills:
    check(skill in found_skills, f'role skill {skill} missing SKILL.md')
check('run-research' in found_skills, 'run-research skill missing')
for skill in ('technical-writing', 'writing-design-docs', 'recording-decisions',
              'writing-changelogs', 'writing-runbooks', 'writing-issues',
              'writing-postmortems', 'documenting-legacy-codebases',
              'diagramming-processes', 'documenting-contracts',
              'reviewing-technical-prose', 'writing-clearly-and-concisely',
              'writing-commits-and-pull-requests'):
    check(skill in found_skills, f'writing skill {skill} missing')

if errors:
    for error in errors:
        print(f'FAIL: {error}')
    sys.exit(1)
print('PASS: agent roster')
PY
  bash -n "$REPO/.devcontainer/post-create.sh"
  echo 'PASS: post-create.sh syntax'
  bash -n "$REPO/.devcontainer/host-init.sh"
  echo 'PASS: host-init.sh syntax'
  bash -n "$REPO/.devcontainer/bin/gh-app"
  python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
    "$REPO/.devcontainer/bin/gh-app-token"
  echo 'PASS: GitHub App helper syntax'
  bash -n "$REPO/.devcontainer/bin/repo"
  echo 'PASS: repo helper syntax'
  bash -n "$REPO/scripts/render-excalidraw.sh"
  echo 'PASS: Excalidraw renderer syntax'
  bash -n "$REPO/scripts/update-superpowers.sh"
  echo 'PASS: Superpowers update script syntax'
}

run_app_token() {
  say "T1b GitHub App token tests"
  python3 "$SCRIPT_DIR/github-app-token-test.py" -v
}

run_build() {
  prepare_copy
  say "T2 image/feature build"
  if ! devcontainer build --workspace-folder "$COPY" --frozen-lockfile \
      >"$COPY/build.stdout" 2>"$COPY/build.stderr"; then
    tail -80 "$COPY/build.stderr" >&2 || true
    tail -80 "$COPY/build.stdout" >&2 || true
    die "devcontainer build failed"
  fi
  echo 'PASS: image/feature build'
}

run_pre_smoke() {
  local cid
  cid="$(container_id)"
  say "T3 pre-post-create smoke"
  devcontainer exec --container-id "$cid" -- bash -s <<'EOS'
set -uo pipefail
fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$n"; else bad "$n"; fi; }
check_eq() { local n="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then pass "$n"; else bad "$n (expected '$e', got '$a')"; fi; }

check_eq "identity: user" developer "$(id -un)"
check_eq "identity: shell" /bin/bash "$(getent passwd developer | cut -d: -f7)"
check "identity: passwordless sudo" sudo -n true
check_eq "home" /home/developer "$HOME"

for c in git curl yq glow opencode go node npm python3 uv bun fzf kind kubectx kubens kubectl helm gh docker ssh rg less nvim starship unzip zip; do
  check "command: $c" command -v "$c"
done

arg() { sed -n "s/^ARG $1=//p" /workspace/.devcontainer/Dockerfile | head -1 | tr -d '"'; }
glow_expected="$(arg GLOW_VERSION)"
kubectl_expected="$(arg KUBECTL_VERSION)"
helm_expected="$(arg HELM_VERSION)"
check "dockerfile: GLOW_VERSION" test -n "$glow_expected"
check "dockerfile: KUBECTL_VERSION" test -n "$kubectl_expected"
check "dockerfile: HELM_VERSION" test -n "$helm_expected"
check_eq "kubectl version" "$kubectl_expected" \
  "$(kubectl version --client -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["clientVersion"]["gitVersion"])')"
check_eq "helm version" "$helm_expected" \
  "$(helm version --template '{{.Version}}')"
check "minikube absent" bash -c '! command -v minikube'
check "package: bash-completion" dpkg -s bash-completion
check "package: less" dpkg -s less

check "run: node" node --version
check "run: npm" npm --version
check "run: python3" python3 --version
check "run: go" go version
check "run: uv" uv --version
check "run: bun" bun --version
check "run: yq" yq --version
check "run: glow" glow --version
check "run: glow version" bash -c "glow --version | grep -qF '${glow_expected#v}'"
check "run: glow pager" bash -c 'printf "# pager\n" >/tmp/glow-pager.md && env -u PAGER glow /tmp/glow-pager.md --pager </dev/null >/dev/null && rm -f /tmp/glow-pager.md'
check "run: opencode" opencode --version
check "run: nvim" nvim --version
check "run: starship" starship --version
check "specify absent" bash -c '! command -v specify'
check "run: unzip" unzip -v
check "run: zip" zip -v

docker_ok=0
for _ in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then docker_ok=1; break; fi
  sleep 2
done
check_eq "dind: docker info" 1 "$docker_ok"
check "dind: docker compose" docker compose version
check "dind: docker buildx" docker buildx version

for d in "$HOME/.local/share/opencode" "$HOME/.local/state/opencode" \
         "$HOME/.local/share/opentui" "$HOME/.local/share/uv" \
         "$HOME/.local/state/nvim" "$HOME/.local/share/nvim" "$HOME/.kube"; do
  if [ -d "$d" ]; then
    check_eq "owner: $d" developer "$(stat -c '%U' "$d")"
  else
    bad "missing dir: $d"
  fi
done
if [ -L /worktrees ]; then
  check_eq "/worktrees symlink" /workspace/repos "$(readlink /worktrees)"
else
  bad "/worktrees must be a symlink to /workspace/repos"
fi
check "locale: en_US.utf8" bash -c "locale -a | grep -qi en_US"

tz_arg="$(arg TZ)"
container_tz="$(yq -r '.containerEnv.TZ // ""' /workspace/.devcontainer/devcontainer.json)"
tz_template='${localEnv:DEVCONTAINER_TZ:America/Los_Angeles}'
check "dockerfile: TZ" test -n "$tz_arg"
if [ "$container_tz" = "$tz_template" ]; then
  check "env: TZ" test -n "${TZ:-}"
elif [ -n "$container_tz" ]; then
  check_eq "env: TZ" "$container_tz" "${TZ:-}"
else
  check_eq "env: TZ" "$tz_arg" "${TZ:-}"
fi
check "timezone: zoneinfo present" test -f "/usr/share/zoneinfo/$tz_arg"
check "timezone: localtime matches image default" \
  cmp -s /etc/localtime "/usr/share/zoneinfo/$tz_arg"
check_eq "timezone: /etc/timezone" "$tz_arg" "$(cat /etc/timezone 2>/dev/null || true)"

tz_summer_ref="$(TZ="$tz_arg" date -d '2026-07-01 12:00:00 UTC' +%z)"
tz_winter_ref="$(TZ="$tz_arg" date -d '2026-01-15 12:00:00 UTC' +%z)"
check_eq "timezone: summer offset" "$tz_summer_ref" \
  "$(env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"
check_eq "timezone: winter offset" "$tz_winter_ref" \
  "$(env -u TZ date -d '2026-01-15 12:00:00 UTC' +%z)"
check_eq "timezone: summer abbreviation" \
  "$(TZ="$tz_arg" date -d '2026-07-01 12:00:00 UTC' +%Z)" \
  "$(env -u TZ date -d '2026-07-01 12:00:00 UTC' +%Z)"
check_eq "timezone: clean env offset" "$tz_summer_ref" \
  "$(env -i PATH=/usr/bin:/bin date -d '2026-07-01 12:00:00 UTC' +%z)"
check_eq "timezone: sudo clean env offset" "$tz_summer_ref" \
  "$(sudo -n env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"
check_eq "clock: UTC rendering" +0000 "$(date -u +%z)"

if [ "$fail" -ne 0 ]; then echo "PRE-SMOKE FAILED"; exit 1; fi
echo "PRE-SMOKE PASSED"
EOS
}

run_smoke() {
  local cid
  cid="$(container_id)"
  say "T4 runtime smoke"
  devcontainer exec --container-id "$cid" -- bash -s <<'EOS'
set -uo pipefail
fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$n"; else bad "$n"; fi; }
check_eq() { local n="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then pass "$n"; else bad "$n (expected '$e', got '$a')"; fi; }

check_eq "identity: user" developer "$(id -un)"
check_eq "identity: shell" /bin/bash "$(getent passwd developer | cut -d: -f7)"
check "identity: passwordless sudo" sudo -n true
check_eq "home" /home/developer "$HOME"
check_eq "env: LANG" en_US.UTF-8 "${LANG:-}"
check_eq "env: LC_ALL" en_US.UTF-8 "${LC_ALL:-}"
check_eq "env: STARSHIP_CONFIG" /workspace/.devcontainer/starship.toml "${STARSHIP_CONFIG:-}"
check_eq "env: EDITOR" nvim "${EDITOR:-}"
check_eq "env: KUBECONFIG" /home/developer/.kube/config "${KUBECONFIG:-}"

for c in git curl yq glow opencode go node npm python3 uv bun fzf kind kubectx kubens kubectl helm gh docker ssh rg less nvim starship unzip zip gh-app-token gh-app; do
  check "command: $c" command -v "$c"
done
check "run: gh-app-token help" gh-app-token --help
check "run: gh-app-token missing config" bash -c \
  'out=$(env -u GITHUB_APP_CLIENT_ID -u GITHUB_APP_ID -u GITHUB_APP_INSTALLATION_ID \
       -u GITHUB_APP_PRIVATE_KEY_FILE -u GITHUB_API_URL -u GITHUB_SERVER_URL \
       gh-app-token --env-file /dev/null token 2>&1); rc=$?; \
       test "$rc" -eq 2 && printf "%s" "$out" | grep -q GITHUB_APP_CLIENT_ID'

arg() { sed -n "s/^ARG $1=//p" /workspace/.devcontainer/Dockerfile | head -1 | tr -d '"'; }
glow_expected="$(arg GLOW_VERSION)"
kubectl_expected="$(arg KUBECTL_VERSION)"
helm_expected="$(arg HELM_VERSION)"
check "dockerfile: GLOW_VERSION" test -n "$glow_expected"
check "dockerfile: KUBECTL_VERSION" test -n "$kubectl_expected"
check "dockerfile: HELM_VERSION" test -n "$helm_expected"
check_eq "kubectl version" "$kubectl_expected" \
  "$(kubectl version --client -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["clientVersion"]["gitVersion"])')"
check_eq "helm version" "$helm_expected" \
  "$(helm version --template '{{.Version}}')"
check "minikube absent" bash -c '! command -v minikube'

tz_expected="${TZ:-}"
check "env: TZ" test -n "$tz_expected"
if [ -n "$tz_expected" ]; then
  check "timezone: zoneinfo present" test -f "/usr/share/zoneinfo/$tz_expected"
  check "timezone: localtime matches TZ" \
    cmp -s /etc/localtime "/usr/share/zoneinfo/$tz_expected"
  check_eq "timezone: /etc/timezone" "$tz_expected" \
    "$(cat /etc/timezone 2>/dev/null || true)"

  tz_summer_ref="$(TZ="$tz_expected" date -d '2026-07-01 12:00:00 UTC' +%z)"
  tz_winter_ref="$(TZ="$tz_expected" date -d '2026-01-15 12:00:00 UTC' +%z)"
  check_eq "timezone: summer offset" "$tz_summer_ref" \
    "$(env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"
  check_eq "timezone: winter offset" "$tz_winter_ref" \
    "$(env -u TZ date -d '2026-01-15 12:00:00 UTC' +%z)"
  check_eq "timezone: summer abbreviation" \
    "$(TZ="$tz_expected" date -d '2026-07-01 12:00:00 UTC' +%Z)" \
    "$(env -u TZ date -d '2026-07-01 12:00:00 UTC' +%Z)"
  check_eq "timezone: clean env offset" "$tz_summer_ref" \
    "$(env -i PATH=/usr/bin:/bin date -d '2026-07-01 12:00:00 UTC' +%z)"
  check_eq "timezone: sudo clean env offset" "$tz_summer_ref" \
    "$(sudo -n env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"
fi
check_eq "clock: UTC rendering" +0000 "$(date -u +%z)"

check "run: node" node --version
check "run: npm" npm --version
check "run: go" go version
check "run: python3" python3 --version
check "run: uv" uv --version
check "run: bun" bun --version
check "run: fzf" fzf --version
check "run: kind" kind --version
check "run: kubectl" kubectl version --client
check "run: helm" helm version --short
check "kubeconfig: writable" bash -c 'test -w "$HOME/.kube/config"'
check "kubeconfig: client-go lock" bash -c 'kubectl config set-context smoke-test --cluster=smoke --user=smoke >/dev/null && kubectl config delete-context smoke-test >/dev/null'
check "run: gh" gh --version
check "run: ssh" ssh -V
check "run: rg" rg --version
check "run: less" less --version
check "run: nvim" nvim --version
check "run: nvim headless" nvim --headless +q
check "run: starship" starship --version
check "run: starship prompt" starship prompt
check "specify absent" bash -c '! command -v specify'
check "run: unzip" unzip -v
check "run: zip" zip -v
check "archive round-trip" bash -c 'cd /tmp && rm -rf dc-zip-test && mkdir dc-zip-test && echo hello > dc-zip-test/hello.txt && zip -q -r dc-zip-test.zip dc-zip-test && rm -rf dc-zip-test && unzip -q dc-zip-test.zip && test "$(cat dc-zip-test/hello.txt)" = hello && rm -rf dc-zip-test dc-zip-test.zip'
yq_expected="$(sed -n 's/^ARG YQ_VERSION=//p' /workspace/.devcontainer/Dockerfile | head -1 | tr -d '"')"
check "run: yq version" bash -c "yq --version | grep -qF '$yq_expected'"
check "run: glow" glow --version
check "run: glow version" bash -c "glow --version | grep -qF '${glow_expected#v}'"
check "run: glow pager" bash -c 'printf "# pager\n" >/tmp/glow-pager.md && env -u PAGER glow /tmp/glow-pager.md --pager </dev/null >/dev/null && rm -f /tmp/glow-pager.md'
check "run: opencode" opencode --version
agents_file="$(mktemp)" || die "cannot create agents temp file"
agents_err="$(mktemp)" || die "cannot create agents error file"
if ! opencode --standalone debug agents >"$agents_file" 2>"$agents_err"; then
  bad "control-plane agents: debug agents failed"
  sed -n '1,40p' "$agents_err" >&2 || true
elif ! python3 - "$agents_file" <<'PY'
import json, sys
agents = {a['id']: a for a in json.load(open(sys.argv[1]))}
expected = {'orchestrator','research','copy-writer','design','rubber-duck',
            'task-enumerator','implementer','validator','security-reviewer'}
missing = expected - agents.keys()
assert not missing, f'missing agents: {sorted(missing)}'
assert agents['orchestrator']['mode'] == 'primary'
for name in expected - {'orchestrator'}:
    assert agents[name]['mode'] == 'subagent', name
for name in expected:
    resolved = agents[name]['model']
    assert resolved.get('providerID') == 'opencode-go', name
    # OpenCode 2.3.0 reports the model id under 'id'; older shapes used 'model'.
    assert resolved.get('id', resolved.get('model')) == 'deepseek-v4.1-flash', name
print('PASS: control-plane agents')
PY
then
  bad "control-plane agents"
fi
hermetic=0
if [ -f /workspace/.dc-smoke-prefix ]; then
  hermetic=1
fi
if [ "$hermetic" -eq 1 ]; then
  if [ -f "$agents_file" ]; then
    if python3 - "$agents_file" <<'PY'
import json, sys
agents = {a['id']: a for a in json.load(open(sys.argv[1]))}
research = agents.get('research', {})
description = research.get('description', '')
assert description == 'Host test research override', description
system = research.get('system', '')
assert 'Host test research override body' in system, system[:200]
model = research.get('model', {})
assert model.get('providerID') == 'opencode-go', model
assert model.get('id', model.get('model')) == 'deepseek-v4.1-flash', model
permissions = research.get('permissions', [])
def matching(action, resource, effect):
    return [i for i, rule in enumerate(permissions)
            if rule.get('action') == action
            and rule.get('resource') == resource
            and rule.get('effect') == effect]
base = matching('edit', 'research/**', 'allow')
question = matching('question', '*', 'deny')
host = matching('edit', 'research/host/**', 'allow')
assert base, permissions
assert question, permissions
assert host, permissions
assert base[0] < host[0], (base, host)
PY
    then
      pass "host overlay: research agent override"
      pass "host overlay: research body and model"
      pass "host overlay: research permissions inherit and append"
    else
      bad "host overlay: research agent override"
      bad "host overlay: research body and model"
      bad "host overlay: research permissions inherit and append"
    fi
  fi
  # The first `opencode mcp list` can start the background service and read an
  # empty list before it has loaded the host overlay. Retry before failing.
  mcp_listed=0
  for _ in $(seq 1 15); do
    if opencode mcp list >"$HOME/.mcp-list.txt" 2>&1 \
        && grep -qF 'probe-disabled' "$HOME/.mcp-list.txt"; then
      mcp_listed=1
      break
    fi
    sleep 1
  done
  if [ "$mcp_listed" -eq 1 ]; then
    check "host overlay: probe-disabled listed" grep -qF 'probe-disabled' "$HOME/.mcp-list.txt"
    if [ -f /etc/opencode/opencode.json ]; then
      for server in parallel-search brave-search-mcp-server; do
        if grep -qF "\"$server\"" /etc/opencode/opencode.json; then
          check "host overlay: $server listed" grep -qF "$server" "$HOME/.mcp-list.txt"
        fi
      done
    fi
  else
    check "host overlay: probe-disabled listed" grep -qF 'probe-disabled' "$HOME/.mcp-list.txt"
    sed -n '1,40p' "$HOME/.mcp-list.txt" >&2 || true
  fi
  test_root="$(mktemp -d)"
  if [ -d /workspace/test-remote.git ]; then
    if REPO_ROOT="$test_root" repo clone "file:///workspace/test-remote.git" >"$test_root/clone.log" 2>&1; then
      pass "repo clone: local remote"
    else
      bad "repo clone: local remote"
      sed -n '1,40p' "$test_root/clone.log" >&2 || true
    fi
    clone_dir="$test_root/local/test-remote"
    check "repo clone: checkout exists" test -d "$clone_dir"
    if [ -d "$clone_dir" ]; then
      if ( cd "$clone_dir" && opencode --standalone debug agents ) \
          >"$test_root/clone-agents.json" 2>"$test_root/clone-agents.err"; then
        pass "clone inheritance: debug agents"
      else
        bad "clone inheritance: debug agents"
        sed -n '1,40p' "$test_root/clone-agents.err" >&2 || true
      fi
      if [ -f "$test_root/clone-agents.json" ] \
          && python3 - "$test_root/clone-agents.json" <<'PY'
import json, sys
agents = {a['id']: a for a in json.load(open(sys.argv[1]))}
expected = {'orchestrator', 'research', 'copy-writer', 'design', 'rubber-duck',
            'task-enumerator', 'implementer', 'validator', 'security-reviewer'}
missing = expected - agents.keys()
assert not missing, f'missing agents: {sorted(missing)}'
assert agents['orchestrator']['mode'] == 'primary'
for name in expected - {'orchestrator'}:
    assert agents[name]['mode'] == 'subagent', name
for name in expected:
    model = agents[name]['model']
    assert model.get('providerID') == 'opencode-go', name
    assert model.get('id', model.get('model')) == 'deepseek-v4.1-flash', name
PY
      then
        pass "clone inheritance: agents, modes, and models"
      else
        bad "clone inheritance: agents, modes, and models"
      fi
      for link in agents/orchestrator.md agents/research.md skills/orchestration; do
        check "clone inheritance: global link $link" test -L "$HOME/.config/opencode/$link"
      done
      if ( cd "$clone_dir" && REPO_ROOT="$test_root" repo worktree smoke-wt smoke-branch ) >"$test_root/worktree.log" 2>&1; then
        pass "repo worktree: created"
      else
        bad "repo worktree: created"
        sed -n '1,40p' "$test_root/worktree.log" >&2 || true
      fi
      worktree_dir="$test_root/.worktrees/local/test-remote/smoke-wt"
      check "repo worktree: path exists" test -d "$worktree_dir"
      if [ -d "$worktree_dir" ]; then
        git -C "$clone_dir" worktree remove --force "$worktree_dir" >/dev/null 2>&1 || rm -rf "$worktree_dir"
      fi
      if ( cd "$clone_dir" && REPO_ROOT="$test_root" repo worktree ../escape smoke-branch ) \
          >"$test_root/worktree-escape.log" 2>&1; then
        bad "repo worktree: rejects traversal"
      else
        pass "repo worktree: rejects traversal"
      fi
      check "repo worktree: traversal creates nothing" test ! -e "$test_root/.worktrees/local/escape"
      check "repo worktree: traversal creates no sibling" test ! -e "$test_root/escape"
      if ( cd "$clone_dir" && REPO_ROOT="$test_root" repo fork upstream/repo .. ) \
          >"$test_root/fork-escape.log" 2>&1; then
        bad "repo fork: rejects traversal"
      else
        pass "repo fork: rejects traversal"
      fi
      check "repo fork: traversal creates nothing" test ! -e "$test_root/repo"
      if ( cd "$test_root" && REPO_ROOT="$test_root" repo clone ../repo ) \
          >"$test_root/clone-escape.log" 2>&1; then
        bad "repo clone: rejects traversal"
      else
        pass "repo clone: rejects traversal"
      fi
      check "repo clone: traversal creates nothing" test ! -e "$test_root/local/repo"
      if ( cd "$clone_dir" && REPO_ROOT="$test_root" repo pr --detach ) \
          >"$test_root/pr-option.log" 2>&1; then
        bad "repo pr: rejects option injection"
      else
        pass "repo pr: rejects option injection"
      fi
    fi
    rm -rf "$test_root"
  fi
fi
check "host overlay: /etc/opencode read-only" bash -c \
  'findmnt -no OPTIONS /etc/opencode 2>/dev/null | tr "," "\n" | grep -qx ro'

docker_ok=0
for _ in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then docker_ok=1; break; fi
  sleep 2
done
check_eq "dind: docker info" 1 "$docker_ok"
check "dind: docker compose" docker compose version
check "dind: docker buildx" docker buildx version

for d in "$HOME/.local/share/opencode" "$HOME/.local/state/opencode" \
         "$HOME/.local/share/opentui" "$HOME/.local/share/uv" \
         "$HOME/.local/state/nvim" "$HOME/.local/share/nvim" "$HOME/.kube"; do
  if [ -d "$d" ]; then
    check_eq "owner: $d" developer "$(stat -c '%U' "$d")"
  else
    bad "missing dir: $d"
  fi
done
if [ -d /workspace/repos ]; then
  check_eq "owner: /workspace/repos" developer "$(stat -c '%U' /workspace/repos)"
  if touch /workspace/repos/.smoke-$$ 2>/dev/null; then rm -f /workspace/repos/.smoke-$$; pass "/workspace/repos writable"; else bad "/workspace/repos not writable"; fi
else
  bad "missing /workspace/repos"
fi
if [ -L /worktrees ]; then
  check_eq "/worktrees symlink" /workspace/repos "$(readlink /worktrees)"
else
  bad "/worktrees must be a symlink to /workspace/repos"
fi

check "bashrc: kubectl aliases" grep -q '# --- kubectl aliases ---' "$HOME/.bashrc"
check "bashrc: devcontainer aliases" grep -q '# --- devcontainer aliases ---' "$HOME/.bashrc"
check "bashrc: terminal paste" grep -q '# --- terminal paste ---' "$HOME/.bashrc"
check "bashrc: starship prompt" grep -q '# --- starship prompt ---' "$HOME/.bashrc"
check "bashrc: helm completion" grep -q '# --- helm completion ---' "$HOME/.bashrc"
check "bash-completion: _init_completion" bash -ic 'declare -F _init_completion'
check "completion: kubectl" bash -ic 'complete -p kubectl | grep -q __start_kubectl'
check "completion: helm" bash -ic 'complete -p helm | grep -q __start_helm'
check "alias: ll" bash -ic 'type ll >/dev/null 2>&1'
check "alias: vi" bash -ic 'type vi >/dev/null 2>&1'
check "alias: gs" bash -ic 'type gs >/dev/null 2>&1'
check "bashrc: github env" grep -q '# --- github env ---' "$HOME/.bashrc"
check "bashrc: brave env" grep -q '# --- brave env ---' "$HOME/.bashrc"
if [ -f "$HOME/.dc/github/.env" ]; then
  check "bashrc: github env loads" bash -ic 'test -n "${GITHUB_TOKEN:-}"'
fi
if [ -f "$HOME/.dc/brave/.env" ]; then
  check "bashrc: brave env loads" bash -ic 'test -n "${BRAVE_API_KEY:-}"'
fi
check "locale: en_US.utf8" bash -c "locale -a | grep -qi en_US"

rm -f "$agents_file" "$agents_err"
if [ "$fail" -ne 0 ]; then echo "SMOKE FAILED"; exit 1; fi
echo "SMOKE PASSED"
EOS
}

run_paste() {
  local cid
  cid="$(container_id)"
  say "T7 PTY paste smoke"
  python3 "$SCRIPT_DIR/paste-smoke.py" --container-id "$cid"
}

run_idempotent() {
  local cid before after state epoch_before epoch_after epoch_delta
  cid="$(container_id)"
  say "T5 post-create idempotency"
  state='
  wc -l < "$HOME/.bashrc"
  grep -c "^# --- " "$HOME/.bashrc" || true
  readlink -f /etc/localtime
  stat -c %i /etc/localtime
  cat /etc/timezone 2>/dev/null || true
'
  epoch_before="$(devcontainer exec --container-id "$cid" -- date +%s)"
  before="$(devcontainer exec --container-id "$cid" -- bash -c "$state")"
  for i in 1 2; do
    if ! devcontainer exec --container-id "$cid" -- bash -c 'cd /workspace && bash .devcontainer/post-create.sh' \
        >"$COPY/post-create-$i.stdout" 2>"$COPY/post-create-$i.stderr"; then
      tail -80 "$COPY/post-create-$i.stderr" >&2 || true
      tail -80 "$COPY/post-create-$i.stdout" >&2 || true
      die "manual post-create run $i failed"
    fi
  done
  after="$(devcontainer exec --container-id "$cid" -- bash -c "$state")"
  epoch_after="$(devcontainer exec --container-id "$cid" -- date +%s)"
  [ "$before" = "$after" ] || die ".bashrc or timezone state changed after repeated post-create"
  epoch_delta=$((epoch_after - epoch_before))
  [ "$epoch_delta" -ge 0 ] && [ "$epoch_delta" -lt 120 ] \
    || die "system clock jumped during post-create (${epoch_delta}s)"
  echo 'PASS: post-create is idempotent'
}

run_recreate() {
  say "T5b container recreate with persistent volumes"
  run_up
  run_smoke
}

run_fresh() {
  local cid vols vol
  cid="$(container_id)"
  say "T6 fresh-volume test"
  vols="$(docker inspect "$cid" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}')"
  docker rm -f "$cid" >/dev/null 2>&1 || true
  for vol in $vols; do
    case "$vol" in
      "$PREFIX"*|dind-var-lib-docker-*)
        docker volume rm "$vol" >/dev/null 2>&1 || true
        if docker volume inspect "$vol" >/dev/null 2>&1; then
          die "failed to remove test volume: $vol"
        fi
        ;;
    esac
  done
  if docker volume ls -q 2>/dev/null | grep -q "^${PREFIX}"; then
    die "test volumes remain after cleanup"
  fi
  rm -f "$COPY/.dc-smoke-container-id"
  run_up
  run_smoke
}

run_tz() {
  last_copy
  local cid
  TZ_JSON_BACKUP="$COPY/.devcontainer/devcontainer.json.tz-backup"
  cp "$COPY/.devcontainer/devcontainer.json" "$TZ_JSON_BACKUP"
  trap 'cp "$COPY/.devcontainer/devcontainer.json.tz-backup" "$COPY/.devcontainer/devcontainer.json"; rm -f "$COPY/.devcontainer/devcontainer.json.tz-backup"' EXIT

  python3 - "$COPY/.devcontainer/devcontainer.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    d = json.load(f)
d.setdefault('containerEnv', {})['TZ'] = 'Asia/Tokyo'
with open(p, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
PY

  say "T8 timezone override"
  run_up skip
  cid="$(container_id)"
  devcontainer exec --container-id "$cid" -- bash -s <<'EOS'
set -uo pipefail
fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$n"; else bad "$n"; fi; }
check_eq() { local n="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then pass "$n"; else bad "$n (expected '$e', got '$a')"; fi; }

check_eq "tz override pre: env" Asia/Tokyo "${TZ:-}"
tz_arg="$(sed -n 's/^ARG TZ=//p' /workspace/.devcontainer/Dockerfile | head -1 | tr -d '"')"
check "tz override pre: image localtime is still the image default" \
  cmp -s /etc/localtime "/usr/share/zoneinfo/$tz_arg"
if [ "$fail" -ne 0 ]; then echo "TZ PRE-SMOKE FAILED"; exit 1; fi
echo "TZ PRE-SMOKE PASSED"
EOS

  say "T8 timezone override with post-create"
  run_up
  cid="$(container_id)"
  devcontainer exec --container-id "$cid" -- bash -s <<'EOS'
set -uo pipefail
fail=0
pass() { printf 'PASS %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$n"; else bad "$n"; fi; }
check_eq() { local n="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then pass "$n"; else bad "$n (expected '$e', got '$a')"; fi; }

check_eq "tz override: env" Asia/Tokyo "${TZ:-}"
check "tz override: zoneinfo" test -f /usr/share/zoneinfo/Asia/Tokyo
check "tz override: localtime" cmp -s /etc/localtime /usr/share/zoneinfo/Asia/Tokyo
check_eq "tz override: /etc/timezone" Asia/Tokyo "$(cat /etc/timezone)"
check_eq "tz override: offset" +0900 \
  "$(env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"
check_eq "tz override: clean env" +0900 \
  "$(env -i PATH=/usr/bin:/bin date -d '2026-07-01 12:00:00 UTC' +%z)"

before_localtime="$(readlink -f /etc/localtime)"
before_timezone="$(cat /etc/timezone 2>/dev/null || true)"
for bad_tz in 'Not/AZone' 'America/Los Angeles' 'PST' 'America' 'Etc' '' '../etc/passwd' \
    'localtime' 'leapseconds' 'posixrules' '../../../etc/passwd' \
    '/usr/share/zoneinfo/America/Los_Angeles' 'America//Los_Angeles' 'America/Los_Angeles/'; do
  if env TZ="$bad_tz" bash -c 'cd /workspace && bash .devcontainer/post-create.sh' \
      >"$HOME/.tz-invalid.log" 2>&1; then
    bad "tz invalid '$bad_tz' accepted"
  else
    pass "tz invalid '$bad_tz' rejected"
  fi
  check "tz invalid '$bad_tz' message" \
    grep -q 'Invalid TZ' "$HOME/.tz-invalid.log"
  check_eq "tz invalid '$bad_tz' did not mutate localtime" \
    "$before_localtime" "$(readlink -f /etc/localtime)"
  check_eq "tz invalid '$bad_tz' did not mutate /etc/timezone" \
    "$before_timezone" "$(cat /etc/timezone 2>/dev/null || true)"
done

if env TZ=$'America/Los_Angeles\n' bash -c 'cd /workspace && bash .devcontainer/post-create.sh' \
    >"$HOME/.tz-invalid.log" 2>&1; then
  bad "tz invalid multiline accepted"
else
  pass "tz invalid multiline rejected"
fi
check_eq "tz invalid multiline did not mutate localtime" \
  "$before_localtime" "$(readlink -f /etc/localtime)"
check_eq "tz invalid multiline did not mutate /etc/timezone" \
  "$before_timezone" "$(cat /etc/timezone 2>/dev/null || true)"

for good_tz in 'US/Pacific' 'Etc/GMT+5' 'MST7MDT'; do
  if env TZ="$good_tz" bash -c 'cd /workspace && bash .devcontainer/post-create.sh' \
      >"$HOME/.tz-valid.log" 2>&1; then
    pass "tz valid '$good_tz' accepted"
  else
    bad "tz valid '$good_tz' rejected"
  fi
  check_eq "tz valid '$good_tz' /etc/timezone" "$good_tz" \
    "$(cat /etc/timezone 2>/dev/null || true)"
  check "tz valid '$good_tz' localtime" \
    cmp -s /etc/localtime "/usr/share/zoneinfo/$good_tz"
  check_eq "tz valid '$good_tz' offset" \
    "$(TZ="$good_tz" date -d '2026-07-01 12:00:00 UTC' +%z)" \
    "$(env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"
done

if env TZ=Asia/Tokyo bash -c 'cd /workspace && bash .devcontainer/post-create.sh' \
    >"$HOME/.tz-valid.log" 2>&1; then
  pass "tz valid restore accepted"
else
  bad "tz valid restore rejected"
fi
check_eq "tz valid restore /etc/timezone" Asia/Tokyo \
  "$(cat /etc/timezone 2>/dev/null || true)"
check "tz valid restore localtime" cmp -s /etc/localtime /usr/share/zoneinfo/Asia/Tokyo

if [ "$fail" -ne 0 ]; then echo "TZ SMOKE FAILED"; exit 1; fi
echo "TZ SMOKE PASSED"
EOS

  check_eq_host "tz override: docker exec env" Asia/Tokyo "$(docker exec "$cid" printenv TZ)"
  check_eq_host "tz override: docker exec offset" +0900 \
    "$(docker exec "$cid" env -u TZ date -d '2026-07-01 12:00:00 UTC' +%z)"

  cp "$TZ_JSON_BACKUP" "$COPY/.devcontainer/devcontainer.json"
  rm -f "$TZ_JSON_BACKUP"
  trap - EXIT
}

run_cleanup() {
  last_copy
  local cid vols vol
  if [ -f "$COPY/.dc-smoke-container-id" ]; then
    cid="$(cat "$COPY/.dc-smoke-container-id")"
    vols="$(docker inspect "$cid" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}} {{end}}{{end}}' 2>/dev/null || true)"
    docker rm -f "$cid" >/dev/null 2>&1 || true
    for vol in $vols; do
      case "$vol" in
        "$PREFIX"*|dind-var-lib-docker-*) docker volume rm "$vol" >/dev/null 2>&1 || true ;;
      esac
    done
  fi
  for vol in $(docker volume ls -q 2>/dev/null | grep "^${PREFIX}" || true); do
    docker volume rm "$vol" >/dev/null 2>&1 || true
  done
  if docker volume ls -q 2>/dev/null | grep -q "^${PREFIX}"; then
    die "test volumes remain after cleanup"
  fi
  rm -rf -- "$COPY"
  rm -f "$LAST_COPY_FILE"
  echo 'PASS: cleaned up disposable copy, container, and test volumes'
}

case "$MODE" in
  guard) run_guard_test ;;
  static) run_static ;;
  app-token) run_app_token ;;
  build) run_static; run_build ;;
  pre) last_copy; run_up skip; run_pre_smoke ;;
  up) last_copy; run_up; run_smoke ;;
  smoke) last_copy; run_smoke ;;
  smoke-real) run_smoke ;;
  paste) last_copy; run_paste ;;
  paste-real) run_paste ;;
  idempotent) last_copy; run_idempotent ;;
  recreate) last_copy; run_recreate ;;
  fresh) last_copy; run_fresh ;;
  tz) last_copy; run_tz ;;
  cleanup) run_cleanup ;;
  all)
    run_guard_test
    run_static
    run_app_token
    run_build
    run_up skip
    run_pre_smoke
    run_up
    run_smoke
    run_paste
    run_idempotent
    run_recreate
    run_fresh
    run_tz
    ;;
  *) die "unknown mode: $MODE (use guard|static|app-token|build|pre|up|smoke|smoke-real|paste|paste-real|idempotent|recreate|fresh|tz|cleanup|all)" ;;
esac
