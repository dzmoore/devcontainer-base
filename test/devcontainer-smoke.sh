#!/usr/bin/env bash
# Deterministic smoke test for this devcontainer.
#
# Destructive modes (build/up/pre/idempotent/fresh) run against a disposable
# copy of the repo under $HOME and use prefixed volume names for the repo's own
# mounts. Feature-provided volumes (for example minikube-config) are not
# rewritten; the smoke tests do not write to them. The real repo's container
# and volumes are never modified by this script.
#
# Usage: test/devcontainer-smoke.sh [guard|static|build|pre|up|smoke|smoke-real|idempotent|recreate|fresh|cleanup|all]
# Set CID=<container-id> for smoke-real.
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
    rsync -a --exclude .git --exclude test "$REPO/" "$COPY/"
  else
    (cd "$REPO" && tar --exclude .git --exclude test -cf - .) | (cd "$COPY" && tar -xf -)
  fi
  python3 - "$COPY/.devcontainer/devcontainer.json" "$PREFIX" <<'PY'
import json, sys
path, prefix = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
mounts = []
for mount in data.get('mounts', []):
    parts = mount.split(',')
    is_volume = any(p == 'type=volume' for p in parts)
    out = []
    for part in parts:
        if is_volume and (part.startswith('source=') or part.startswith('src=')):
            key, value = part.split('=', 1)
            part = f'{key}={prefix}{value}'
        out.append(part)
    mounts.append(','.join(out))
data['mounts'] = mounts
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
  printf '%s' "$PREFIX" >"$COPY/.dc-smoke-prefix"
  printf '%s' "$COPY" >"$LAST_COPY_FILE"
  echo "PASS: disposable copy and volume prefix $PREFIX"
}

last_copy() {
  [ -f "$LAST_COPY_FILE" ] || die "no disposable copy; run build/up/pre first"
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
import json, pathlib, re, sys
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
check(dc.get('remoteUser') == 'developer', 'remoteUser must be developer')
check(dc.get('postCreateCommand') == 'bash .devcontainer/post-create.sh', 'postCreateCommand must run post-create.sh')
check(dc.get('waitFor') == 'postCreateCommand', 'waitFor must be postCreateCommand')
check((repo / '.devcontainer' / 'post-create.sh').is_file(), 'post-create.sh missing')

container_env = dc.get('containerEnv', {})
check(container_env.get('LANG') == 'en_US.UTF-8', 'containerEnv.LANG must be en_US.UTF-8')
check(container_env.get('LC_ALL') == 'en_US.UTF-8', 'containerEnv.LC_ALL must be en_US.UTF-8')

remote_path = dc.get('remoteEnv', {}).get('PATH', '')
check('/home/developer/.opencode/bin' in remote_path, 'remoteEnv.PATH missing opencode bin')
check('/home/developer/.local/bin' in remote_path, 'remoteEnv.PATH missing local bin')

for mount in dc.get('mounts', []):
    m = dict(part.split('=', 1) for part in mount.split(',') if '=' in part)
    target = m.get('target') or m.get('dst') or ''
    check(target.startswith('/home/developer') or target == '/worktrees',
          f'mount target outside developer home: {target}')
    check('/home/vscode' not in target, f'vscode mount target: {target}')

dockerfile = dockerfile_path.read_text()
check(re.search(r'useradd\b[^\n]*--shell\s+/bin/bash', dockerfile) is not None,
      'Dockerfile useradd must set --shell /bin/bash')
for pkg in ('libatomic1', 'openssh-client', 'ripgrep', 'locales'):
    check(pkg in dockerfile, f'Dockerfile must install {pkg}')
check(re.search(r'^ENV LANG=en_US\.UTF-8', dockerfile, re.M) is not None,
      'Dockerfile must set ENV LANG=en_US.UTF-8')
check('chown -R $USERNAME:$USERNAME' in dockerfile,
      'Dockerfile must chown pre-created volume mount targets')
check('/home/$USERNAME/.local' in dockerfile and '/home/$USERNAME/.config' in dockerfile,
      'Dockerfile must chown the .local and .config parents')
check('/worktrees' in dockerfile, 'Dockerfile must pre-create /worktrees')

post = post_path.read_text()
check('vscode' not in post.lower(), 'post-create.sh still references vscode')
check('YQ_VERSION' not in post, 'post-create.sh should not reinstall yq')
check('export $(' not in post, 'post-create.sh uses unsafe export $(...)')
check('[ -f "$GITHUB_ENV_FILE" ]' in post, 'post-create.sh must use -f for env files')
check('# --- github env ---' in post, 'post-create.sh missing github env marker')
check('# --- brave env ---' in post, 'post-create.sh missing brave env marker')
check('chown -R --no-dereference "$DEV_USER:$DEV_USER" "$HOME/.local" "$HOME/.config" /worktrees' in post,
      'post-create.sh must chown .local, .config, and /worktrees to the runtime user')
check('uv tool install specify-cli' in post, 'post-create.sh must install specify-cli')
check('yq --version' in post, 'post-create.sh must verify yq')

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
  bash -n "$REPO/.devcontainer/post-create.sh"
  echo 'PASS: post-create.sh syntax'
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

for c in git curl yq opencode go node npm python3 uv bun fzf kind kubectx kubens kubectl helm minikube gh docker ssh rg; do
  check "command: $c" command -v "$c"
done

check "run: node" node --version
check "run: npm" npm --version
check "run: python3" python3 --version
check "run: go" go version
check "run: uv" uv --version
check "run: bun" bun --version
check "run: yq" yq --version
check "run: opencode" opencode --version

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
         "$HOME/.local/state/nvim" "$HOME/.local/share/nvim"; do
  if [ -d "$d" ]; then
    check_eq "owner: $d" developer "$(stat -c '%U' "$d")"
  else
    bad "missing dir: $d"
  fi
done
if [ -d /worktrees ]; then
  check_eq "owner: /worktrees" developer "$(stat -c '%U' /worktrees)"
  if touch /worktrees/.smoke-$$ 2>/dev/null; then rm -f /worktrees/.smoke-$$; pass "/worktrees writable"; else bad "/worktrees not writable"; fi
else
  bad "missing /worktrees"
fi
check "locale: en_US.utf8" bash -c "locale -a | grep -qi en_US"

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

for c in git curl yq opencode go node npm python3 uv bun fzf kind kubectx kubens kubectl helm minikube gh docker ssh rg specify; do
  check "command: $c" command -v "$c"
done

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
check "run: minikube" minikube version
check "run: gh" gh --version
check "run: ssh" ssh -V
check "run: rg" rg --version
check "run: specify" specify --help
check "run: yq version" bash -c "yq --version | grep -q 'v4.54.1'"
check "run: opencode version" bash -c "opencode --version 2>&1 | grep -q '2.1.4'"

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
         "$HOME/.local/state/nvim" "$HOME/.local/share/nvim"; do
  if [ -d "$d" ]; then
    check_eq "owner: $d" developer "$(stat -c '%U' "$d")"
  else
    bad "missing dir: $d"
  fi
done
if [ -d /worktrees ]; then
  check_eq "owner: /worktrees" developer "$(stat -c '%U' /worktrees)"
  if touch /worktrees/.smoke-$$ 2>/dev/null; then rm -f /worktrees/.smoke-$$; pass "/worktrees writable"; else bad "/worktrees not writable"; fi
else
  bad "missing /worktrees"
fi

check "uv tool: specify-cli" bash -c "uv tool list 2>/dev/null | grep -q specify-cli"
check "bashrc: kubectl aliases" grep -q '# --- kubectl aliases ---' "$HOME/.bashrc"
check "bashrc: github env" grep -q '# --- github env ---' "$HOME/.bashrc"
check "bashrc: brave env" grep -q '# --- brave env ---' "$HOME/.bashrc"
if [ -f "$HOME/.dc/github/.env" ]; then
  check "bashrc: github env loads" bash -ic 'test -n "${GITHUB_TOKEN:-}"'
fi
if [ -f "$HOME/.dc/brave/.env" ]; then
  check "bashrc: brave env loads" bash -ic 'test -n "${BRAVE_API_KEY:-}"'
fi
check "locale: en_US.utf8" bash -c "locale -a | grep -qi en_US"

if [ "$fail" -ne 0 ]; then echo "SMOKE FAILED"; exit 1; fi
echo "SMOKE PASSED"
EOS
}

run_idempotent() {
  local cid before after
  cid="$(container_id)"
  say "T5 post-create idempotency"
  before="$(devcontainer exec --container-id "$cid" -- bash -c 'wc -l < "$HOME/.bashrc"; grep -c "^# --- " "$HOME/.bashrc"')"
  for i in 1 2; do
    if ! devcontainer exec --container-id "$cid" -- bash -c 'cd /workspace && bash .devcontainer/post-create.sh' \
        >"$COPY/post-create-$i.stdout" 2>"$COPY/post-create-$i.stderr"; then
      tail -80 "$COPY/post-create-$i.stderr" >&2 || true
      tail -80 "$COPY/post-create-$i.stdout" >&2 || true
      die "manual post-create run $i failed"
    fi
  done
  after="$(devcontainer exec --container-id "$cid" -- bash -c 'wc -l < "$HOME/.bashrc"; grep -c "^# --- " "$HOME/.bashrc"')"
  [ "$before" = "$after" ] || die ".bashrc changed after repeated post-create ($before -> $after)"
  grep -q 'specify-cli already installed' "$COPY/post-create-2.stdout" \
    || die "post-create did not skip the existing specify-cli install"
  if grep -q 'Installed 1 executable' "$COPY/post-create-2.stdout"; then
    die "post-create reinstalled specify-cli on the second run"
  fi
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
  build) run_static; run_build ;;
  pre) last_copy; run_up skip; run_pre_smoke ;;
  up) last_copy; run_up; run_smoke ;;
  smoke) last_copy; run_smoke ;;
  smoke-real) run_smoke ;;
  idempotent) last_copy; run_idempotent ;;
  recreate) last_copy; run_recreate ;;
  fresh) last_copy; run_fresh ;;
  cleanup) run_cleanup ;;
  all)
    run_guard_test
    run_static
    run_build
    run_up skip
    run_pre_smoke
    run_up
    run_smoke
    run_idempotent
    run_recreate
    run_fresh
    ;;
  *) die "unknown mode: $MODE (use guard|static|build|pre|up|smoke|smoke-real|idempotent|recreate|fresh|cleanup|all)" ;;
esac
