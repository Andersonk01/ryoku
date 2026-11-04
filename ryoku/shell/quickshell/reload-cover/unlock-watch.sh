#!/usr/bin/env bash
# [user] Replay the login intro after the screen unlocks.
#
# The reload cover only rises at login and on a shell reload; an unlock is
# neither, so the intro never showed there. qylock unlocks through
# `loginctl unlock-session`, which makes logind broadcast Session.Unlock on the
# system bus. This watcher waits for that signal, lets the lock surface go,
# then raises a reload cover tagged RYOKU_INTRO_REASON=unlock: its iris closes
# over the desktop, HackerIntro plays (with its sound), and shell.qml holds it
# for the intro's minimum hold before opening.
#
# ~/.config/ryoku/intro.json is read at each unlock, so the Hub's switches
# apply at once: it replays when "enabled" is true, "showMode" is "always"
# (first-login-only never replays) and "afterUnlock" is not false.
#
#   unlock-watch.sh          watch (intro-unlock.service runs this)
#   unlock-watch.sh --now    play the after-unlock intro once, right now
set -u

cfg="${XDG_CONFIG_HOME:-$HOME/.config}/ryoku/intro.json"
uid=$(id -u)

log() { printf 'intro-unlock: %s\n' "$*" >&2; }

wanted() {
    jq -e '(.enabled == true)
        and ((.showMode // "always") != "once")
        and (.afterUnlock != false)' "$cfg" >/dev/null 2>&1
}

locker_running() {
    pgrep -u "$uid" -f 'lock_shell\.qml' >/dev/null 2>&1
}

# A unit started before the session imported its environment would miss the
# compositor; take the few names the cover needs from the user manager, fresh
# each time (no eval: each line is a literal NAME=value).
refresh_env() {
    local line
    while IFS= read -r line; do
        case $line in
            WAYLAND_DISPLAY=*|HYPRLAND_INSTANCE_SIGNATURE=*|XDG_SESSION_ID=*|XDG_CURRENT_DESKTOP=*|XDG_SESSION_TYPE=*)
                export "${line?}" ;;
        esac
    done < <(systemctl --user show-environment 2>/dev/null)
}

play() {
    refresh_env
    [[ -n ${WAYLAND_DISPLAY:-} ]] || { log "no WAYLAND_DISPLAY; skipped"; return 0; }
    local tok
    if ! tok=$(RYOKU_INTRO_REASON=unlock ryoku-reload-cover begin reload 2>/dev/null); then
        log "cover did not rise (another cover up?); skipped"
        return 0
    fi
    # shell.qml answers false until the hold is over, then opens by itself;
    # the launcher's retries just give up quietly, so do not wait on them
    (ryoku-reload-cover finish "$tok" >/dev/null 2>&1 &)
    log "intro played"
}

after_unlock() {
    # only a real unlock: the lock client is still up when its unlock fires
    locker_running || return 0
    wanted || return 0
    # its reveal takes 0.1 to 2.3 s by theme; give it up to 5 s to leave
    local i
    for ((i = 0; i < 100; i++)); do
        locker_running || break
        sleep 0.05
    done
    if locker_running; then
        log "lock still up (a cancelled reveal?); skipped"
        return 0
    fi
    play
}

if [[ ${1:-} == --now ]]; then
    play
    exit 0
fi

refresh_env
path=""
if [[ -n ${XDG_SESSION_ID:-} ]]; then
    path=$(gdbus call --system --dest org.freedesktop.login1 \
        --object-path /org/freedesktop/login1 \
        --method org.freedesktop.login1.Manager.GetSession "$XDG_SESSION_ID" 2>/dev/null \
        | sed -n "s/^(objectpath '\(.*\)',)\$/\1/p")
fi
args=(monitor --system --dest org.freedesktop.login1)
[[ -n $path ]] && args+=(--object-path "$path")
log "watching ${path:-every login1 session} for unlocks"

# gdbus prints one line per signal, e.g.
#   /org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Unlock ()
while IFS= read -r line; do
    case $line in
        *.Session.Unlock\ \(*) after_unlock ;;
    esac
done < <(gdbus "${args[@]}")
log "monitor ended"
exit 1
