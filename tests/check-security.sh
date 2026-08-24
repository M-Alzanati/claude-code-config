#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/claude-config-security.XXXXXX) || exit 1
trap 'rm -rf "$TMP_ROOT"' 0 HUP INT TERM

passed=0
failed=0

run_test() {
    if "$2"; then
        printf 'ok - %s\n' "$1"
        passed=$((passed + 1))
    else
        printf 'not ok - %s\n' "$1"
        failed=$((failed + 1))
    fi
}

file_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

file_mode() {
    if stat -c %a "$1" >/dev/null 2>&1; then
        stat -c %a "$1"
    else
        stat -f %Lp "$1"
    fi
}

make_config_fixture() {
    fixture=$1
    mkdir -p "$fixture"
    cp "$ROOT/check.sh" "$ROOT/settings.json" "$ROOT/statusline.sh" "$ROOT/.gitignore" "$ROOT/README.md" "$fixture/"
    cp -R "$ROOT/hooks" "$fixture/"
    cp -R "$ROOT/output-styles" "$fixture/"
    chmod +x "$fixture/check.sh" "$fixture/statusline.sh" "$fixture/hooks/"*.sh
    git -C "$fixture" init -q
    git -C "$fixture" add .
}

check_output_has_secret_failure() {
    fixture=$1
    output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  no secrets in Git index'
}

test_staged_secret() {
    fixture="$TMP_ROOT/staged"
    make_config_fixture "$fixture"
    printf '%s\n' "gh""p_12345678901234567890" > "$fixture/README.md"
    git -C "$fixture" add README.md
    check_output_has_secret_failure "$fixture"
}

test_committed_secret() {
    fixture="$TMP_ROOT/committed"
    make_config_fixture "$fixture"
    git -C "$fixture" -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.invalid commit -qm baseline
    printf '%s\n' "A""KIA1234567890123456" > "$fixture/README.md"
    git -C "$fixture" add README.md
    git -C "$fixture" -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.invalid commit -qm secret
    check_output_has_secret_failure "$fixture"
}

test_github_token_families() {
    for entry in \
        "github-fine:github""_pat_1234567890ABCDEFGHIJ_1234567890" \
        "github-oauth:gh""o_12345678901234567890" \
        "github-server:gh""s_12345678901234567890" \
        "github-user:gh""u_12345678901234567890" \
        "github-refresh:gh""r_12345678901234567890"
    do
        name=${entry%%:*}
        token=${entry#*:}
        fixture="$TMP_ROOT/$name"
        make_config_fixture "$fixture"
        printf '%s\n' "$token" > "$fixture/README.md"
        git -C "$fixture" add README.md
        check_output_has_secret_failure "$fixture" || return 1
    done
}

test_aws_token_families() {
    for entry in \
        "aws-permanent:A""KIA1234567890123456" \
        "aws-temporary:A""SIA1234567890123456"
    do
        name=${entry%%:*}
        token=${entry#*:}
        fixture="$TMP_ROOT/$name"
        make_config_fixture "$fixture"
        printf '%s\n' "$token" > "$fixture/README.md"
        git -C "$fixture" add README.md
        check_output_has_secret_failure "$fixture" || return 1
    done
}

test_binary_staged_secret() {
    fixture="$TMP_ROOT/binary-secret"
    make_config_fixture "$fixture"
    printf '\000%s\n' "github""_pat_1234567890ABCDEFGHIJ_1234567890" > "$fixture/README.md"
    git -C "$fixture" add README.md
    check_output_has_secret_failure "$fixture"
}

test_scanner_error_fails_closed() {
    fixture="$TMP_ROOT/scanner-error"
    make_config_fixture "$fixture"
    real_git=$(command -v git)
    mkdir -p "$fixture/fake-bin"
    sed "s|@REAL_GIT@|$real_git|" > "$fixture/fake-bin/git" <<'EOF'
#!/bin/sh
case " $* " in *" grep "*) exit 2 ;; esac
exec "@REAL_GIT@" "$@"
EOF
    chmod +x "$fixture/fake-bin/git"
    output=$(PATH="$fixture/fake-bin:$PATH" CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  Git index secret scan completed'
}

test_rtk_does_not_approve() {
    mkdir -p "$TMP_ROOT/rtk-bin"
    cat > "$TMP_ROOT/rtk-bin/rtk" <<'EOF'
#!/bin/sh
case "$1" in
    --version) printf '%s\n' 'rtk 0.23.0' ;;
    rewrite) printf 'rtk %s\n' "$2" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TMP_ROOT/rtk-bin/rtk"
    output=$(printf '%s\n' '{"tool_input":{"command":"echo hello"}}' |
        PATH="$TMP_ROOT/rtk-bin:$PATH" "$ROOT/hooks/rtk-rewrite.sh") || return 1
    printf '%s\n' "$output" | jq -e '
        .hookSpecificOutput.updatedInput.command == "rtk echo hello" and
        (.hookSpecificOutput | has("permissionDecision") | not) and
        (.hookSpecificOutput | has("permissionDecisionReason") | not)
    ' >/dev/null
}

test_output_style_file_is_present() {
    style=$(jq -r '.outputStyle // empty' "$ROOT/settings.json") || return 1
    [ -n "$style" ] || return 1
    [ -f "$ROOT/output-styles/$style.md" ] || return 1
    head -1 "$ROOT/output-styles/$style.md" | grep -q '^---$' || return 1
    grep -qx "name: $style" "$ROOT/output-styles/$style.md"
}

test_checker_rejects_missing_output_style() {
    fixture="$TMP_ROOT/nostyle"
    make_config_fixture "$fixture"
    rm -f "$fixture/output-styles/"*.md
    output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  output style file exists:'
}

test_settings_use_portable_paths() {
    jq -e '
        [(.hooks | to_entries[] | .value[] | .hooks[] | .command), .statusLine.command]
        | all(test("^(node )?\\\"\\$\\{CLAUDE_CONFIG_DIR:-\\$HOME/\\.claude\\}/[^\\\" ]+\\\"$"))
    ' "$ROOT/settings.json" >/dev/null
}

test_checker_rejects_nonportable_path() {
    fixture="$TMP_ROOT/nonportable"
    make_config_fixture "$fixture"
    jq '.statusLine.command = "~/.claude/statusline.sh"' "$fixture/settings.json" > "$fixture/settings.new"
    mv "$fixture/settings.new" "$fixture/settings.json"
    git -C "$fixture" add settings.json
    output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  portable config path:'
}

test_checker_rejects_unsafe_relative_paths() {
    for entry in \
        'absolute:/statusline.sh' \
        'dot:./statusline.sh' \
        'middle-dot:hooks/./output-style.sh' \
        'parent:../outside.sh' \
        'middle-parent:hooks/../statusline.sh'
    do
        name=${entry%%:*}
        relative=${entry#*:}
        fixture="$TMP_ROOT/unsafe-$name"
        make_config_fixture "$fixture"
        : > "$TMP_ROOT/outside.sh"
        jq --arg command "\"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/$relative\"" \
            '.statusLine.command = $command' "$fixture/settings.json" > "$fixture/settings.new"
        mv "$fixture/settings.new" "$fixture/settings.json"
        git -C "$fixture" add settings.json
        output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
        status=$?
        [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  safe config path:' || return 1
    done
}

test_checker_rejects_shell_metacharacters() {
    for entry in \
        'dollar:status$(id).sh' \
        'backtick:status`id`.sh' \
        'semicolon:status;id.sh' \
        'hash:status#id.sh'
    do
        name=${entry%%:*}
        relative=${entry#*:}
        fixture="$TMP_ROOT/metachar-$name"
        make_config_fixture "$fixture"
        : > "$fixture/$relative"
        jq --arg command "\"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/$relative\"" \
            '.statusLine.command = $command' "$fixture/settings.json" > "$fixture/settings.new"
        mv "$fixture/settings.new" "$fixture/settings.json"
        git -C "$fixture" add settings.json
        output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
        status=$?
        [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  safe config path:' || return 1
    done
}

test_malformed_hooks_fail_closed() {
    fixture="$TMP_ROOT/malformed-hooks"
    make_config_fixture "$fixture"
    jq '.hooks = "broken"' "$fixture/settings.json" > "$fixture/settings.new"
    mv "$fixture/settings.new" "$fixture/settings.json"
    git -C "$fixture" add settings.json
    output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  hook commands extracted'
}

test_extractor_tool_failures_fail_closed() {
    for tool in mktemp sed awk; do
        fixture="$TMP_ROOT/extractor-$tool"
        make_config_fixture "$fixture"
        mkdir -p "$fixture/fake-bin"
        cat > "$fixture/fake-bin/$tool" <<'EOF'
#!/bin/sh
exit 2
EOF
        chmod +x "$fixture/fake-bin/$tool"
        output=$(PATH="$fixture/fake-bin:$PATH" CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
        status=$?
        [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'FAIL  hook commands extracted' || return 1
    done
}

test_shasum_fallback() {
    fixture="$TMP_ROOT/shasum-fallback"
    make_config_fixture "$fixture"
    bin="$fixture/minimal-bin"
    mkdir -p "$bin"
    # node is in the list because settings.json declares node hooks and check.sh
    # parses them; this fixture is about shasum, not about a machine without node.
    for tool in awk basename cat git hostname jq ls mktemp node rm rmdir sed sh shasum sort tail whoami; do
        ln -s "$(command -v "$tool")" "$bin/$tool"
    done
    output=$(PATH="$bin" CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
    status=$?
    [ "$status" -eq 0 ] && printf '%s\n' "$output" | grep -q 'ok    rtk-rewrite.sh matches its recorded checksum'
}

test_path_fallback_runs() {
    home="$TMP_ROOT/home"
    fixture="$home/.claude"
    make_config_fixture "$fixture"
    command=$(jq -r '.statusLine.command' "$fixture/settings.json")
    ( unset CLAUDE_CONFIG_DIR
      printf '%s\n' '{}' | HOME="$home" sh -c "$command" >/dev/null 2>&1
    )
}

test_path_override_runs() {
    fixture="$TMP_ROOT/override"
    home="$TMP_ROOT/override-home"
    make_config_fixture "$fixture"
    mkdir -p "$home"
    command=$(jq -r '.statusLine.command' "$fixture/settings.json")
    printf '%s\n' '{}' | CLAUDE_CONFIG_DIR="$fixture" HOME="$home" sh -c "$command" >/dev/null 2>&1
}

test_statusline_plugin_path_fallback() {
    home="$TMP_ROOT/statusline-fallback-home"
    config="$home/.claude"
    mkdir -p "$config/plugins/marketplaces/ponytail/hooks"
    printf '%s\n' '#!/bin/sh' "printf 'FALLBACK_PLUGIN\\n'" \
        > "$config/plugins/marketplaces/ponytail/hooks/ponytail-statusline.sh"
    chmod +x "$config/plugins/marketplaces/ponytail/hooks/ponytail-statusline.sh"
    output=$(env -u CLAUDE_CONFIG_DIR HOME="$home" sh -c \
        "printf '%s\\n' '{}' | '$ROOT/statusline.sh'" 2>&1)
    printf '%s\n' "$output" | grep -q 'FALLBACK_PLUGIN'
}

test_statusline_plugin_path_override() {
    home="$TMP_ROOT/statusline-override-home"
    config="$TMP_ROOT/statusline-override-config"
    for entry in "$config:OVERRIDE_PLUGIN" "$home/.claude:HOME_PLUGIN"; do
        base=${entry%%:*}
        marker=${entry#*:}
        mkdir -p "$base/plugins/marketplaces/ponytail/hooks"
        printf '%s\n' '#!/bin/sh' "printf '$marker\\n'" \
            > "$base/plugins/marketplaces/ponytail/hooks/ponytail-statusline.sh"
        chmod +x "$base/plugins/marketplaces/ponytail/hooks/ponytail-statusline.sh"
    done
    output=$(printf '%s\n' '{}' | CLAUDE_CONFIG_DIR="$config" HOME="$home" \
        "$ROOT/statusline.sh" 2>&1)
    printf '%s\n' "$output" | grep -q 'OVERRIDE_PLUGIN' &&
        ! printf '%s\n' "$output" | grep -q 'HOME_PLUGIN'
}

test_template_path_fallback() {
    home="$TMP_ROOT/template-fallback-home"
    project="$TMP_ROOT/template-fallback-project"
    mkdir -p "$home/.claude/templates" "$project"
    git -C "$project" init -q
    output=$(cd "$project" && printf '%s\n' "{\"cwd\":\"$project\"}" |
        env -u CLAUDE_CONFIG_DIR HOME="$home" "$ROOT/hooks/suggest-claude-md.sh")
    printf '%s\n' "$output" | grep -Fq "$home/.claude/templates/CLAUDE.md"
}

test_template_path_override() {
    home="$TMP_ROOT/template-override-home"
    config="$TMP_ROOT/template-override-config"
    project="$TMP_ROOT/template-override-project"
    mkdir -p "$home/.claude/templates" "$config/templates" "$project"
    git -C "$project" init -q
    output=$(cd "$project" && printf '%s\n' "{\"cwd\":\"$project\"}" |
        CLAUDE_CONFIG_DIR="$config" HOME="$home" "$ROOT/hooks/suggest-claude-md.sh")
    printf '%s\n' "$output" | grep -Fq "$config/templates/CLAUDE.md" &&
        ! printf '%s\n' "$output" | grep -Fq "$home/.claude/templates/CLAUDE.md"
}

make_src_fixture() {
    src=$1
    mkdir -p "$src/hooks" "$src/.githooks"
    cp "$ROOT/install.sh" "$ROOT/settings.json" "$src/"
    : > "$src/statusline.sh"
    : > "$src/hooks/noop.sh"
    : > "$src/.githooks/pre-commit"
    git -C "$src" init -q
    git -C "$src" add .
}

test_install_propagates_check_failure() {
    src="$TMP_ROOT/install-src"
    cfg="$TMP_ROOT/install-cfg"
    make_src_fixture "$src"
    mkdir -p "$cfg"
    cat > "$src/check.sh" <<'EOF'
#!/bin/sh
echo 'sentinel check failure'
exit 7
EOF
    output=$(CLAUDE_CONFIG_DIR="$cfg" sh "$src/install.sh" --yes --no-deps 2>&1)
    status=$?
    [ "$status" -ne 0 ] &&
        printf '%s\n' "$output" | grep -q 'sentinel check failure' &&
        printf '%s\n' "$output" | grep -q '(config has problems, see above)'
}

test_install_refuses_in_place_layout() {
    src="$TMP_ROOT/inplace-src"
    make_src_fixture "$src"
    output=$(CLAUDE_CONFIG_DIR="$src" sh "$src/install.sh" --yes --no-deps 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'this checkout is'
}

test_install_symlinks_assets_but_copies_settings() {
    src="$TMP_ROOT/link-src"
    cfg="$TMP_ROOT/link-cfg"
    make_src_fixture "$src"
    mkdir -p "$cfg"
    printf '#!/bin/sh\nexit 0\n' > "$src/check.sh"
    CLAUDE_CONFIG_DIR="$cfg" sh "$src/install.sh" --yes --no-deps >/dev/null 2>&1 || return 1
    [ -L "$cfg/hooks" ] || return 1
    [ "$(readlink "$cfg/hooks")" = "$src/hooks" ] || return 1
    [ -L "$cfg/statusline.sh" ] || return 1
    # settings.json must stay a real file: Claude Code rewrites it in place.
    [ -f "$cfg/settings.json" ] || return 1
    [ -L "$cfg/settings.json" ] && return 1
    cmp -s "$cfg/settings.json" "$src/settings.json"
}

test_install_merge_drops_removed_hook_events() {
    src="$TMP_ROOT/merge-src"
    cfg="$TMP_ROOT/merge-cfg"
    make_src_fixture "$src"
    mkdir -p "$cfg"
    printf '#!/bin/sh\nexit 0\n' > "$src/check.sh"
    # A stale event pointing at a script the repo no longer ships, plus a
    # machine-local key that must survive.
    jq '.hooks.UserPromptSubmit = [{"matcher":"*","hooks":[{"type":"command","command":"gone.sh"}]}]
        | .localOnlyKey = "keep me"' \
        "$src/settings.json" > "$cfg/settings.json"
    CLAUDE_CONFIG_DIR="$cfg" sh "$src/install.sh" --yes --no-deps >/dev/null 2>&1 || return 1
    jq -e '(.hooks | has("UserPromptSubmit") | not) and .localOnlyKey == "keep me"' \
        "$cfg/settings.json" >/dev/null
}

test_install_sweeps_legacy_repo_files() {
    src="$TMP_ROOT/legacy-src"
    cfg="$TMP_ROOT/legacy-cfg"
    make_src_fixture "$src"
    mkdir -p "$cfg/.github/workflows"
    printf '#!/bin/sh\nexit 0\n' > "$src/check.sh"
    # What the old in-place layout left sitting in ~/.claude.
    printf 'stale\n' > "$cfg/README.md"
    printf 'stale\n' > "$cfg/install.sh"
    printf 'stale\n' > "$cfg/LICENSE"
    printf 'stale\n' > "$cfg/.gitignore"
    printf 'stale\n' > "$cfg/.github/workflows/check.yml"
    printf 'mine\n' > "$cfg/settings.local.json"
    CLAUDE_CONFIG_DIR="$cfg" sh "$src/install.sh" --yes --no-deps >/dev/null 2>&1 || return 1
    for stale in README.md install.sh LICENSE .gitignore .github; do
        [ -e "$cfg/$stale" ] && return 1
    done
    # Swept, not deleted, and unrelated machine-local files stay put.
    [ -f "$cfg/backups/"*"/README.md" ] || return 1
    [ -f "$cfg/settings.local.json" ]
}

test_rtk_skips_shapes_it_mistranslates() {
    mkdir -p "$TMP_ROOT/rtk-skip-bin"
    # A stand-in that rewrites anything it is handed, so a rewrite here proves
    # the hook consulted rtk rather than skipping.
    cat > "$TMP_ROOT/rtk-skip-bin/rtk" <<'EOF'
#!/bin/sh
case "$1" in
    --version) printf '%s\n' 'rtk 0.23.0' ;;
    rewrite) printf 'rtk %s\n' "$2" ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$TMP_ROOT/rtk-skip-bin/rtk"
    # rtk turns each of these into a command it then rejects.
    for cmd in 'cat a.txt b.txt' 'tail -3 f.log' 'head -5 f.log' 'find . -name x -exec rm {} ;'; do
        out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' |
            PATH="$TMP_ROOT/rtk-skip-bin:$PATH" "$ROOT/hooks/rtk-rewrite.sh") || return 1
        [ -n "$out" ] && return 1
    done
    # Shapes rtk handles correctly must still be rewritten.
    for cmd in 'cat one.txt' 'git status'; do
        out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' |
            PATH="$TMP_ROOT/rtk-skip-bin:$PATH" "$ROOT/hooks/rtk-rewrite.sh") || return 1
        printf '%s\n' "$out" | jq -e --arg c "rtk $cmd" \
            '.hookSpecificOutput.updatedInput.command == $c' >/dev/null || return 1
    done
    return 0
}

test_install_merge_replaces_managed_blocks() {
    src="$TMP_ROOT/managed-src"
    cfg="$TMP_ROOT/managed-cfg"
    make_src_fixture "$src"
    mkdir -p "$cfg"
    printf '#!/bin/sh\nexit 0\n' > "$src/check.sh"
    # A plugin and marketplace the repo no longer declares, plus machine-local
    # keys that must survive the merge.
    jq '.enabledPlugins = {"gone@old": true}
        | .extraKnownMarketplaces = {"old": {"source": {"source": "github", "repo": "x/y"}}}
        | .env.LOCAL_ONLY = "1"
        | .localScalar = "keep"' \
        "$src/settings.json" > "$cfg/settings.json"
    CLAUDE_CONFIG_DIR="$cfg" sh "$src/install.sh" --yes --no-deps >/dev/null 2>&1 || return 1
    jq -e '(.enabledPlugins | has("gone@old") | not)
           and (.extraKnownMarketplaces | has("old") | not)
           and .env.LOCAL_ONLY == "1"
           and .localScalar == "keep"' "$cfg/settings.json" >/dev/null
}

test_checker_rejects_unparseable_hooks() {
    for broken in 'hooks/ecc/session-start.js:const x = {{{' 'hooks/suggest-claude-md.sh:if [ then fi done'; do
        rel=${broken%%:*}
        junk=${broken#*:}
        fixture="$TMP_ROOT/unparseable-$(printf '%s' "$rel" | tr / -)"
        make_config_fixture "$fixture"
        printf '%s\n' "$junk" >> "$fixture/$rel"
        output=$(CLAUDE_CONFIG_DIR="$fixture" "$fixture/check.sh" 2>&1)
        status=$?
        [ "$status" -ne 0 ] || return 1
        printf '%s\n' "$output" | grep -q "FAIL  parses: $rel" || return 1
    done
    return 0
}

test_checker_detects_symlink_drift() {
    src="$TMP_ROOT/drift-src"
    other="$TMP_ROOT/drift-other"
    cfg="$TMP_ROOT/drift-cfg"
    make_config_fixture "$src"
    mkdir -p "$other/hooks" "$cfg"
    # A second checkout on the same machine; ~/.claude is wired to the wrong one.
    ln -s "$other/hooks" "$cfg/hooks"
    cp "$src/settings.json" "$cfg/settings.json"
    output=$(CLAUDE_CONFIG_DIR="$cfg" "$src/check.sh" 2>&1)
    status=$?
    [ "$status" -ne 0 ] &&
        printf '%s\n' "$output" | grep -q 'FAIL  managed symlinks point at this checkout'
}

test_install_update_requires_upstream() {
    src="$TMP_ROOT/noupstream-src"
    cfg="$TMP_ROOT/noupstream-cfg"
    make_src_fixture "$src"
    mkdir -p "$cfg"
    output=$(CLAUDE_CONFIG_DIR="$cfg" sh "$src/install.sh" --update --yes --no-deps 2>&1)
    status=$?
    [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q 'no upstream branch'
}

test_ecc_config_dir_and_project_safe_sessions() {
    config="$TMP_ROOT/ecc-config"
    home="$TMP_ROOT/ecc-home"
    project_a="$TMP_ROOT/project-a"
    project_b="$TMP_ROOT/project-b"
    mkdir -p "$config" "$home" "$project_a" "$project_b"
    git -C "$project_a" init -q
    git -C "$project_b" init -q

    node - <<'NODE' "$ROOT/hooks/ecc/lib/utils.js" "$config"
const assert = require('assert');
const [utilsPath, config] = process.argv.slice(2);
process.env.CLAUDE_CONFIG_DIR = config;
const utils = require(utilsPath);
assert.strictEqual(utils.getClaudeDir(), config);
assert.strictEqual(utils.getSessionsDir(), require('path').join(config, 'sessions'));
assert.strictEqual(utils.getLearnedSkillsDir(), require('path').join(config, 'skills', 'learned'));
NODE

    transcript="$TMP_ROOT/transcript.jsonl"
    cat > "$transcript" <<'EOF'
{"type":"user","content":"TOP_SECRET_RAW_PROMPT_A"}
{"type":"tool_use","tool_name":"Edit","tool_input":{"file_path":"src/a.js"}}
EOF
    (cd "$project_a" && printf '%s\n' "{\"transcript_path\":\"$transcript\"}" |
        CLAUDE_CONFIG_DIR="$config" HOME="$home" CLAUDE_SESSION_ID='../../escape-a' \
        node "$ROOT/hooks/ecc/session-end.js" >/dev/null 2>&1)

    cat > "$transcript" <<'EOF'
{"type":"user","content":"TOP_SECRET_RAW_PROMPT_B"}
{"type":"tool_use","tool_name":"Write","tool_input":{"file_path":"src/b.js"}}
EOF
    (cd "$project_b" && printf '%s\n' "{\"transcript_path\":\"$transcript\"}" |
        CLAUDE_CONFIG_DIR="$config" HOME="$home" CLAUDE_SESSION_ID='../../escape-b' \
        node "$ROOT/hooks/ecc/session-end.js" >/dev/null 2>&1)

    files=$(find "$config/sessions" -type f -name '*-session.tmp' -print)
    [ "$(printf '%s\n' "$files" | sed '/^$/d' | wc -l)" -eq 2 ] || return 1
    ! printf '%s\n' "$files" | grep -q '/\.\./' || return 1
    ! grep -R -q 'TOP_SECRET_RAW_PROMPT_[AB]' "$config/sessions" || return 1
    grep -R -q 'ECC:SESSION-METADATA:v1' "$config/sessions" || return 1

    output_a=$(cd "$project_a" && CLAUDE_CONFIG_DIR="$config" HOME="$home" \
        node "$ROOT/hooks/ecc/session-start.js" 2>&1)
    printf '%s\n' "$output_a" | grep -q 'untrusted metadata' || return 1
    ! printf '%s\n' "$output_a" | grep -q 'TOP_SECRET_RAW_PROMPT_[AB]' || return 1
    ! printf '%s\n' "$output_a" | grep -q 'src/b.js' || return 1
    printf '%s\n' "$output_a" | grep -q 'src/a.js' || return 1

    file_a=$(grep -l 'src/a.js' "$config"/sessions/*-session.tmp)
    file_b=$(grep -l 'src/b.js' "$config"/sessions/*-session.tmp)
    before_a=$(file_size "$file_a")
    before_b=$(file_size "$file_b")
    (cd "$project_a" && CLAUDE_CONFIG_DIR="$config" HOME="$home" \
        node "$ROOT/hooks/ecc/pre-compact.js" >/dev/null 2>&1)
    after_a=$(file_size "$file_a")
    after_b=$(file_size "$file_b")
    [ "$after_a" -gt "$before_a" ] && [ "$after_b" -eq "$before_b" ]
}

test_ecc_legacy_summary_is_ignored() {
    config="$TMP_ROOT/ecc-legacy-config"
    home="$TMP_ROOT/ecc-legacy-home"
    project="$TMP_ROOT/ecc-legacy-project"
    mkdir -p "$config/sessions" "$home" "$project"
    git -C "$project" init -q
    printf '%s\n' 'TOP_SECRET_LEGACY_SUMMARY' > "$config/sessions/9999999999-session.tmp"
    output=$(cd "$project" && CLAUDE_CONFIG_DIR="$config" HOME="$home" \
        node "$ROOT/hooks/ecc/session-start.js" 2>&1)
    ! printf '%s\n' "$output" | grep -q 'TOP_SECRET_LEGACY_SUMMARY'
}

test_ecc_counter_is_config_local() {
    config="$TMP_ROOT/ecc-counter-config"
    home="$TMP_ROOT/ecc-counter-home"
    session="counter-$(date +%s)-$$"
    mkdir -p "$config" "$home"
    rm -f "/tmp/claude-tool-count-$session"
    CLAUDE_CONFIG_DIR="$config" HOME="$home" CLAUDE_SESSION_ID="$session" \
        node "$ROOT/hooks/ecc/suggest-compact.js" >/dev/null 2>&1
    [ ! -e "/tmp/claude-tool-count-$session" ] || return 1
    [ "$(find "$config" -type f -name '*tool-count*' | wc -l)" -eq 1 ]
}

test_ecc_private_storage_and_compaction_isolation() {
    config="$TMP_ROOT/ecc-private-config"
    home="$TMP_ROOT/ecc-private-home"
    project_a="$TMP_ROOT/private-project-a"
    project_b="$TMP_ROOT/private-project-b"
    mkdir -p "$config" "$home" "$project_a" "$project_b"
    git -C "$project_a" init -q
    git -C "$project_b" init -q
    transcript="$TMP_ROOT/private-transcript.jsonl"
    printf '%s\n' '{"type":"user","content":"PRIVATE_RAW_PROMPT"}' > "$transcript"
    for project in "$project_a" "$project_b"; do
        (cd "$project" && printf '%s\n' "{\"transcript_path\":\"$transcript\"}" |
            CLAUDE_CONFIG_DIR="$config" HOME="$home" node "$ROOT/hooks/ecc/session-end.js" >/dev/null 2>&1) || return 1
    done

    [ "$(file_mode "$config/sessions")" = 700 ] || return 1
    session_files=$(find "$config/sessions" -type f -name '*-session.tmp' -print)
    for file in $session_files; do
        [ "$(file_mode "$file")" = 600 ] || return 1
    done

    key_a=$(cd "$project_a" && CLAUDE_CONFIG_DIR="$config" node -e "process.stdout.write(require('$ROOT/hooks/ecc/lib/utils').getProjectKey())")
    key_b=$(cd "$project_b" && CLAUDE_CONFIG_DIR="$config" node -e "process.stdout.write(require('$ROOT/hooks/ecc/lib/utils').getProjectKey())")
    log_a="$config/sessions/$key_a-compaction.log"
    log_b="$config/sessions/$key_b-compaction.log"
    (cd "$project_a" && CLAUDE_CONFIG_DIR="$config" HOME="$home" node "$ROOT/hooks/ecc/pre-compact.js" >/dev/null 2>&1) || return 1
    [ -f "$log_a" ] && [ ! -e "$log_b" ] || return 1
    [ "$(file_mode "$log_a")" = 600 ] || return 1

    target="$TMP_ROOT/private-target"
    mkdir -p "$target"
    rm -f "$config/private"
    ln -s "$target" "$config/private"
    CLAUDE_CONFIG_DIR="$config" HOME="$home" CLAUDE_SESSION_ID=symlink-counter \
        node "$ROOT/hooks/ecc/suggest-compact.js" >/dev/null 2>&1
    [ "$(find "$target" -type f | wc -l)" -eq 0 ]
}

test_ecc_session_symlink_is_rejected() {
    config="$TMP_ROOT/ecc-session-symlink-config"
    home="$TMP_ROOT/ecc-session-symlink-home"
    project="$TMP_ROOT/ecc-session-symlink-project"
    target="$TMP_ROOT/ecc-session-symlink-target"
    mkdir -p "$config" "$home" "$project" "$target"
    git -C "$project" init -q
    ln -s "$target" "$config/sessions"
    CLAUDE_CONFIG_DIR="$config" HOME="$home" CLAUDE_SESSION_ID=symlink-session \
        node "$ROOT/hooks/ecc/session-end.js" >/dev/null 2>&1
    [ "$(find "$target" -type f | wc -l)" -eq 0 ]
}

test_ecc_replacement_repo_gets_new_key() {
    config="$TMP_ROOT/ecc-replacement-config"
    home="$TMP_ROOT/ecc-replacement-home"
    project="$TMP_ROOT/ecc-replacement-project"
    transcript="$TMP_ROOT/ecc-replacement-transcript.jsonl"
    mkdir -p "$config" "$home" "$project"
    git -C "$project" init -q
    printf 'old\n' > "$project/old.js"
    git -C "$project" add old.js
    git -C "$project" -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.invalid commit -qm old
    printf '%s\n' '{"type":"tool_use","tool_name":"Edit","tool_input":{"file_path":"old.js"}}' > "$transcript"
    (cd "$project" && printf '%s\n' "{\"transcript_path\":\"$transcript\"}" |
        CLAUDE_CONFIG_DIR="$config" HOME="$home" node "$ROOT/hooks/ecc/session-end.js" >/dev/null 2>&1) || return 1
    old_key=$(cd "$project" && CLAUDE_CONFIG_DIR="$config" node -e "process.stdout.write(require('$ROOT/hooks/ecc/lib/utils').getProjectKey())")
    old_session="$config/sessions/$old_key-session.tmp"
    [ -f "$old_session" ] || return 1
    printf 'stable\n' > "$project/stable.js"
    git -C "$project" add stable.js
    git -C "$project" -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.invalid commit -qm stable
    stable_key=$(cd "$project" && CLAUDE_CONFIG_DIR="$config" node -e "process.stdout.write(require('$ROOT/hooks/ecc/lib/utils').getProjectKey())")
    [ "$old_key" = "$stable_key" ] || return 1
    rm -rf "$project/.git"
    git -C "$project" init -q
    printf 'new\n' > "$project/new.js"
    git -C "$project" add new.js
    git -C "$project" -c core.hooksPath=/dev/null -c user.name=test -c user.email=test@example.invalid commit -qm new
    new_key=$(cd "$project" && CLAUDE_CONFIG_DIR="$config" node -e "process.stdout.write(require('$ROOT/hooks/ecc/lib/utils').getProjectKey())")
    [ "$old_key" != "$new_key" ] || return 1
    new_session="$config/sessions/$new_key-session.tmp"
    [ "$old_session" != "$new_session" ] && [ -f "$old_session" ] || return 1
    output=$(cd "$project" && CLAUDE_CONFIG_DIR="$config" HOME="$home" node "$ROOT/hooks/ecc/session-start.js" 2>&1)
    ! printf '%s\n' "$output" | grep -q 'old.js' &&
        ! printf '%s\n' "$output" | grep -q '\[SessionStart\] Error:'
}

run_test 'normally staged secrets are rejected' test_staged_secret
run_test 'already committed secrets are rejected' test_committed_secret
run_test 'GitHub token families are rejected' test_github_token_families
run_test 'AWS access-key families are rejected' test_aws_token_families
run_test 'binary-classified staged secrets are rejected' test_binary_staged_secret
run_test 'Git scanner errors fail closed' test_scanner_error_fails_closed
run_test 'RTK rewrites without approving' test_rtk_does_not_approve
run_test 'configured output style ships with the config' test_output_style_file_is_present
run_test 'checker rejects a missing output style file' test_checker_rejects_missing_output_style
run_test 'settings commands use the portable config expression' test_settings_use_portable_paths
run_test 'checker rejects nonportable command paths' test_checker_rejects_nonportable_path
run_test 'checker rejects unsafe relative paths' test_checker_rejects_unsafe_relative_paths
run_test 'checker rejects shell metacharacters' test_checker_rejects_shell_metacharacters
run_test 'malformed hooks fail closed' test_malformed_hooks_fail_closed
run_test 'extractor tool failures fail closed' test_extractor_tool_failures_fail_closed
run_test 'checksum verification falls back to shasum' test_shasum_fallback
run_test 'settings command falls back to HOME/.claude' test_path_fallback_runs
run_test 'settings command honors CLAUDE_CONFIG_DIR' test_path_override_runs
run_test 'statusline plugin lookup falls back to HOME/.claude' test_statusline_plugin_path_fallback
run_test 'statusline plugin lookup honors CLAUDE_CONFIG_DIR' test_statusline_plugin_path_override
run_test 'template prompt falls back to HOME/.claude' test_template_path_fallback
run_test 'template prompt honors CLAUDE_CONFIG_DIR' test_template_path_override
run_test 'installer propagates post-install check failures' test_install_propagates_check_failure
run_test 'installer refuses the legacy in-place layout' test_install_refuses_in_place_layout
run_test 'installer symlinks assets and copies settings.json' test_install_symlinks_assets_but_copies_settings
run_test 'installer --update requires an upstream branch' test_install_update_requires_upstream
run_test 'settings merge drops hook events the repo removed' test_install_merge_drops_removed_hook_events
run_test 'installer sweeps legacy in-place repo files' test_install_sweeps_legacy_repo_files
run_test 'RTK hook skips shapes rtk mistranslates' test_rtk_skips_shapes_it_mistranslates
run_test 'settings merge replaces repo-managed blocks' test_install_merge_replaces_managed_blocks
run_test 'checker rejects hooks that do not parse' test_checker_rejects_unparseable_hooks
run_test 'checker detects symlinks into another checkout' test_checker_detects_symlink_drift
run_test 'ECC sessions use config-local project-safe metadata' test_ecc_config_dir_and_project_safe_sessions
run_test 'legacy ECC summaries are ignored' test_ecc_legacy_summary_is_ignored
run_test 'compact counters are config-local' test_ecc_counter_is_config_local
run_test 'ECC private storage and project compaction logs are isolated' test_ecc_private_storage_and_compaction_isolation
run_test 'ECC rejects symlinked session directories' test_ecc_session_symlink_is_rejected
run_test 'replacement repositories get a new session key' test_ecc_replacement_repo_gets_new_key

printf '%s passed; %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
