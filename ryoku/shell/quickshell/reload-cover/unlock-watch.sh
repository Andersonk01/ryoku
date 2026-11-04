#!/usr/bin/env bash
# [user] Replay the login intro after the screen unlocks.
#
# The reload cover only rises at login and on a shell reload; an unlock is
# neither, so the intro never showed there. Raising a cover only once the
# unlock happened showed the desktop for about a second first (the lock
# leaves in ~0.1 s, a fresh cover needs ~0.4 s to map and its iris 0.5 s to
# close). So the cover is readied while the screen is still locked:
#
#   lock   qylock publishes its proof ($XDG_RUNTIME_DIR/qylock.<session>.locked)
#          once the compositor confirms the lock; that starts unlock.qml,
#          which maps a black cover per screen under the lock surface, with
#          the intro paused on its first frame.
#   unlock qylock unlocks through `loginctl unlock-session`, so logind
#          broadcasts Session.Unlock; the readied cover hears it itself and
#          starts the intro, which is already playing when the lock goes.
#
# If no cover was readied (inotifywait missing, a lock older than this
# watcher), the unlock falls back to a reload cover tagged
# RYOKU_INTRO_REASON=unlock: its iris closes over the desktop.
#
# ~/.config/ryoku/intro.json is read at each lock, so the Hub's switches apply
# at once: it replays when "enabled" is true, "showMode" is "always"
# (first-login-only never replays) and "afterUnlock" is not false.
#
#   unlock-watch.sh          watch (intro-unlock.service runs this)
#   unlock-watch.sh --now    play the after-unlock intro once, right now
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/ryoku/intro.json"
uid=$(id -u)
standby_pid=""

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
    # the cover imports Ryoku.Ui; a checkout deploy keeps it under ~/.local
    if [[ -d $HOME/.local/lib/qt6/qml && :${QML_IMPORT_PATH:-}: != *":$HOME/.local/lib/qt6/qml:"* ]]; then
        export QML_IMPORT_PATH="${QML_IMPORT_PATH:+$QML_IMPORT_PATH:}$HOME/.local/lib/qt6/qml"
        export QML2_IMPORT_PATH="${QML2_IMPORT_PATH:+$QML2_IMPORT_PATH:}$HOME/.local/lib/qt6/qml"
    fi
}

standby_alive() {
    [[ -n $standby_pid ]] && kill -0 "$standby_pid" 2>/dev/null
}

# Ready the cover behind the lock. extra: more env for the cover (tests).
start_standby() {
    standby_alive && return 0
    refresh_env
    [[ -n ${WAYLAND_DISPLAY:-} ]] || { log "no WAYLAND_DISPLAY; not readied"; return 1; }
    setsid env RYOKU_RELOAD_COVER_MODE=boot RYOKU_INTRO_REASON=unlock \
        RYOKU_INTRO_SESSION_PATH="$path" RYOKU_INTRO_LOCK_MARKER="$marker" "$@" \
        qs -p "$here/unlock.qml" >/dev/null 2>&1 </dev/null &
    standby_pid=$!
    log "cover readied behind the lock (pid $standby_pid)"
}

# The fallback: a reload cover after the lock has gone.
play_fallback() {
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
    log "intro played (fallback)"
}

on_lock() {
    wanted || return 0
    start_standby || true
}

on_unlock() {
    # the readied cover starts on this same signal by itself
    if standby_alive; then
        return 0
    fi
    # only a real unlock: the lock client is still up when its unlock fires
    locker_running || return 0
    wanted || return 0
    local i
    for ((i = 0; i < 100; i++)); do
        locker_running || break
        sleep 0.05
    done
    if locker_running; then
        log "lock still up (a cancelled reveal?); skipped"
        return 0
    fi
    play_fallback
}

refresh_env
sid="${XDG_SESSION_ID:-}"
# where qylock keeps its proof (RYOKU_INTRO_LOCK_DIR: tests only)
rt="${RYOKU_INTRO_LOCK_DIR:-${XDG_RUNTIME_DIR:-/run/user/$uid}}"
marker=""
[[ -n $sid ]] && marker="$rt/qylock.$sid.locked"
path=""
if [[ -n $sid ]]; then
    path=$(gdbus call --system --dest org.freedesktop.login1 \
        --object-path /org/freedesktop/login1 \
        --method org.freedesktop.login1.Manager.GetSession "$sid" 2>/dev/null \
        | sed -n "s/^(objectpath '\(.*\)',)\$/\1/p")
fi

if [[ ${1:-} == --now ]]; then
    # the readied cover, released by itself after a moment (no lock needed)
    start_standby RYOKU_INTRO_AUTORELEASE_MS=700 RYOKU_INTRO_LOCK_MARKER=
    exit 0
fi

args=(monitor --system --dest org.freedesktop.login1)
[[ -n $path ]] && args+=(--object-path "$path")
log "watching ${path:-every login1 session} for unlocks"

# Both sources feed one line stream: "lock" when the proof is published (it
# lands by rename), "unlock" on logind's signal, e.g.
#   /org/freedesktop/login1/session/_33: org.freedesktop.login1.Session.Unlock ()
events() {
    stdbuf -oL gdbus "${args[@]}" 2>/dev/null \
        | sed -u -n 's/.*\.Session\.Unlock (.*/unlock/p' &
    if [[ -n $sid ]] && command -v inotifywait >/dev/null 2>&1; then
        inotifywait -m -q -e create -e moved_to --format '%f' "$rt" 2>/dev/null \
            | sed -u -n "s/^qylock\\.${sid}\\.locked\$/lock/p" &
    else
        log "inotifywait missing: the intro will follow the unlock (fallback)"
    fi
    # already locked when the watcher started
    [[ -n $marker && -e $marker ]] && echo lock
    wait -n
    kill $(jobs -p) 2>/dev/null
}

while IFS= read -r ev; do
    case $ev in
        lock) on_lock ;;
        unlock) on_unlock ;;
    esac
done < <(events)
log "monitor ended"
exit 1
