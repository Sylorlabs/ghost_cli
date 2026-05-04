#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ghost_bin="$repo_root/zig-out/bin/ghost"

if [[ ! -x "$ghost_bin" ]]; then
    echo "error: required CLI binary is missing or not executable: $ghost_bin" >&2
    echo "hint: run 'zig build' in ghost_cli first, or use 'zig build smoke-artifact-autopsy-cli'." >&2
    exit 1
fi

engine_root=""
if [[ -x "$repo_root/../ghost_engine/zig-out/bin/ghost_gip" ]]; then
    engine_root="$(cd "$repo_root/../ghost_engine" && pwd)"
elif [[ -n "${GHOST_ENGINE_ROOT:-}" ]]; then
    if [[ -x "$GHOST_ENGINE_ROOT/zig-out/bin/ghost_gip" || -x "$GHOST_ENGINE_ROOT/ghost_gip" ]]; then
        engine_root="$GHOST_ENGINE_ROOT"
    fi
fi

if [[ -z "$engine_root" ]]; then
    echo "error: built ghost_engine ghost_gip was not found." >&2
    echo "hint: build adjacent ../ghost_engine with 'zig build', or set GHOST_ENGINE_ROOT to a built engine root or bin dir." >&2
    exit 1
fi

if [[ -x "$engine_root/zig-out/bin/ghost_gip" ]]; then
    ghost_gip="$engine_root/zig-out/bin/ghost_gip"
elif [[ -x "$engine_root/ghost_gip" ]]; then
    ghost_gip="$engine_root/ghost_gip"
else
    echo "error: ghost_gip disappeared after engine root detection: $engine_root" >&2
    exit 1
fi

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/ghost-aa-cli-smoke.XXXXXX")"
cleanup() {
    rm -rf "$tmp_root"
}
trap cleanup EXIT

workspace="$tmp_root/workspace"
mkdir -p "$workspace"

cat > "$tmp_root/fixture.json" <<'JSON'
{"gipVersion":"gip.v0.1","kind":"artifact.autopsy.inspect"}
JSON

cat > "$workspace/docs.md" <<'EOF'
# Artifact Autopsy CLI

Run `zig build smoke-artifact-autopsy-cli` for explicit local smoke checks.
The output remains READ-ONLY, NON-AUTHORIZING, and CANDIDATE ONLY.
EOF
cat > "$tmp_root/documentation_audit.json" <<'JSON'
{"gipVersion":"gip.v0.1","kind":"artifact.autopsy.inspect","domain":"documentation_audit","artifactPaths":["docs.md"]}
JSON

cat > "$workspace/unused.md" <<'EOF'
# Pancakes

## Ingredients
- flour
- milk
- butter

## Steps
Mix flour and milk.
Cook batter.
EOF
cat > "$tmp_root/unused_ingredient.json" <<'JSON'
{"gipVersion":"gip.v0.1","kind":"artifact.autopsy.inspect","domain":"recipe_consistency","artifactPaths":["unused.md"]}
JSON

cat > "$workspace/missing.md" <<'EOF'
# Sauce

## Ingredients
- tomato

## Steps
Add salt to tomato.
EOF
cat > "$tmp_root/missing_ingredient.json" <<'JSON'
{"gipVersion":"gip.v0.1","kind":"artifact.autopsy.inspect","domain":"recipe_consistency","artifactPaths":["missing.md"]}
JSON

cat > "$tmp_root/path_traversal.json" <<'JSON'
{"gipVersion":"gip.v0.1","kind":"artifact.autopsy.inspect","domain":"documentation_audit","artifactPaths":["../outside.md"]}
JSON

assert_contains() {
    local file="$1"
    local expected="$2"
    if ! grep -Fq "$expected" "$file"; then
        echo "error: expected '$expected' in $file" >&2
        echo "---- $file ----" >&2
        cat "$file" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq "$unexpected" "$file"; then
        echo "error: did not expect '$unexpected' in $file" >&2
        echo "---- $file ----" >&2
        cat "$file" >&2
        exit 1
    fi
}

run_cli() {
    local name="$1"
    local request="$2"
    shift 2
    "$ghost_bin" artifact autopsy inspect --engine-root="$engine_root" --file "$request" "$@" \
        > "$tmp_root/$name.out" \
        2> "$tmp_root/$name.err"
}

run_cli fixture "$tmp_root/fixture.json"
assert_contains "$tmp_root/fixture.out" "Artifact Autopsy Result / CANDIDATE ONLY"
assert_contains "$tmp_root/fixture.out" "READ-ONLY"
assert_contains "$tmp_root/fixture.out" "NON-AUTHORIZING"
assert_contains "$tmp_root/fixture.out" "Fixture Backed: true"
assert_contains "$tmp_root/fixture.out" "Proof/Support:"
assert_contains "$tmp_root/fixture.out" "not granted"
assert_not_contains "$tmp_root/fixture.out" "Verified"
assert_not_contains "$tmp_root/fixture.out" "Support Granted: true"
assert_not_contains "$tmp_root/fixture.out" "Proof Granted: true"

run_cli documentation "$tmp_root/documentation_audit.json" --workspace "$workspace"
assert_contains "$tmp_root/documentation.out" "Artifact Domain:"
assert_contains "$tmp_root/documentation.out" "documentation_audit"
assert_contains "$tmp_root/documentation.out" "File Backed: true"
assert_contains "$tmp_root/documentation.out" "docs.md"
assert_not_contains "$tmp_root/documentation.out" "Verified"

run_cli unused "$tmp_root/unused_ingredient.json" --workspace "$workspace"
assert_contains "$tmp_root/unused.out" "recipe_consistency"
assert_contains "$tmp_root/unused.out" "unused_ingredient"
assert_contains "$tmp_root/unused.out" "butter"
assert_not_contains "$tmp_root/unused.out" "Verified"

run_cli missing "$tmp_root/missing_ingredient.json" --workspace "$workspace"
assert_contains "$tmp_root/missing.out" "recipe_consistency"
assert_contains "$tmp_root/missing.out" "missing_ingredient"
assert_contains "$tmp_root/missing.out" "salt"
assert_not_contains "$tmp_root/missing.out" "Verified"

run_cli traversal "$tmp_root/path_traversal.json" --workspace "$workspace"
assert_contains "$tmp_root/traversal.out" "Engine Error:"
assert_contains "$tmp_root/traversal.out" "invalid_request"
assert_contains "$tmp_root/traversal.out" "path traversal is rejected for artifact autopsy"
assert_contains "$tmp_root/traversal.out" "Proof/Support:"
assert_contains "$tmp_root/traversal.out" "not granted"
assert_not_contains "$tmp_root/traversal.out" "Verified"
assert_not_contains "$tmp_root/traversal.out" "Support Granted: true"
assert_not_contains "$tmp_root/traversal.out" "Proof Granted: true"

"$ghost_bin" artifact autopsy inspect --json --engine-root="$engine_root" --workspace "$workspace" --file "$tmp_root/documentation_audit.json" \
    > "$tmp_root/cli.json" \
    2> "$tmp_root/cli_json.err"
"$ghost_gip" --stdin --workspace "$workspace" \
    < "$tmp_root/documentation_audit.json" \
    > "$tmp_root/engine.json" \
    2> "$tmp_root/engine_json.err"
cmp -s "$tmp_root/cli.json" "$tmp_root/engine.json" || {
    echo "error: CLI --json output differed from direct ghost_gip output" >&2
    diff -u "$tmp_root/engine.json" "$tmp_root/cli.json" >&2 || true
    exit 1
}

echo "artifact autopsy CLI smoke checks passed"
echo "engine root: $engine_root"
