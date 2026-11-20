#!/usr/bin/env bash
# Usage as a command or source this file and call mixamo_auth_guard.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail
fi
mixamo_guard_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

mixamo_login_instructions() {
    local python=$1
    printf '%s\n' 'Mixamo requires an interactive Adobe sign-in or verification.' \
        'Run this as the pipeline service user in a graphical desktop session:' >&2
    printf '  cd %q\n  %q browser.py login\n' "$mixamo_guard_dir" "$python" >&2
    printf '%s\n' 'Complete the sign-in in the browser, then retry the Rails job.' >&2
}

check_mixamo_auth() {
    local python=${1:-${MIXAMO_PYTHON:-}}
    if [[ -z $python ]]; then
        python=$(env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$mixamo_guard_dir/setup_character.sh") || return "$?"
    fi
    env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$python" "$mixamo_guard_dir/browser.py" check
}

mixamo_auth_guard() {
    local python status
    python=${MIXAMO_PYTHON:-}
    if [[ -z $python ]]; then
        python=$(env -u MIXAMO_EMAIL -u MIXAMO_PASSWORD "$mixamo_guard_dir/setup_character.sh") || return "$?"
    fi
    if check_mixamo_auth "$python"; then
        return 0
    else
        status=$?
    fi
    # Only an explicit authentication failure should start a sign-in attempt.
    if (( status != 42 )); then
        return "$status"
    fi
    printf '%s\n' 'Mixamo session needs renewal. Attempting one non-interactive sign-in.' >&2
    if "$python" "$mixamo_guard_dir/browser.py" auto-login; then
        if check_mixamo_auth "$python"; then
            return 0
        else
            status=$?
        fi
    else
        status=$?
    fi
    if (( status == 42 )); then
        mixamo_login_instructions "$python"
    fi
    return "$status"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    mixamo_auth_guard
fi
