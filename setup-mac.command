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
claude_bin() { ls -d "$HOME_DIR"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null | tail -1; }

# ── fetching a piece from its maker, and checking it before it is used ──
work() { [ -n "$TMP" ] || { TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-zero-code-setup.XXXXXX")" && trap 'rm -rf "$TMP"' EXIT; }; [ -n "$TMP" ] && [ -d "$TMP" ]; }
fetch() { curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 20 -o "$2" "$1" 2>/dev/null; }                   # address, file
fetch_big() { curl -fL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 20 --progress-bar -o "$2" "$1"; }                # the same, showing how far it is
sum_ok() { [ -n "$2" ] && [ "$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)" = "$2" ]; }           # a file, the checksum it must have
signed_by() { codesign --verify --strict "$1" >/dev/null 2>&1 && codesign -dv --verbose=2 "$1" 2>&1 | grep -qx "TeamIdentifier=$2"; }
link_in() { mkdir -p "$LBIN" && ln -sf "$1" "$LBIN/$2" && ADDED=1; }
refused() { note "$1 It was not installed."; return 1; }

get_node() { # the pinned version, from nodejs.org
  work || return 1; local f="node-v$PIN_NODE-darwin-$ARCH.tar.gz" sum d
  sum="$(pin_sum NODE "$ARCH")" || { note "This setup file carries no fingerprint for Node on this kind of Mac."; return 1; }
  note "Fetching ${f%.tar.gz} from nodejs.org (about 50 MB)…"
  fetch_big "https://nodejs.org/dist/v$PIN_NODE/$f" "$TMP/$f" || { note "nodejs.org could not be reached, or the download did not finish."; return 1; }
  sum_ok "$TMP/$f" "$sum" || { refused "The download is not the one this setup file was made for (its fingerprint differs)."; return 1; }
  d="${f%.tar.gz}"; mkdir -p "$TMP/node-x" && tar -xzf "$TMP/$f" -C "$TMP/node-x" 2>/dev/null && [ -f "$TMP/node-x/$d/bin/node" ] || { note "The download could not be unpacked."; return 1; }
  signed_by "$TMP/node-x/$d/bin/node" "$TEAM_NODE" || { refused "The download is not signed by the Node.js Foundation."; return 1; }
  mkdir -p "$SHARE" && { [ -d "$SHARE/$d" ] || mv "$TMP/node-x/$d" "$SHARE/$d"; } && link_in "$SHARE/$d/bin/node" node
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
# Whole: every file the truth file lists matches its fingerprint, and nothing is there that it does not list.
whole() { local d="$1" bad extra
  [ -s "$d/TRUTH.txt" ] || { note "It has no truth file (TRUTH.txt)."; return 1; }
  if grep -Ev '^[0-9a-f]{64}  \./[^[:cntrl:]]+$' "$d/TRUTH.txt" | grep . >/dev/null || grep -e '\.\./' "$d/TRUTH.txt" >/dev/null; then note "Its truth file is not a plain list of fingerprints."; return 1; fi
  bad="$(cd "$d" && shasum -a 256 -c TRUTH.txt 2>/dev/null | grep -v ': OK$' | head -3)"
  [ -z "$bad" ] || { note "These do not match their fingerprints: $(printf '%s' "$bad" | sed 's/: .*//' | tr '\n' ' ')"; return 1; }
  extra="$(cd "$d" && find . -type f ! -name TRUTH.txt ! -name TRUTH.sig ! -name .DS_Store ! -name '._*' ! -path './.git/*' | LC_ALL=C sort | comm -23 - <(sed -E 's/^[0-9a-f]{64}  //' TRUTH.txt | LC_ALL=C sort) | head -3)"
  [ -z "$extra" ] || { note "These are in it and not in its truth file: $(printf '%s' "$extra" | tr '\n' ' ')"; return 1; }
}
version_in() { sed -n 's/.*"version"[^"]*"\([0-9][0-9.]*\)".*/\1/p' "$1/plugins/agent-zero-code/.claude-plugin/plugin.json" 2>/dev/null | head -1; }
newer() { # is version $1 newer than version $2
  local a b i; IFS=. read -r -a a <<< "$1"; IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ] 2>/dev/null && return 0; [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ] 2>/dev/null && return 1; done; return 1; }

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
  if whole "$KIT"; then ok "$(wc -l < "$KIT/TRUTH.txt" | tr -d ' ') files, each matches its fingerprint"
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
piece node get_node && ok "node $(node --version 2>/dev/null)" || no "node is not installed yet"

step "jq (a small free tool; newer Macs already have it)"
piece jq get_jq && ok "jq is here" || no "jq is not installed yet"

if [ -n "$KIT" ]; then step "Improvements, through GitHub (your agent works without this)"; else step "The GitHub tool, and this Mac signed in to GitHub"; fi
if ! piece gh get_gh; then gap "the GitHub tool (gh) is not installed yet"
else
  if ! gh auth status >/dev/null 2>&1 && [ -z "$CHECK" ]; then
    echo "     → Signing this Mac in to GitHub. A browser window opens; sign in there. No password is typed here."
    if [ -n "$EVENTS" ]; then signin_github; else gh auth login --hostname github.com --git-protocol https --web; fi
  fi
  # Pointing git at that sign-in changes this Mac's git settings, so a check-only run leaves it alone.
  if gh auth status >/dev/null 2>&1; then [ -n "$CHECK" ] || gh auth setup-git >/dev/null 2>&1; ok "this Mac is signed in to GitHub"; else gap "this Mac is not signed in to GitHub yet (run this file again to sign in)"; fi
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
    if [ -n "$VH" ] && newer "$VH" "$VK"; then note "A newer copy (version $VH) is already in place on this Mac. It was kept; the older one you were handed ($VK) was not put over it."
    else mkdir -p "$KEPT" "$SHARE/provider" && rsync -a -c --delete --exclude .git "$KIT/" "$KEPT/" && printf '%s\n' "$REPO" > "$SHARE/provider/source.txt"; fi
    if whole "$KEPT"; then
      "$CL" plugin marketplace add "$KEPT" 2>&1 | tail -1 | sed 's/^/       /'
      "$CL" plugin marketplace update "$HUB" >/dev/null 2>&1
      "$CL" plugin install "$PLUGIN" 2>&1 | tail -1 | sed 's/^/       /'
      # A Mac that already had an older version keeps running it after "install": only "update" moves it to the copy just put in place.
      "$CL" plugin update "$PLUGIN" >/dev/null 2>&1
    else note "The copy did not arrive whole in your home folder, so nothing was installed from it."; no "the new copy was not put in place (what was installed before is unchanged)"; fi
  else
    "$CL" plugin marketplace add "$REPO" 2>&1 | tail -1 | sed 's/^/       /'
    "$CL" plugin marketplace update "$HUB" >/dev/null 2>&1
    "$CL" plugin install "$PLUGIN" 2>&1 | tail -1 | sed 's/^/       /'
    "$CL" plugin update "$PLUGIN" >/dev/null 2>&1
  fi
  if "$CL" plugin list 2>/dev/null | grep -q "agent-zero-code@"; then ok "Agent Zero Code is installed"; else no "Agent Zero Code did not install (send the lines above to the person who invited you)"; fi
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
os: $(sw_vers -productVersion 2>/dev/null || uname -sr) · node: $(tool node) · jq: $(tool jq) · git: $(tool git) · gh: $(tool gh)
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
  if [ -n "$PORTAL" ]; then
    echo "  All set. Your Portal is opening now. It is on your Desktop too: $(basename "$PORTAL" | sed 's/\.[a-z]*$//')."
    echo "    Answer its few questions there. Your agent takes it from there."; echo "    You can close this window."
    [ "$LATER" -gt 0 ] && echo "  Your agent works as it is. It is not connected to GitHub yet, so improvements will not reach it: run this file again to connect."
    open "$PORTAL" 2>/dev/null
  else
    echo "  All set. VS Code is opening on a new, empty folder: ~${START#"$HOME_DIR"}"; echo "    1. Click the Claude icon."; echo "    2. Type:  onboard me"
    [ "$LATER" -gt 0 ] && echo "  Your agent works as it is. It is not connected to GitHub yet, so improvements will not reach it: run this file again to connect."
    open -a "$VS" "$START" 2>/dev/null
  fi
elif [ "$MISSING" -eq 0 ]; then echo "  Everything this Mac needs is in place."
else echo "  $MISSING thing(s) still missing, marked ✗ above. Double-click this file again when they are done."; fi
ev end "\"missing\":$MISSING,\"later\":$LATER,\"portal\":\"$(js "${PORTAL:-}")\""
echo
[ "$MISSING" -eq 0 ]
