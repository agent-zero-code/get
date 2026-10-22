#!/bin/bash
# Set up Agent Zero Code — double-click me (on a Mac).
#
# It checks what this Mac needs, one thing at a time, and installs whatever is missing by itself. Each
# piece is fetched from its maker's own server and checked before it is used: against the maker's own
# checksum, and against the maker's signature where the maker signs. A piece that fails a check is not
# installed. It asks for no password and never uses sudo: small tools go in your own home folder
# (~/.local), VS Code goes in Applications. What only you can do stays yours: Apple's own Install
# button for its developer tools, and signing in (to GitHub, to Claude) in your own browser.
#
# Handed the whole folder (on a drive, say): that folder installs your agent by itself. It carries a
# fingerprint for every file in it (TRUTH.txt); this file checks the folder against them first and
# installs nothing from a folder that does not match. No GitHub is needed to have a working agent.
# GitHub is only where improvements come from afterwards: this file offers to connect this Mac to it,
# and your agent works either way. Handed only this one file, it installs from GitHub, by invitation.
#
#   SETUP_CHECK_ONLY=1 bash "Set up Agent Zero Code.command"     look and report; change and open nothing
#
# Exit 0 everything is in place · 1 something is still missing (it says what) · 2 this is not a Mac.

set -u
CHECK="${SETUP_CHECK_ONLY:-}"
HOME_DIR="${SETUP_HOME:-$HOME}"
LBIN="$HOME_DIR/.local/bin"; SHARE="$HOME_DIR/.local/share/agent-zero-code"
# A window opened by a double-click does not always know where newly installed tools live.
PATH="${SETUP_PATH:-$PATH:/usr/local/bin:/opt/homebrew/bin}:$LBIN"; export PATH
REPO="agent-zero-code/agent-zero-code"; PLUGIN="agent-zero-code@zero-code-hub"
[ "$(uname -s)" = "Darwin" ] || [ -n "${SETUP_ANY_OS:-}" ] || { echo "This setup file is for a Mac. On another computer, ask the person who invited you."; exit 2; }
# The makers' signing teams, as Apple records them: Node.js Foundation, GitHub, Microsoft.
TEAM_NODE="HX7739G8FX"; TEAM_GH="VEKTX9H2N7"; TEAM_CODE="UBF8T346G9"
# ── pins ──
# The exact version of every piece this file fetches, and the fingerprint (sha256) each download must have, for both kinds of Mac.
# Each was read from its maker's own server and then fetched and checked once before this copy was handed on. Nothing here
# follows "the newest": a piece that changes is a piece nobody tried. To move a pin: core/tools/pins-check.mjs says what is
# newer and proves a new line by fetching it. (The SETUP_PIN_ names are how the checks stand in made-up downloads.)
PIN_NODE="${SETUP_PIN_NODE:-24.21.0}"
PIN_NODE_arm64="${SETUP_PIN_NODE_arm64:-bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057}"
PIN_NODE_x64="${SETUP_PIN_NODE_x64:-1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097}"
PIN_JQ="${SETUP_PIN_JQ:-1.8.2}"
PIN_JQ_arm64="${SETUP_PIN_JQ_arm64:-2d75340ba57a4b4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e}"
PIN_JQ_amd64="${SETUP_PIN_JQ_amd64:-e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0}"
PIN_GH="${SETUP_PIN_GH:-2.102.0}"
PIN_GH_arm64="${SETUP_PIN_GH_arm64:-da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e}"
PIN_GH_amd64="${SETUP_PIN_GH_amd64:-b245f24eb2bf5f75b426b4c26da3651a107f8d5b6f4fddfbfccc5679041378b3}"
PIN_CODE="${SETUP_PIN_CODE:-1.141.0}"
PIN_CODE_darwin_arm64="${SETUP_PIN_CODE_darwin_arm64:-9b4ae386e3cf738d7ba990237ddf0a18092c924a1bcae465ed4697964745f42d}"
PIN_CODE_darwin="${SETUP_PIN_CODE_darwin:-c1b3950fbe76dcb14a5eaebb9834c3b87bc28bf54b2ad7953e0e6eda268150b6}"
PIN_CLAUDE="${SETUP_PIN_CLAUDE:-2.1.293}"
pin_sum() { local v; v="PIN_$1_$(printf '%s' "$2" | tr '-' '_')"; printf '%s' "${!v:-}" | grep -Ex '[0-9a-f]{64}'; }   # a piece, a kind of Mac
APPS="${SETUP_APPS:-/Applications}"; APP_NAME="Visual Studio Code.app"
if [ -n "${SETUP_ARCH:-}" ]; then ARCH="$SETUP_ARCH"; elif [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then ARCH="arm64"; else ARCH="x64"; fi
if [ "$ARCH" = "arm64" ]; then GARCH="arm64"; CODE_FOR="darwin-arm64"; else GARCH="amd64"; CODE_FOR="darwin"; fi
# A copy handed over as a folder: this file sits beside the catalogue and the program.
CONF="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}"; HUB="zero-code-hub"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"; KIT="${SETUP_KIT-$HERE}"
{ [ -n "$KIT" ] && [ -f "$KIT/.claude-plugin/marketplace.json" ] && [ -d "$KIT/plugins/agent-zero-code" ]; } || KIT=""

MISSING=0; N=0; ADDED=0; TMP=""; LATER=0
# ── led by a screen ──
# With SETUP_EVENTS naming a file, everything this run says is also written there, one line of JSON each, so a window of
# ours can show it. Then nothing waits on a keyboard: a wait is a look every few seconds, and a sign-in hands its code and
# its address to the screen. Without it, this file behaves exactly as it always has.
EVENTS="${SETUP_EVENTS:-}"; WAIT_MAX="${SETUP_WAIT_SECONDS:-1800}"
js() { printf '%s' "$1" | sed "s|$HOME_DIR|~|g" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }                     # words, made safe to sit inside JSON
ev() { [ -n "$EVENTS" ] || return 0; printf '{"k":"%s"%s}\n' "$1" "${2:+,$2}" >> "$EVENTS" 2>/dev/null; return 0; }   # a kind, then its fields
wait_for() { local w=0; until "$@" || [ "$w" -ge "$WAIT_MAX" ]; do sleep 5; w=$((w + 5)); done; "$@"; }                 # look again every few seconds, up to the limit
line() { printf '\n%s\n' "────────────────────────────────────────"; }
# What each step found is kept, with this home folder written as ~, for the first check-up at the end.
SEEN=""; seen() { SEEN="$SEEN  $1 $(printf '%s' "$2" | sed "s|$HOME_DIR|~|g")
"; }
ok()   { printf '  ✓  %s\n' "$1"; seen "✓" "$1"; ev ok "\"text\":\"$(js "$1")\""; }
no()   { printf '  ✗  %s\n' "$1"; MISSING=$((MISSING + 1)); seen "✗" "$1"; ev no "\"text\":\"$(js "$1")\""; }
# With a handed copy, GitHub is for improvements only: what is missing there is said, and does not stop the install.
gap()  { if [ -n "$KIT" ]; then printf '  ○  %s\n' "$1"; LATER=$((LATER + 1)); seen "○" "$1"; ev later "\"text\":\"$(js "$1")\""; else no "$1"; fi; }
note() { printf '     → %s\n' "$1"; ev note "\"text\":\"$(js "$1")\""; }
step() { N=$((N + 1)); printf '\n%s. %s\n' "$N" "$1"; ev step "\"n\":$N,\"title\":\"$(js "$1")\""; }
have() { command -v "$1" >/dev/null 2>&1; }
# Open a page and wait for the person; in a check-only run it just says where to go.
help_with() { # what to do, address
  if [ -n "$CHECK" ]; then printf '     → %s (%s)\n' "$1" "$2"; return; fi
  printf '     → %s\n       Opening %s\n' "$1" "$2"; open "$2" 2>/dev/null
  if [ -n "$EVENTS" ]; then ev do "\"text\":\"$(js "$1")\",\"url\":\"$(js "$2")\""; return; fi
  printf '       When that is done, come back here and press Return. '; read -r _
}
code_app() {
  if [ -n "${SETUP_VSCODE:-}" ]; then [ -d "$SETUP_VSCODE" ] && echo "$SETUP_VSCODE"; return; fi
  local a; for a in "$APPS/$APP_NAME" "$HOME_DIR/Applications/$APP_NAME"; do [ -d "$a" ] && { echo "$a"; return; }; done
  mdfind "kMDItemCFBundleIdentifier == 'com.microsoft.VSCode'" 2>/dev/null | head -1
}
# Claude Code inside VS Code: the newest copy by its version, never by its folder's name (claude_in_vscode, written in below by the build).
claude_bin() { claude_in_vscode "$HOME_DIR"; }

# ── fetching a piece from its maker, and checking it before it is used ──
work() { [ -n "$TMP" ] || { TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-zero-code-setup.XXXXXX")" && trap 'rm -rf "$TMP"' EXIT; }; [ -n "$TMP" ] && [ -d "$TMP" ]; }
fetch() { curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 20 -o "$2" "$1" 2>/dev/null; }                   # address, file
fetch_big() { curl -fL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 20 --progress-bar -o "$2" "$1"; }                # the same, showing how far it is
sum_ok() { [ -n "$2" ] && [ "$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)" = "$2" ]; }           # a file, the checksum it must have
signed_by() { codesign --verify --strict "$1" >/dev/null 2>&1 && codesign -dv --verbose=2 "$1" 2>&1 | grep -qx "TeamIdentifier=$2"; }
link_in() { mkdir -p "$LBIN" && ln -sf "$1" "$LBIN/$2" && ADDED=1; }
refused() { note "$1 It was not installed."; return 1; }

# Node comes with two helpers, npm and npx; the agent's own tools are started through npx, so all three are put in reach.
link_node() { local t; for t in node npm npx; do [ -e "$1/bin/$t" ] && link_in "$1/bin/$t" "$t" || return 1; done; }
get_node() { # the pinned version, from nodejs.org
  local f="node-v$PIN_NODE-darwin-$ARCH.tar.gz" sum d; d="${f%.tar.gz}"
  [ -x "$SHARE/$d/bin/node" ] && { link_node "$SHARE/$d"; return; }   # fetched and checked by an earlier run: only put it in reach
  work || return 1
  sum="$(pin_sum NODE "$ARCH")" || { note "This setup file carries no fingerprint for Node on this kind of Mac."; return 1; }
  note "Fetching ${f%.tar.gz} from nodejs.org (about 50 MB)…"
  fetch_big "https://nodejs.org/dist/v$PIN_NODE/$f" "$TMP/$f" || { note "nodejs.org could not be reached, or the download did not finish."; return 1; }
  sum_ok "$TMP/$f" "$sum" || { refused "The download is not the one this setup file was made for (its fingerprint differs)."; return 1; }
  mkdir -p "$TMP/node-x" && tar -xzf "$TMP/$f" -C "$TMP/node-x" 2>/dev/null && [ -f "$TMP/node-x/$d/bin/node" ] || { note "The download could not be unpacked."; return 1; }
  signed_by "$TMP/node-x/$d/bin/node" "$TEAM_NODE" || { refused "The download is not signed by the Node.js Foundation."; return 1; }
  mkdir -p "$SHARE" && { [ -d "$SHARE/$d" ] || mv "$TMP/node-x/$d" "$SHARE/$d"; } && link_node "$SHARE/$d"
}

get_jq() { # only an older Mac lacks it
  work || return 1; local f="jq-macos-$GARCH" sum
  sum="$(pin_sum JQ "$GARCH")" || { note "This setup file carries no fingerprint for jq on this kind of Mac."; return 1; }
  note "Fetching jq $PIN_JQ from its makers (about 1 MB)…"
  fetch "https://github.com/jqlang/jq/releases/download/jq-$PIN_JQ/$f" "$TMP/$f" || { note "jq's download page could not be reached, or the download did not finish."; return 1; }
  sum_ok "$TMP/$f" "$sum" || { refused "The download is not the one this setup file was made for (its fingerprint differs)."; return 1; }
  mkdir -p "$SHARE" && cp "$TMP/$f" "$SHARE/jq" && chmod +x "$SHARE/jq" && link_in "$SHARE/jq" jq
}

get_gh() { # GitHub's own tool
  work || return 1; local v="$PIN_GH" z d sum; d="gh_${v}_macOS_$GARCH"; z="$d.zip"
  sum="$(pin_sum GH "$GARCH")" || { note "This setup file carries no fingerprint for the GitHub tool on this kind of Mac."; return 1; }
  note "Fetching the GitHub tool $v from GitHub (about 17 MB)…"
  fetch_big "https://github.com/cli/cli/releases/download/v$v/$z" "$TMP/$z" || { note "GitHub's download page could not be reached, or the download did not finish."; return 1; }
  sum_ok "$TMP/$z" "$sum" || { refused "The download is not the one this setup file was made for (its fingerprint differs)."; return 1; }
  mkdir -p "$TMP/gh-x" && ditto -xk "$TMP/$z" "$TMP/gh-x" 2>/dev/null && [ -f "$TMP/gh-x/$d/bin/gh" ] || { note "The download could not be unpacked."; return 1; }
  signed_by "$TMP/gh-x/$d/bin/gh" "$TEAM_GH" || { refused "The download is not signed by GitHub."; return 1; }
  mkdir -p "$SHARE" && { [ -d "$SHARE/$d" ] || mv "$TMP/gh-x/$d" "$SHARE/$d"; } && link_in "$SHARE/$d/bin/gh" gh
}

get_vscode() { # the pinned version, from Microsoft's own server
  work || return 1; local sum app dest
  sum="$(pin_sum CODE "$CODE_FOR")" || { note "This setup file carries no fingerprint for VS Code on this kind of Mac."; return 1; }
  note "Fetching VS Code $PIN_CODE from Microsoft (about 320 MB; a few minutes)…"
  fetch_big "https://update.code.visualstudio.com/$PIN_CODE/$CODE_FOR/stable" "$TMP/vscode.zip" || { note "Microsoft's server could not be reached, or the download did not finish."; return 1; }
  sum_ok "$TMP/vscode.zip" "$sum" || { refused "The download is not the one this setup file was made for (its fingerprint differs)."; return 1; }
  note "Unpacking and checking Microsoft's signature…"
  mkdir -p "$TMP/vscode-x" && ditto -xk "$TMP/vscode.zip" "$TMP/vscode-x" 2>/dev/null && app="$TMP/vscode-x/$APP_NAME" && [ -d "$app" ] || { note "The download could not be unpacked."; return 1; }
  codesign --verify --deep --strict "$app" >/dev/null 2>&1 && signed_by "$app" "$TEAM_CODE" || { refused "The download is not signed by Microsoft."; return 1; }
  dest="$APPS"; { [ -d "$dest" ] && [ -w "$dest" ]; } || { dest="$HOME_DIR/Applications"; mkdir -p "$dest" || return 1; }
  [ ! -e "$dest/$APP_NAME" ] && mv "$app" "$dest/$APP_NAME"
}

# ── the truth file: what a copy is checked against ──
# The routine is not written here: the build writes it in, the same text as the product's own truth.sh carries (core/tools/truth-whole.sh).
# >>> truth (written here by the build from core/tools/truth-whole.sh; change it there)
# truth-whole.sh — the one way anything decides "is this copy whole?". It is a snippet, not a program: build-spoke.mjs writes
# it into the product's truth.sh and into the setup file (which must stand alone, before anything is installed), and the maker's
# own tools run it from here through core/tools/lib/truth.mjs. truth.test.sh runs one table of cases (fleet/spoke/truth-cases.json)
# through all three.
#
#   truth_whole <folder> [<list> [<prefix>]]
#     <list>    the truth file to check against (default <folder>/TRUTH.txt): one line per file, "<sha256>  ./<path>"
#     <prefix>  only the list's lines under this folder are used, and are read as if it were the root (default ./). It is how a
#               running copy (plugins/<name>) is checked against the list of the kit it was installed from. It must end in /.
#   It prints one line: what is wrong, or "N files, each matches its fingerprint". When one file is to blame, a second line
#   "file: <path>" names the first. It returns 0 whole · 1 not whole · 2 could not decide (it says why).
#
# A copy is whole when every file the list names matches its fingerprint, and nothing is in the folder that the list does not name.
# What the list does not name and still may be there, and why:
#   ./TRUTH.txt   the list itself (it cannot list its own fingerprint)            — only when the list is the folder's own
#   ./TRUTH.sig   the provider's signature on the list; it is data and is checked by seal-kit.sh, not here — the root only, the same
#   .DS_Store, ._*   what the Mac's Finder adds the moment someone opens a folder; data the system makes, never run — at any depth,
#                    but ONLY as a plain file with no execute bit: one that could run is not exempt
# Nothing else is exempt: not a .git folder, not a file by any other name. A symbolic link or any other special file (a pipe, a
# socket) anywhere in the folder is refused outright, so a file cannot stand in for another by pointing at it.
# This is an accident and damage check. The list sits beside the files it lists, so whoever can change the files can change the
# list: it is not yet a seal against someone who can change the source (a signature and a chain lock are decided and not built).
# A file the Mac itself adds, and may be let be: 0 yes, 1 no. Known two ways. It is a plain file with no execute mark (the rule as it was).
# OR it IS what its name says: a ._NAME that begins with the AppleDouble signature (the four bytes 00 05 16 07) and has NAME beside it, a
# .DS_Store that begins as the Finder writes it (00 00 00 01 "Bud1"). The second way is for a disk that keeps no execute mark: on a USB stick
# every file reads as runnable, so the mark says nothing there and the file itself is read. The first bytes are compared by their fingerprint,
# with the tools this routine already needs. (Found 2026-10-12: a copy filed on a stick failed its own check on the six ._ files the Mac added.)
# What input makes this go red? A runnable ._ or .DS_Store that does not begin with its signature, or a ._NAME with no NAME beside it.
_truth_mac() { # folder, ./path
  local p="$1/${2#./}" b="${2##*/}" h
  case "$b" in .DS_Store|._?*) ;; *) return 1 ;; esac
  [ -n "$(find "$p" -maxdepth 0 \( -perm -100 -o -perm -010 -o -perm -001 \) 2>/dev/null)" ] || return 0
  case "$b" in
    .DS_Store) h="$(head -c 8 "$p" 2>/dev/null | shasum -a 256 2>/dev/null)"; [ "${h%% *}" = "c60d20d511de9eb88cd842833d175fc7cb79c6fe54fb4f3f4265b144ec39e7a6" ] ;;
    *) h="$(head -c 4 "$p" 2>/dev/null | shasum -a 256 2>/dev/null)"; [ "${h%% *}" = "26af2039e3563c710de3d6585af9e7b430427ee7767b88b5723bf276186e0043" ] && [ -e "${p%/*}/${b#._}" ] ;;
  esac
}
_truth_core() { # folder, selected list file (made by truth_whole), prefix
  local d="$1" sel="$2" pre="$3" n odd extra out bad good first ex=()
  n="$(wc -l < "$sel" | tr -d ' ')"
  # a link or special file anywhere, first: a link makes the fingerprints below say nothing
  odd="$(cd "$d" && find . ! -type f ! -type d 2>/dev/null)" || { echo "could not decide — the folder could not be read all the way"; return 2; }
  if [ -n "$odd" ]; then first="$(printf '%s\n' "$odd" | LC_ALL=C sort | head -1)"; echo "It holds a link or a special file, and a copy never does: $(printf '%s\n' "$odd" | LC_ALL=C sort | head -3 | tr '\n' ' ')"; echo "file: ${first#./}"; return 1; fi
  out="$(cd "$d" && shasum -a 256 -c "$sel" 2>/dev/null)"
  bad="$(printf '%s\n' "$out" | grep -v ': OK$' | grep . | head -3)"; good="$(printf '%s\n' "$out" | grep -c ': OK$')"
  if [ -n "$bad" ]; then first="$(printf '%s\n' "$bad" | head -1 | sed 's/: .*//')"; echo "These do not match their fingerprints: $(printf '%s\n' "$bad" | sed 's/: .*//' | tr '\n' ' ')"; echo "file: ${first#./}"; return 1; fi
  [ "$good" -eq "$n" ] || { echo "could not decide — the fingerprints could not all be read"; return 2; }
  [ "$pre" = "./" ] && ex=(! -path ./TRUTH.txt ! -path ./TRUTH.sig)
  # What input makes this go red? A file in the folder that the list does not name, unless it is one the Mac itself adds (_truth_mac).
  # Both lists are sorted and compared byte by byte (LC_ALL=C on comm too): in another language's order comm loses a match and calls a listed file a stranger.
  extra="$(cd "$d" && find . -type f ${ex[@]+"${ex[@]}"} 2>/dev/null)" || { echo "could not decide — the folder could not be read all the way"; return 2; }
  extra="$(printf '%s\n' "$extra" | grep . | LC_ALL=C sort | LC_ALL=C comm -23 - <(sed -E 's/^[0-9a-f]{64}  //' "$sel" | LC_ALL=C sort) | while IFS= read -r f; do _truth_mac "$d" "$f" || printf '%s\n' "$f"; done | head -3)"
  if [ -n "$extra" ]; then echo "These are in it and not in its truth file: $(printf '%s\n' "$extra" | tr '\n' ' ')"; echo "file: $(printf '%s\n' "$extra" | head -1 | sed 's|^\./||')"; return 1; fi
  echo "$n files, each matches its fingerprint"
}
truth_whole() {
  local d="${1:-}" list="${2:-${1:-}/TRUTH.txt}" pre="${3:-./}" sel rc o
  { [ -n "$d" ] && [ -d "$d" ] && (cd "$d") 2>/dev/null; } || { echo "could not decide — that folder is not there"; return 2; }
  for o in shasum find awk comm sed mktemp head; do command -v "$o" >/dev/null 2>&1 || { echo "could not decide — $o is missing"; return 2; }; done
  case "$pre" in *..*) echo "could not decide — the folder prefix is not a folder name"; return 2 ;; ./|./*/) ;; *) echo "could not decide — the folder prefix is not a folder name"; return 2 ;; esac
  [ -s "$list" ] || { echo "It has no truth file (TRUTH.txt)"; return 1; }
  if grep -Ev '^[0-9a-f]{64}  \./[^[:cntrl:]]+$' "$list" | grep . >/dev/null || grep -e '\.\./' "$list" >/dev/null; then echo "Its truth file is not a plain list of fingerprints"; return 1; fi
  sel="$(mktemp "${TMPDIR:-/tmp}/truth.XXXXXX")" || { echo "could not decide — a working file could not be made"; return 2; }
  LC_ALL=C awk -v p="$pre" '{ n = substr($0, 67); if (index(n, p) == 1) print substr($0, 1, 66) "./" substr(n, length(p) + 1) }' "$list" > "$sel" 2>/dev/null
  if [ ! -s "$sel" ]; then rm -f "$sel"; echo "Its truth file lists nothing for this folder"; return 1; fi
  _truth_core "$d" "$sel" "$pre"; rc=$?
  rm -f "$sel"; return "$rc"
}
# <<< truth
# Whole, said in this file's own voice: yes (0), or no (1) with the reason as a note, or could not decide (2), which also installs nothing.
whole() { local r rc; r="$(truth_whole "$1")"; rc=$?; WHOLE_RC="$rc"; WHOLE_SAID="$(printf '%s\n' "$r" | head -1 | sed 's/ *$//')"
  [ "$rc" -eq 0 ] || note "$WHOLE_SAID."; return "$rc"; }
version_in() { sed -n 's/.*"version"[^"]*"\([0-9][0-9.]*\)".*/\1/p' "$1/plugins/agent-zero-code/.claude-plugin/plugin.json" 2>/dev/null | head -1; }
# >>> semver (written here by the build from core/tools/semver.sh; change it there)
# semver.sh — the one way the product's shell scripts compare two version numbers. It is a snippet, not a program: build-spoke.mjs
# writes it into each shipped script that compares versions (so the setup file still stands alone). The same rule in JavaScript is
# core/tools/semver.cjs; semver.test.sh runs one table of cases (fleet/spoke/semver-cases.json) through both.
#
# A version is three plain whole numbers with dots between them (1.3.2), at most 4, 5 and 6 digits. Leading zeros count as the
# number (1.03.2 is 1.3.2). Anything else (a missing part, an extra part, a tail like -beta, a letter, a space, nothing) is NOT a
# version: nothing is said and the return is 2 (could not decide), never "same" and never "older".
#   semver_cmp A B   prints newer (A is newer than B), same, or older, and returns 0; prints nothing and returns 2 if either is not a version
semver_cmp() {
  local v p a1 a2 a3 b1 b2 b3 x y
  for v in "$1" "$2"; do
    case "$v" in ''|*[!0-9.]*|.*|*.|*..*) return 2 ;; esac
    p="${v//[!.]/}"; [ "${#p}" -eq 2 ] || return 2
  done
  IFS=. read -r a1 a2 a3 <<< "$1"; IFS=. read -r b1 b2 b3 <<< "$2"
  [ "${#a1}" -le 4 ] && [ "${#b1}" -le 4 ] && [ "${#a2}" -le 5 ] && [ "${#b2}" -le 5 ] && [ "${#a3}" -le 6 ] && [ "${#b3}" -le 6 ] || return 2
  for p in "$a1 $b1" "$a2 $b2" "$a3 $b3"; do
    x="${p% *}"; y="${p#* }"
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then echo newer; return 0; fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then echo older; return 0; fi
  done
  echo same
}
# <<< semver
# >>> claude-vscode (written here by the build from core/tools/claude-vscode.sh; change it there)
# claude-vscode.sh — the one way the product's shell scripts find Claude Code inside VS Code. It is a snippet, not a program: the
# build writes it into each shipped script that looks there (the setup file, the updater, the reach report; the manifest lists them),
# beside the version-compare snippet it uses (semver_cmp). Its JavaScript twin is the finder the Portal's server reads.
#
# VS Code keeps several copies of its Claude Code extension, each in a folder named for its version and machine
# (anthropic.claude-code-2.1.304-darwin-x64). The newest is chosen by its VERSION, through semver_cmp, never by its name: by name
# 2.1.99 comes after 2.1.100 (walk 137, Oct 21 2026: the setup, the reach report and the Portal's server each picked by name). A folder
# whose version is not three plain numbers, or whose program is not there or cannot run, is passed over.
#   claude_in_vscode <home>       prints the newest copy's program; nothing, and return 1, when there is none
#   claude_in_vscode <home> all   prints every copy's program, newest first, one per line
claude_in_vscode() {
  local c v line best bv left="" all="${2:-}"
  for c in "$1"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude; do
    [ -f "$c" ] && [ -x "$c" ] || continue
    v="${c#"$1"/.vscode/extensions/anthropic.claude-code-}"; v="${v%%/*}"; v="${v%%-*}"
    semver_cmp "$v" "$v" >/dev/null 2>&1 && left="${left:+$left$'\n'}$v $c"
  done
  [ -n "$left" ] || return 1
  while [ -n "$left" ]; do
    best=""; bv=""
    while IFS= read -r line; do v="${line%% *}"; if [ -z "$bv" ] || [ "$(semver_cmp "$v" "$bv")" = newer ]; then bv="$v"; best="$line"; fi; done <<< "$left"
    printf '%s\n' "${best#* }"; [ "$all" = all ] || return 0
    left="$(printf '%s\n' "$left" | grep -vxF -- "$best" || true)"
  done
}
# <<< claude-vscode

# So that windows opened later find the tools put in ~/.local/bin: one marked line in the shell's own startup file.
remember_path() {
  [ "$ADDED" = "1" ] || return 0; local f="$HOME_DIR/.zprofile"; case "${SHELL:-}" in */bash) f="$HOME_DIR/.bash_profile" ;; esac
  grep -q 'added by Agent Zero Code setup' "$f" 2>/dev/null && return 0
  printf '\n# added by Agent Zero Code setup: the small tools it installed for you live in ~/.local/bin\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$f" && note "Added one line to ~${f#"$HOME_DIR"} so new windows find those tools."
}

# One piece: here already, or fetched and checked now. In a check-only run nothing is fetched.
piece() { # the tool, the function that gets it
  have "$1" && return 0
  if [ -n "$CHECK" ]; then note "would be fetched from its maker and checked"; return 1; fi
  "$2"; have "$1"
}

# A sign-in with no keyboard behind it. GitHub's tool prints a one-time code and waits; the screen shows the code and opens
# the address. Claude Code opens the browser itself and waits for it to come back; the screen is told the address too.
# What the tool printed is told once, whether it is still waiting or has already finished: a tool that prints and exits
# before the first look (a fast Mac, a slow one, an error) must still reach the screen, so each loop ends with one more read.
tell_gh()     { [ -n "$told" ] && return; code="$(grep -o -E '[A-Z0-9]{4}-[A-Z0-9]{4}' "$out" 2>/dev/null | head -1)"; [ -n "$code" ] && { ev signin "\"who\":\"github\",\"code\":\"$code\",\"url\":\"https://github.com/login/device\""; told=1; }; }
tell_claude() { [ -n "$told" ] && return; url="$(grep -o -E 'https://[A-Za-z0-9./?=&%_:+~#-]+' "$out" 2>/dev/null | head -1)"; [ -n "$url" ] && { ev signin "\"who\":\"claude\",\"url\":\"$(js "$url")\""; told=1; }; }
signin_github() { work || return 1; local out="$TMP/gh-signin.txt" pid code told="" w=0; : > "$out"
  gh auth login --hostname github.com --git-protocol https --web < /dev/null > "$out" 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$w" -lt "$WAIT_MAX" ]; do tell_gh; sleep 1; w=$((w + 1)); done
  tell_gh; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 0; }
signin_claude() { work || return 1; local out="$TMP/claude-signin.txt" pid hold url told="" w=0; : > "$out"; rm -f "$TMP/claude-in"; mkfifo "$TMP/claude-in" 2>/dev/null || return 1
  sleep "$WAIT_MAX" > "$TMP/claude-in" & hold=$!; "$CL" auth login < "$TMP/claude-in" > "$out" 2>&1 & pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$w" -lt "$WAIT_MAX" ]; do tell_claude; sleep 1; w=$((w + 1)); done
  tell_claude; kill "$pid" "$hold" 2>/dev/null; wait "$pid" "$hold" 2>/dev/null; return 0; }

ev start "\"version\":\"$(js "$( [ -n "$KIT" ] && version_in "$KIT" )")\",\"handed\":$([ -n "$KIT" ] && echo true || echo false),\"check\":$([ -n "$CHECK" ] && echo true || echo false)"
echo; echo "  Setting up Agent Zero Code on this Mac."
echo "  Whatever is missing is fetched from its maker and checked. You sign in twice, in your browser."
if [ -n "$KIT" ]; then
  echo "  The copy in this folder installs your agent. GitHub is only for improvements afterwards."
  step "The copy you were handed"
  if whole "$KIT"; then ok "$WHOLE_SAID"
  elif [ "$WHOLE_RC" -eq 2 ]; then no "this copy could not be checked against its truth file, so nothing is installed from it"
  else no "this copy does not match its truth file, so nothing is installed from it"; fi
fi

step "Apple's developer tools (they include git)"
git_ready() { have git && { [ -n "${SETUP_ANY_OS:-}" ] || xcode-select -p >/dev/null 2>&1; }; }
if git_ready; then ok "git is here"
else
  if [ -z "$CHECK" ]; then echo "     → Your Mac will offer to install them. Say Install, wait for it to finish, then press Return here."; xcode-select --install >/dev/null 2>&1; if [ -n "$EVENTS" ]; then ev wait '"for":"apple-tools"'; wait_for git_ready; else read -r _; fi; fi
  git_ready && ok "git is here" || no "git is not installed yet (Apple's developer tools)"
fi

step "Node (a small free tool the agent's scripts run on)"
if piece node get_node; then
  # Node without its helper npx (an earlier setup left it so): the agent's tools could not start. Put right here.
  if have npx || { [ -z "$CHECK" ] && get_node && have npx; }; then ok "node $(node --version 2>/dev/null)"
  elif [ -n "$CHECK" ]; then no "node is here, but a helper it comes with (npx) is not in reach; setting up puts that right"
  else no "node is here, but a helper it comes with (npx) could not be put in reach"; fi
else no "node is not installed yet"; fi

step "jq (a small free tool; newer Macs already have it)"
piece jq get_jq && ok "jq is here" || no "jq is not installed yet"

if [ -n "$KIT" ]; then step "Improvements, through GitHub (your agent works without this)"; else step "The GitHub tool, and this Mac signed in to GitHub"; fi
if ! piece gh get_gh; then gap "the GitHub tool (gh) is not installed yet"
else
  # A handed copy needs no GitHub to work (2026-10-18): the sign-in is not started here; the agent asks for it when an improvement needs it. That takes a sign-in out of the owner's install.
  if ! gh auth status >/dev/null 2>&1 && [ -z "$CHECK" ] && [ -z "$KIT" ]; then
    echo "     → Signing this Mac in to GitHub. A browser window opens; sign in there. No password is typed here."
    if [ -n "$EVENTS" ]; then signin_github; else gh auth login --hostname github.com --git-protocol https --web; fi
  fi
  # Pointing git at that sign-in changes this Mac's git settings, so a check-only run leaves it alone.
  if gh auth status >/dev/null 2>&1; then [ -n "$CHECK" ] || gh auth setup-git >/dev/null 2>&1; ok "this Mac is signed in to GitHub"; elif [ -n "$KIT" ]; then gap "this Mac is not signed in to GitHub yet; your agent works without it and asks when an improvement needs it"; else gap "this Mac is not signed in to GitHub yet (run this file again to sign in)"; fi
fi

[ -n "$KIT" ] || step "Your invitation to Agent Zero Code"
can_read() { have gh && gh api "repos/$REPO" --silent >/dev/null 2>&1; }
can_read || { have gh && gh auth status >/dev/null 2>&1 && help_with "Accept your invitation (GitHub emailed it). If there is none, send your GitHub username to the person who invited you" "https://github.com/$REPO/invitations"; [ -n "$EVENTS" ] && [ -z "$KIT" ] && [ -z "$CHECK" ] && wait_for can_read; }
can_read && ok "you can read Agent Zero Code" || gap "you cannot read Agent Zero Code yet (the invitation is not accepted, or not sent)"

step "VS Code, with Claude Code in it"
if [ -z "$(code_app)" ]; then if [ -n "$CHECK" ]; then note "would be fetched from Microsoft and checked"; else get_vscode; fi; fi
VS="$(code_app)"
if [ -z "$VS" ]; then no "VS Code is not installed yet"
else
  ok "VS Code is here"
  if [ -z "$(claude_bin)" ] && [ -z "$CHECK" ] && [ -x "$VS/Contents/Resources/app/bin/code" ]; then
    note "Adding Claude Code $PIN_CLAUDE to VS Code (from the VS Code marketplace)…"
    "$VS/Contents/Resources/app/bin/code" --install-extension "anthropic.claude-code@$PIN_CLAUDE" --extensions-dir "$HOME_DIR/.vscode/extensions" ${SETUP_CODE_DATA:+--user-data-dir "$SETUP_CODE_DATA"} >/dev/null 2>&1
  fi
  [ -n "$(claude_bin)" ] && ok "Claude Code is in VS Code" || no "the Claude Code extension is not installed yet"
fi
CL="$(claude_bin)"

step "Signed in to Claude"
if [ -z "$CL" ]; then echo "     (waits for Claude Code, above)"
else
  if ! "$CL" auth status >/dev/null 2>&1 && [ -z "$CHECK" ]; then
    echo "     → Signing in to Claude. A browser window opens; sign in there with your own Claude account."
    if [ -n "$EVENTS" ]; then signin_claude; else "$CL" auth login; fi
  fi
  "$CL" auth status >/dev/null 2>&1 && ok "signed in to Claude" || no "not signed in to Claude yet (run this file again to sign in)"
fi

# Installed is not the same as working (seen 2026-10-13: a copy installed whole while the program its browser starts with was out of
# reach). Every tool the agent starts is named in the copy's .mcp.json by the program that starts it; each must be in reach.
tools_reach() { local f="$1/plugins/agent-zero-code/.mcp.json" c bad=""
  [ -n "$1" ] && [ -f "$f" ] || return 0
  for c in $(grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | sed 's/.*"\([^"]*\)"$/\1/' | sort -u); do have "$c" || bad="$bad $c"; done   # no jq: Apple's own tools only
  if [ -n "$bad" ]; then no "your agent's own tools cannot start: missing$bad (run this file again; if it says this again, tell the person who invited you)"
  else ok "your agent's own tools can start"; fi
}
step "Agent Zero Code itself"
[ -n "$CHECK" ] || remember_path
if [ "$MISSING" -gt 0 ]; then echo "     (waits until everything above has a ✓)"
elif [ -n "$CHECK" ]; then echo "     → ready to install (not done in a check-only run)"
else
  echo "     → Installing Agent Zero Code now."
  if [ -n "$KIT" ]; then
    # From the copy you were handed, kept in your own home folder so it stays when the drive it came on goes.
    # Claude Code updates from that folder; an improvement is fetched into it later, from GitHub, and checked first.
    KEPT="$SHARE/kit"; VK="$(version_in "$KIT")"; VH="$(version_in "$KEPT")"
    CMP="$(semver_cmp "$VH" "$VK")"; [ -z "$VH" ] || [ -n "$CMP" ] || note "Could not tell which copy is newer (the one in place says '$VH', the one you were handed says '$VK'), so the one you were handed is put in."
    if [ "$CMP" = newer ]; then note "A newer copy (version $VH) is already in place on this Mac. It was kept; the older one you were handed ($VK) was not put over it."
    else mkdir -p "$KEPT" "$SHARE/provider" && rsync -a -c --delete --exclude .git "$KIT/" "$KEPT/" && printf '%s\n' "$REPO" > "$SHARE/provider/source.txt"; fi
    if whole "$KEPT"; then
      "$CL" plugin marketplace add "$KEPT" 2>&1 | tail -1 | sed 's/^/       /'
      "$CL" plugin marketplace update "$HUB" >/dev/null 2>&1
      "$CL" plugin install "$PLUGIN" 2>&1 | tail -1 | sed 's/^/       /'
      # A Mac that already had an older version keeps running it after "install": only "update" moves it to the copy just put in place.
      "$CL" plugin update "$PLUGIN" >/dev/null 2>&1
    else note "The copy did not arrive whole in your home folder, so nothing was installed from it."; no "the new copy was not put in place (what was installed before is unchanged)"; fi
  else
    # No folder was handed over: Claude Code fetches the catalogue from GitHub itself. What it fetched is checked against its truth
    # file BEFORE anything is installed from it (a copy of its files without the .git folder, so the check sees exactly what would be
    # installed). If that copy is not whole, or cannot be checked, nothing is installed, and what was installed before stays.
    # What input makes this go red? A catalogue clone with one file changed, or no clone to look at.
    "$CL" plugin marketplace add "$REPO" 2>&1 | tail -1 | sed 's/^/       /'
    "$CL" plugin marketplace update "$HUB" >/dev/null 2>&1
    CLONE="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}/plugins/marketplaces/$HUB"; SNAP="$(mktemp -d "${TMPDIR:-/tmp}/agent-zero-code-clone.XXXXXX" 2>/dev/null)"; GOT=""
    if [ -n "$SNAP" ] && [ -d "$CLONE" ] && rsync -a --exclude .git "$CLONE/" "$SNAP/" 2>/dev/null; then whole "$SNAP" && GOT=1; else note "The copy Claude Code fetched from GitHub could not be looked at, so it could not be checked."; fi
    [ -z "$SNAP" ] || rm -rf "$SNAP"
    if [ -n "$GOT" ]; then
      "$CL" plugin install "$PLUGIN" 2>&1 | tail -1 | sed 's/^/       /'
      "$CL" plugin update "$PLUGIN" >/dev/null 2>&1
    else note "Nothing was installed from it. What was installed before is unchanged."; no "the copy from GitHub was not checked as whole, so it was not installed (run this file again; if it says this again, tell the person who invited you)"; fi
  fi
  if "$CL" plugin list 2>/dev/null | grep -q "agent-zero-code@"; then ok "Agent Zero Code is installed"; tools_reach "${KEPT:-${CLONE:-}}"; else no "Agent Zero Code did not install (send the lines above to the person who invited you)"; fi
fi

# ── the first check-up: what kind of Mac this is and what this setup found, for the person who set it up ──
# It is shown in full and saved only on a yes, next to this file (on a stick, that is how it travels back). When this file
# sits in a folder that was handed over, it is saved beside that folder, never inside it: the folder is checked against its
# fingerprints every time this file runs, and one more file in it would make it fail and install nothing.
# Nothing is ever sent from here. It holds no names, no files and nothing that was typed.
line
if [ -z "$CHECK" ]; then
  ver() { "$@" 2>/dev/null | head -1 | grep -o -E '[0-9]+(\.[0-9]+)+' | head -1; }
  tool() { if have "$1"; then v="$(ver "$1" --version)"; printf '%s' "${v:-present}"; else printf 'missing'; fi; }
  MEM="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"; DISK="$(df -g "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  CU="Agent Zero Code help report — $(date -u '+%Y-%m-%dT%H:%M:%SZ')
kind: first check-up
about: written by the setup file on this computer. What kind of Mac this is and what the setup found. No names, no files, nothing that was typed.
os: $(sw_vers -productVersion 2>/dev/null || uname -sr) · node: $(tool node) · jq: $(tool jq) · git: $(tool git) · gh: $(tool gh) · npx: $(tool npx)
mac: chip $ARCH · memory ${MEM:-0} GB · free disk ${DISK:-unknown} GB
installed from: $([ -n "$KIT" ] && echo "a copy handed over as a folder" || echo "GitHub")
setup: $MISSING missing · $LATER left for later
steps:
$SEEN"
  ev checkup "\"text\":\"$(printf '%s' "$CU" | sed "s|$HOME_DIR|~|g" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\011\013-\037' | awk '{ printf "%s\\n", $0 }')\""
  echo "  One last thing: a first check-up. It lets the person who set this up tune your agent to this computer."
  echo "  This is all of it:"; echo; printf '%s\n' "$CU" | sed 's/^/     /'
  ANS="${SETUP_CHECKUP:-}"; DEST="$HERE"; WHERE="next to this setup file"
  [ -n "$KIT" ] && { DEST="$(dirname "$KIT")"; WHERE="beside the folder you were handed"; }
  if [ -z "$ANS" ] && [ -t 0 ]; then printf '  Save it %s so they can read it? Type y and press Return, or just press Return to skip: ' "$WHERE"; read -r ANS; fi
  case "$ANS" in
    y|Y|yes|YES|Yes) { [ -n "$DEST" ] && [ -d "$DEST" ] && [ -w "$DEST" ]; } || DEST="$HOME_DIR/Desktop"
      CUF="$DEST/Agent Zero Code first check-up $(date '+%Y-%m-%d %H%M').txt"
      if printf '%s\n' "$CU" > "$CUF" 2>/dev/null; then echo "  Saved: $(printf '%s' "$CUF" | sed "s|$HOME_DIR|~|"). Nothing was sent anywhere: hand it over yourself."
      else echo "  It could not be saved there. Nothing was sent."; fi ;;
    *) echo "  Not saved, and nothing was sent. Your agent can make one later: ask it for a help report." ;;
  esac
else echo "  (At the end of a real run you are shown a first check-up and asked whether to save it. A check-only run writes nothing.)"; fi

line
if [ "$MISSING" -eq 0 ] && [ -z "$CHECK" ]; then
  # One new, empty folder for the agent to start in. Nothing of yours is in it.
  START="$HOME_DIR/My Agent"; mkdir -p "$START" 2>/dev/null
  # The owner's own screen, not the engine's box: their Portal, as an app on the Desktop, opened now. Its first screens ask the
  # few setup questions and hand the answers to the agent, which works with no box open. It is made by the installed copy's own
  # script. Only when that cannot be done here does the setup end the older way, in VS Code.
  CFG="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}"; PDATA="$CFG/plugins/data/$(printf '%s' "$PLUGIN" | tr '@' '-')"; DESK="$HOME_DIR/Desktop"; PORTAL=""
  PROOT="$(node -e 'try { const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).plugins || {}; const k = Object.keys(p).find((n) => n.startsWith("agent-zero-code@")); process.stdout.write(k && p[k][0] && typeof p[k][0].installPath === "string" ? p[k][0].installPath : "") } catch { }' "$CFG/plugins/installed_plugins.json" 2>/dev/null)"
  if [ -n "$PROOT" ] && [ -f "$PROOT/scripts/portal.sh" ] && [ -d "$DESK" ]; then
    if [ -d "$DESK/My Portal.app" ] && pgrep -f "$DESK/My Portal.app/Contents/MacOS/applet" >/dev/null 2>&1; then osascript -e "tell application \"$DESK/My Portal.app\" to quit" >/dev/null 2>&1; sleep 2; fi
    printf '{}' | HOME="$HOME_DIR" CLAUDE_PLUGIN_ROOT="$PROOT" CLAUDE_PLUGIN_DATA="$PDATA" bash "$PROOT/scripts/init-data.sh" >/dev/null 2>&1
    HOME="$HOME_DIR" PORTAL_BUTTON_DIR="$DESK" CLAUDE_PLUGIN_ROOT="$PROOT" CLAUDE_PLUGIN_DATA="$PDATA" bash "$PROOT/scripts/portal.sh" --button "$START" >/dev/null 2>&1
    if [ -d "$DESK/My Portal.app" ]; then PORTAL="$DESK/My Portal.app"; elif [ -f "$DESK/Open my Portal.command" ]; then PORTAL="$DESK/Open my Portal.command"; fi
  fi
  # Nothing the setup starts comes in front of the owner's work (2026-10-18). Led by a screen (the Claude app's move-in), nothing is opened here:
  # the Portal opens once, after the hand-over, by the connector's open_my_portal; the end event names it. Run by a double-click, the Portal
  # (or, failing that, VS Code) is the next screen and opens once here.
  if [ -n "$PORTAL" ]; then
    if [ -n "$EVENTS" ]; then echo "  All set. Your Portal is on your Desktop: $(basename "$PORTAL" | sed 's/\.[a-z]*$//'). It opens once your answers are handed over."
    else echo "  All set. Your Portal is opening now. It is on your Desktop too: $(basename "$PORTAL" | sed 's/\.[a-z]*$//')."; fi
    echo "    Answer its few questions there. Your agent takes it from there."; echo "    You can close this window."
    [ "$LATER" -gt 0 ] && echo "  Your agent works as it is. It is not connected to GitHub yet; it asks you to connect when an improvement is ready."
    [ -n "$EVENTS" ] || open "$PORTAL" 2>/dev/null
  else
    if [ -n "$EVENTS" ]; then echo "  All set. Your agent's folder is ready: ~${START#"$HOME_DIR"}. Open VS Code on it when you want it, click the Claude icon and type: onboard me"
    else echo "  All set. VS Code is opening on a new, empty folder: ~${START#"$HOME_DIR"}"; echo "    1. Click the Claude icon."; echo "    2. Type:  onboard me"; fi
    [ "$LATER" -gt 0 ] && echo "  Your agent works as it is. It is not connected to GitHub yet; it asks you to connect when an improvement is ready."
    [ -n "$EVENTS" ] || open -a "$VS" "$START" 2>/dev/null
  fi
elif [ "$MISSING" -eq 0 ]; then echo "  Everything this Mac needs is in place."
else echo "  $MISSING thing(s) still missing, marked ✗ above. Double-click this file again when they are done."; fi
ev end "\"missing\":$MISSING,\"later\":$LATER,\"portal\":\"$(js "${PORTAL:-}")\""
echo
[ "$MISSING" -eq 0 ]
