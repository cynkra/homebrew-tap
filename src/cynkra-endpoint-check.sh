#!/bin/zsh
# cynkra endpoint check: security baseline of Macs used for cynkra work and customer access.
# Read-only: changes nothing, needs no admin rights.
# Side effect: clears your cached sudo credentials (sudo -k) to test for passwordless sudo.
# Needs syft and osv-scanner (brew install syft osv-scanner) for the vulnerability check.
# The software inventory stays on the device. The local report lists security settings, autostart
# entries, container images and vulnerability findings; the central report (run, registered
# owners only) gets only the status per check and summaries without names of files, keys,
# variables, apps, containers or extensions.
# Usage:
#   cynkra-endpoint-check.sh [check] [--offline] [--json]
#                                                 show the result (--json: as JSON), write no
#                                                 files, send nothing (default)
#   cynkra-endpoint-check.sh install <name@cynkra.com>
#                                                 install; runs at login and once a day
#   cynkra-endpoint-check.sh owner <name@cynkra.com>
#                                                 set the owner only (with Homebrew: brew services
#                                                 start cynkra-endpoint-check runs it at login and daily)
#   cynkra-endpoint-check.sh run [--force]         check, report, notify (LaunchAgent)
#   cynkra-endpoint-check.sh uninstall             remove everything (offboarding)
#   --offline  skip the steps that need the network (outdated packages, vulnerability check)
# Installation, scheduled runs, notifications and the report to a Google Form are taken
# over from the device-check proof of concept (PR #26).

MAX_LOCK_SECONDS=300    # ISMS ch. 13: screen lock after at most 5 minutes
MAX_XPROTECT_DAYS=45    # XProtect normally updates every 1–3 weeks
SUDO_FAIL_FROM=2027-01-01  # passwordless sudo is a WARN until this date, then a FAIL
MIN_MACOS_MAJOR=26      # current or previous major version (PR #9); 15 was followed by 26; update every autumn
PENDING_FAIL_DAYS=14    # pending updates within the installed major version: FAIL after 14 days
VULN_INTERVAL_DAYS=7    # scheduled runs: vulnerability check once a week
REPORT_INTERVAL_HOURS=20  # report at most this often, unless the status changes
NOTIFY_INTERVAL_HOURS=20  # repeat the alert for failed checks at most this often

# Google Form for the central overview (empty: send nothing). Form and Sheet setup:
# handbook/endpoints/uebersicht/ in the ISMS repository. The form is writable without login; the reports are a
# convenience, the evidence is the monthly export to the ISMS repository.
FORM_URL="${CYNKRA_ENDPOINT_CHECK_FORM_URL-https://docs.google.com/forms/d/e/1FAIpQLSddA7vSG9aLSW9p4wHtDZhP0GZQi4-OL8KR9YjeTtehA24pSg/formResponse}"  # tests set CYNKRA_ENDPOINT_CHECK_FORM_URL= to send nothing
ENTRY_DEVICE_ID="entry.358592572"
ENTRY_OWNER="entry.855206442"
ENTRY_MODEL="entry.1513216855"
ENTRY_OS_VERSION="entry.1072409779"
ENTRY_STATUS="entry.1326653575"
ENTRY_DETAILS="entry.1302829151"
ENTRY_SCRIPT_VERSION="entry.1572118900"
HELP_URL=""             # optional: guide offered in the alert
GUIDE_URL="https://github.com/cynkra/homebrew-tap/blob/main/docs/credentials.md"  # credentials guide

SCRIPT_VERSION="0.3.5"
LABEL="ch.cynkra.endpoint-check"
APP_DIR="$HOME/Library/Application Support/cynkra-endpoint-check"
OLD_APP_DIR="$HOME/Library/Application Support/cynkra-baseline-check"  # before 0.3.0
[[ -d "$OLD_APP_DIR" && ! -e "$APP_DIR" ]] && mv "$OLD_APP_DIR" "$APP_DIR"
INSTALLED_SCRIPT="$APP_DIR/cynkra-endpoint-check.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/$LABEL.log"

state_get() { cat "$APP_DIR/$1" 2>/dev/null; }
state_set() { mkdir -p "$APP_DIR" && print -r -- "$2" > "$APP_DIR/$1"; }
log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*"; }
progress() { [[ "$cmd" == (check|run) && -t 2 ]] && print -u2 -r -- "… $*"; }

usage() {
  cat <<USAGE
cynkra-endpoint-check $SCRIPT_VERSION: read-only security check of this Mac (changes nothing, needs no admin rights)

Usage:
  cynkra-endpoint-check [check] [--offline] [--json]
                                               show the result now; writes no files and sends nothing;
                                               --offline skips the steps that need the network (outdated
                                               packages, vulnerabilities); --json prints the full report
                                               as JSON (save it with > report.json)
  cynkra-endpoint-check owner name@cynkra.com  register this Mac to you; only registered Macs report
  cynkra-endpoint-check run [--force]          check, report to cynkra, notify (what the background
                                               service runs once a day)
  cynkra-endpoint-check --version | --help

Background service: brew services start cynkra-endpoint-check
More: https://github.com/cynkra/homebrew-tap
USAGE
}

cmd=check force=false offline=false json=false
case "$1" in
  -h|--help|help) usage; exit 0 ;;
  -V|--version|version) print -r -- "cynkra-endpoint-check $SCRIPT_VERSION"; exit 0 ;;
  check|run|install|uninstall|owner) cmd=$1; shift ;;
  -*) ;;
  ?*) print -u2 -r -- "Unknown command: $1"; usage >&2; exit 2 ;;
esac
if [[ "$cmd" == (check|run) ]]; then
  for a in "$@"; do
    case "$a" in
      --offline) offline=true ;;
      --force) force=true ;;
      --json) json=true ;;
      -h|--help) usage; exit 0 ;;
      *) print -u2 -r -- "Unknown option: $a"; usage >&2; exit 2 ;;
    esac
  done
fi

if [[ "$cmd" == owner ]]; then
  [[ "$1" == ?*@cynkra.com ]] || { echo "Usage: $0 owner name@cynkra.com" >&2; exit 2; }
  state_set owner "$1"; echo "Owner set to $1."; exit 0
fi

if [[ "$cmd" == install ]]; then
  owner=$1
  [[ "$owner" == ?*@cynkra.com ]] || { echo "Usage: $0 install name@cynkra.com" >&2; exit 2; }
  mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  cp "$0" "$INSTALLED_SCRIPT" && chmod 755 "$INSTALLED_SCRIPT"
  state_set owner "$owner"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$INSTALLED_SCRIPT</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>86400</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG_FILE</string>
  <key>StandardErrorPath</key><string>$LOG_FILE</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "Installed for $owner; the check runs at login and once a day."
  exit 0
fi

if [[ "$cmd" == uninstall ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST" "$LOG_FILE"
  rm -rf "$APP_DIR"
  echo "Baseline check removed."
  exit 0
fi

fails=0
report=""
rows=""

result() {  # result <PASS|FAIL|WARN|INFO> <check> <detail> [<summary for log and central report>]
  [[ "$1" == "FAIL" ]] && (( fails++ ))
  report+=$(printf "%-4s  %-22s %s" "$1" "$2" "$3")$'\n'
  rows+="$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\n'
}

progress "checking security settings"

# Running inside a virtual machine (e.g. a customer VM in VirtualBuddy)?
in_vm=false
[[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] && in_vm=true

# Owner: without it the central overview cannot tell whose device a report is from
if [[ -n "$(state_get owner)" ]]; then
  result PASS "Owner" "$(state_get owner)"
else
  result WARN "Owner" "not set (cynkra-endpoint-check owner name@cynkra.com)"
fi

# FileVault
case "$(fdesetup status 2>/dev/null)" in
  *"Decryption in progress"*) result FAIL "FileVault" "being turned off; keep it on" ;;
  *"Encryption in progress"*) result WARN "FileVault" "encryption in progress; keep the device on power" ;;
  *"FileVault is On"*)        result PASS "FileVault" "on" ;;
  *)                          result FAIL "FileVault" "off (System Settings > Privacy & Security > FileVault)" ;;
esac

# Firewall
if "${SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}" --getglobalstate | grep -q "enabled"; then
  result PASS "Firewall" "on"
else
  result FAIL "Firewall" "off"
fi

# Gatekeeper and System Integrity Protection
if spctl --status 2>/dev/null | grep -q "enabled"; then
  result PASS "Gatekeeper" "on"
else
  result FAIL "Gatekeeper" "off"
fi
case "$(csrutil status 2>/dev/null)" in
  *"status: enabled."*) result PASS "SIP" "on" ;;
  *"status: enabled"*)  result WARN "SIP" "only partly on (custom configuration)" ;;
  *)                    result FAIL "SIP" "off (csrutil enable in recovery mode)" ;;
esac

# Automatic security updates (XProtect signatures, security responses)
su_prefs=/Library/Preferences/com.apple.SoftwareUpdate
config_data=$(defaults read $su_prefs ConfigDataInstall 2>/dev/null || echo 1)
critical=$(defaults read $su_prefs CriticalUpdateInstall 2>/dev/null || echo 1)
if [[ "$config_data" == "1" && "$critical" == "1" ]]; then
  result PASS "Auto security updates" "on"
else
  result FAIL "Auto security updates" "off (System Settings > General > Software Update)"
fi
# A missing key means the macOS default (on); macOS writes the value only when it is turned off
off=()
for key in AutomaticCheckEnabled AutomaticDownload; do
  [[ "$(defaults read $su_prefs $key 2>/dev/null)" == 0 ]] && off+=($key)
done
(( ${#off} )) && result WARN "Auto update check" "${(j:, :)off} off (System Settings > General > Software Update > Automatic updates)"

# XProtect age
xp_date=$(system_profiler SPInstallHistoryDataType -json 2>/dev/null | python3 -c '
import json, sys
items = json.load(sys.stdin)["SPInstallHistoryDataType"]
dates = [i["install_date"] for i in items if i["_name"].startswith("XProtect")]
print(max(dates)[:10] if dates else "")')
if [[ -n "$xp_date" ]]; then
  age=$(( ( $(date +%s) - $(date -j -f "%Y-%m-%d" "$xp_date" +%s) ) / 86400 ))
  if (( age <= MAX_XPROTECT_DAYS )); then
    result PASS "XProtect" "last update $xp_date ($age days)"
  else
    result FAIL "XProtect" "last update $xp_date ($age days)"
  fi
else
  result WARN "XProtect" "no update found in install history"
fi

# Screen lock: idle time until screensaver or display sleep, plus password delay
delay=$(sysadminctl -screenLock status 2>&1 | sed -nE 's/.*delay is ([0-9]+) seconds.*/\1/p')
[[ -z "$delay" ]] && sysadminctl -screenLock status 2>&1 | grep -q "immediate" && delay=0
saver=$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)
display=$(( $(pmset -g | awk '/ displaysleep /{print $2}') * 60 ))
idle=$display
[[ -n "$saver" && "$saver" -gt 0 && ( "$display" -eq 0 || "$saver" -lt "$display" ) ]] && idle=$saver
if [[ -z "$delay" || "$idle" -eq 0 ]]; then
  result FAIL "Screen lock" "not set (display sleep or password requirement off)"
else
  lock=$(( idle + delay ))
  if (( lock <= MAX_LOCK_SECONDS )); then
    result PASS "Screen lock" "after $(( lock / 60 )) min"
  else
    result FAIL "Screen lock" "after $(( lock / 60 )) min, max. $(( MAX_LOCK_SECONDS / 60 )) min (System Settings > Lock Screen: require password immediately, screen saver or display off after at most $(( MAX_LOCK_SECONDS / 60 )) min)"
  fi
fi

# Automatic login
if defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser >/dev/null 2>&1; then
  result FAIL "Automatic login" "on"
else
  result PASS "Automatic login" "off"
fi

# Passwordless sudo: root privileges need a human confirmation (password or Touch ID)
sudo -k 2>/dev/null
if sudo -n true 2>/dev/null; then
  sudo_status=WARN
  [[ ! "$(date +%Y-%m-%d)" < "$SUDO_FAIL_FROM" ]] && sudo_status=FAIL
  if $in_vm; then  # no Touch ID in a VM
    result $sudo_status "Passwordless sudo" "on; remove the NOPASSWD rule (sudo grep -rl NOPASSWD /etc/sudoers /etc/sudoers.d) and use the password"
  else
    result $sudo_status "Passwordless sudo" "on; use Touch ID instead: echo 'auth sufficient pam_tid.so' | sudo tee /etc/pam.d/sudo_local"
  fi
elif grep -qs pam_tid /etc/pam.d/sudo_local /etc/pam.d/sudo; then
  result PASS "Passwordless sudo" "off (Touch ID for sudo)"
else
  result PASS "Passwordless sudo" "off"
fi

# SSH private keys in ~/.ssh: passphrase recommended (ISMS ch. 7); keys held in an
# agent such as 1Password or the Secure Enclave are not files and are not listed here
unencrypted=()
for f in ~/.ssh/*(N.); do
  head -1 "$f" 2>/dev/null | grep -q "PRIVATE KEY" || continue
  ssh-keygen -y -P "" -f "$f" >/dev/null 2>&1 && unencrypted+=("${f:t}")
done
op_agent=""
grep -qiE '^[[:space:]]*IdentityAgent[[:space:]].*(1password|2BUA8C4S2C)' ~/.ssh/config 2>/dev/null \
  && op_agent="; 1Password SSH agent configured"
if (( ${#unencrypted} )); then
  result WARN "SSH keys" "without passphrase: ${(j:, :)unencrypted} (ssh-keygen -p -f ~/.ssh/<key>, or move them to 1Password; guide: $GUIDE_URL#ssh)$op_agent" \
    "${#unencrypted} without passphrase"
else
  result PASS "SSH keys" "no unencrypted private keys in ~/.ssh$op_agent"
fi

# Plaintext credentials (warning only, rule introduced in stages): reads only the files listed
# here (shell startup files and the files they source, .Renviron, .Rprofile, tool configs) and
# reports file and variable names locally, never values; the central report only says that
# something was found. It catches honest mistakes, it cannot enforce the rule: project .env files,
# scripts and tool caches are not read. Where a tool says how it stores credentials (git credential
# helper, Docker credsStore), that is checked instead of the file contents. op:// references (for
# op run), other variables, paths and empty values are fine; secrets fetched from a password
# manager at shell start (export X=$(op read ...)) are reported, since every process inherits them.
# Each finding names its fix and the section of the guide (GUIDE_URL). False positives go into
# the ignore list, one variable name or file path (~/...) per line.
ignore_file="$APP_DIR/plaintext-ignore"
ignored=(${(f)"$(sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]]+$//' "$ignore_file" 2>/dev/null)"})
ignored=(${ignored/#$HOME/~})
plain=()
plain_add() {  # plain_add <file> <fix> <guide section> [<what>]
  (( ${ignored[(Ie)$1]} )) || plain+=("$1${4:+: $4} → $2 (#$3)")
}
[[ -f ~/.netrc ]] && grep -qE '(^|[[:space:]])password[[:space:]]' ~/.netrc \
  && plain_add "~/.netrc" "op inject from a template" config-files
# git: the credential helper "store" writes plaintext on first use, even before ~/.git-credentials exists
git_store=false
[[ -f ~/.gitconfig || -f ~/.config/git/config ]] \
  && git config --global --get-all credential.helper 2>/dev/null | grep -qE '^[[:space:]]*store([[:space:]]|$)' && git_store=true
if [[ -s ~/.git-credentials ]]; then
  plain_add "~/.git-credentials" "git config --global credential.helper osxkeychain, then delete the file" git
elif $git_store; then
  plain_add "~/.gitconfig" "git config --global credential.helper osxkeychain" git "credential.helper store"
fi
# AWS: only static keys; SSO profiles and credential_process in ~/.aws/config are fine
[[ -f ~/.aws/credentials ]] && grep -q 'aws_secret_access_key' ~/.aws/credentials \
  && plain_add "~/.aws/credentials" "aws configure sso, or op plugin init aws" aws
# npm: a token written into the file; _authToken=${NPM_TOKEN} reads it from the environment
[[ -f ~/.npmrc ]] && grep -E '_authToken=' ~/.npmrc | grep -qvE '_authToken=[[:space:]]*(\$\{|$)' \
  && plain_add "~/.npmrc" '_authToken=${NPM_TOKEN} with op run' config-files
[[ -f ~/.pypirc ]] && grep -qE '^[[:space:]]*password' ~/.pypirc \
  && plain_add "~/.pypirc" "keyring, or TWINE_PASSWORD with op run" python
# gh: a token in hosts.yml means a login with --insecure-storage; by default gh uses the keychain
[[ -f ~/.config/gh/hosts.yml ]] && grep -q 'oauth_token:' ~/.config/gh/hosts.yml \
  && plain_add "~/.config/gh/hosts.yml" "gh auth logout && gh auth login" gh
[[ -f ~/.docker/config.json ]] && python3 -c '
import json, os, sys
d = json.load(open(os.path.expanduser("~/.docker/config.json")))
sys.exit(0 if not d.get("credsStore") and any(v.get("auth") for v in d.get("auths", {}).values()) else 1)' 2>/dev/null \
  && plain_add "~/.docker/config.json" 'set "credsStore": "osxkeychain", then docker login again' docker
# Shell startup files and the files they source (source/. lines, paths in $HOME outside ~/Library;
# paths built from other variables or commands are not followed)
shell_files=() queue=(~/.zshrc ~/.zprofile ~/.zshenv ~/.zlogin ~/.bash_profile ~/.bashrc ~/.profile)
while (( ${#queue} && ${#shell_files} < 50 )); do
  f=${queue[1]}; shift queue
  [[ -f $f ]] && (( ! ${shell_files[(Ie)$f]} )) || continue
  shell_files+=("$f")
  for src in ${(f)"$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null \
      | grep -oE '(^|[;&|{]|then|do)[[:space:]]*(source|\.)[[:space:]]+[^[:space:];&|)]+' \
      | sed -E 's/.*(source|\.)[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')"}; do
    src=${src/#\~/$HOME}; src=${src/#\$\{HOME\}/$HOME}; src=${src/#\$HOME/$HOME}
    [[ $src == *['$`']* ]] && continue
    [[ $src == /* ]] || src=$HOME/$src
    [[ $src == $HOME/* && $src != $HOME/Library/* ]] && queue+=("$src")
  done
done
name_re='[A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|_PAT|_KEY)[A-Za-z0-9_]*'
fetch_re='(\$\(|`)[[:space:]]*(op (read|item get)|security find-(generic|internet)-password|gh auth token|bw get)'
for f in $shell_files ~/.Renviron; do
  [[ -f $f ]] && (( ! ${ignored[(Ie)${f/#$HOME/~}]} )) || continue
  vars=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$name_re=" "$f" \
    | grep -vE '=[[:space:]]*["'"'"']?([$`/~]|op://|$)' \
    | sed -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z0-9_]+)=.*/\2/' | sort -u)
  vars=(${(f)vars}); vars=(${vars:|ignored})
  if (( ${#vars} )); then
    if [[ $f == */.Renviron ]]; then
      fix="keyring::key_get() at the point of use"
      (( ${vars[(Ie)GITHUB_PAT]} )) && fix="gitcreds::gitcreds_set()${${vars:#GITHUB_PAT}:+ for GITHUB_PAT, keyring::key_get() for the others}"
      plain_add "${f/#$HOME/~}" "$fix" r "${(j:, :)vars}"
    else
      plain_add "${f/#$HOME/~}" "op:// reference + op run" env-vars "${(j:, :)vars}"
    fi
  fi
  # Fetched from a password manager at shell start (export X=$(op read ...)): off the disk, but in
  # the environment of every process started from the shell; any variable name counts
  [[ $f == */.Renviron ]] && continue
  fetched=$(grep -E "^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=[\"']?$fetch_re" "$f" \
    | sed -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z0-9_]+)=.*/\2/' | sort -u)
  fetched=(${(f)fetched}); fetched=(${fetched:|ignored})
  (( ${#fetched} )) && plain_add "${f/#$HOME/~}" "fetch at the point of use, op run for tools, or a CLI plugin" \
    how-to-use-them "${(j:, :)fetched} (set at shell start)"
done
# R: Sys.setenv() with a token-like name in ~/.Rprofile puts the secret into every R session,
# wherever the value comes from
if [[ -f ~/.Rprofile ]]; then
  rvars=$(grep -vE '^[[:space:]]*#' ~/.Rprofile | grep -oE 'Sys\.setenv\(.*' \
    | grep -oE "${name_re}[[:space:]]*=" | sed -E 's/[[:space:]]*=$//' | sort -u)
  rvars=(${(f)rvars}); rvars=(${rvars:|ignored})
  (( ${#rvars} )) && plain_add "~/.Rprofile" "gh::gh_token() or keyring::key_get() at the point of use" r \
    "Sys.setenv(${(j:, :)rvars})"
fi
if (( ${#plain} )); then
  result WARN "Plaintext credentials" "${(j:; :)plain}; false positive? add the name to ${ignore_file/#$HOME/~} (#false-positive); guide: $GUIDE_URL" \
    "found (names: cynkra-endpoint-check check)"
else
  result PASS "Plaintext credentials" "none found in the usual places"
fi

# 1Password (on the host; a customer VM gets its password from the host's password manager)
if [[ -d ${ONEPASSWORD_APP:-/Applications/1Password.app} ]]; then
  result PASS "1Password" "installed"
elif $in_vm; then
  result INFO "1Password" "not installed (customer VM)"
else
  result FAIL "1Password" "not installed"
fi

# Find My Mac: lets a lost device be located, locked and erased (not available in VMs).
# macOS 27 keeps the status in /Library/Preferences/com.apple.FindMyMac; older versions in the account list
if $in_vm; then
  result INFO "Find My Mac" "not available in a VM"
elif [[ "$(defaults read /Library/Preferences/com.apple.FindMyMac FMMEnabled 2>/dev/null)" == 1 ]] || python3 -c '
import os, plistlib, sys
d = plistlib.load(open(os.path.expanduser("~/Library/Preferences/MobileMeAccounts.plist"), "rb"))
sys.exit(0 if any(s.get("Name") == "FIND_MY_MAC" and s.get("Enabled")
                  for a in d.get("Accounts", []) for s in a.get("Services", [])) else 1)' 2>/dev/null; then
  result PASS "Find My Mac" "on"
else
  result FAIL "Find My Mac" "off (System Settings > Apple Account > iCloud > Find My Mac)"
fi

# Customer VM: controls that run only inside the VM
if $in_vm; then
  # all traffic through the cynkra VPN (WireGuard full tunnel)
  if route -n get default 2>/dev/null | grep -q "interface: utun"; then
    result PASS "VPN full tunnel" "default route via $(route -n get default | awk '/interface:/{print $2}')"
  else
    result FAIL "VPN full tunnel" "default route not via VPN (start the cynkra WireGuard tunnel)"
  fi
  # Fleet agent (fleetd: orbit and osqueryd)
  if pgrep -x orbit >/dev/null || pgrep -x osqueryd >/dev/null; then
    result PASS "Fleet agent" "running"
  else
    result FAIL "Fleet agent" "not running (install the fleetd package from the security team)"
  fi
  # No AI extensions in VS Code: customer contracts allow AI only through the customer's tools
  ai=$(ls -1 ~/.vscode/extensions 2>/dev/null | grep -iE '^(github\.copilot|continue\.|codeium\.|saoudrizwan\.claude-dev|anthropic\.|tabnine\.|amazonwebservices\.amazon-q|sourcegraph\.cody|rooveterinaryinc\.|kilocode\.)' | sed -E 's/-[0-9][^-]*$//' | sort -u)
  if [[ -n "$ai" ]]; then
    result FAIL "AI extensions" "${(j:, :)${(f)ai}} (remove; only the customer's AI tools are allowed)" \
      "$(print -r -- "$ai" | grep -c .) installed"
  else
    result PASS "AI extensions" "none in VS Code"
  fi
fi

# macOS major version still receiving security updates (current or previous major)
major=$(sw_vers -productVersion | cut -d. -f1)
if (( major >= MIN_MACOS_MAJOR )); then
  result PASS "macOS version" "$(sw_vers -productVersion) receives security updates"
else
  result FAIL "macOS version" "$(sw_vers -productVersion) is two major versions behind; upgrade to macOS $((MIN_MACOS_MAJOR + 1))"
fi

# Pending updates within the installed major version and Safari, read from the list macOS
# keeps in the background (no network needed); upgrades to a new major version do not count.
# FAIL once an update has been pending for PENDING_FAIL_DAYS (first seen by this check).
pending=() other=()
n=$(plutil -extract RecommendedUpdates raw -o - $su_prefs.plist 2>/dev/null)
[[ "$n" == <-> ]] || n=0
for (( i = 0; i < n; i++ )); do
  name=$(plutil -extract "RecommendedUpdates.$i.Display Name" raw -o - $su_prefs.plist 2>/dev/null)
  ver=$(plutil -extract "RecommendedUpdates.$i.Display Version" raw -o - $su_prefs.plist 2>/dev/null)
  [[ "$name" == macOS* && "${ver%%.*}" != "$major" ]] && continue
  [[ "$name" == *"$ver"* ]] || name="$name $ver"
  if [[ "$name" == macOS* || "$name" == Safari* ]]; then pending+=("$name"); else other+=("$name"); fi
done
(( ${#other} )) && result INFO "Other updates" "${(j:, :)other}"
if (( ${#pending} )); then
  since=$(state_get pending_since); [[ "$since" == <-> ]] || { since=$(date +%s); state_set pending_since $since; }
  days=$(( ( $(date +%s) - since ) / 86400 ))
  if (( days >= PENDING_FAIL_DAYS )); then
    result FAIL "Pending updates" "${(j:, :)pending}, pending for $days days (System Settings > General > Software Update)"
  else
    result WARN "Pending updates" "${(j:, :)pending}; install within $PENDING_FAIL_DAYS days"
  fi
else
  rm -f "$APP_DIR/pending_since"
  result PASS "Pending updates" "none required"
fi

progress "counting outdated packages (Homebrew, R, Python; needs network)"
# Outdated packages: counted with each ecosystem's own tool (needs network; not in scheduled runs)
if ! $offline && [[ "$cmd" == check ]]; then
  outdated=()
  command -v brew >/dev/null && \
    outdated+=("Homebrew $(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet 2>/dev/null | grep -c .)")
  command -v Rscript >/dev/null && \
    outdated+=("R $(Rscript -e 'cat(NROW(old.packages(repos = "https://cloud.r-project.org")))' 2>/dev/null)")
  command -v python3 >/dev/null && \
    outdated+=("Python $(python3 -m pip list --outdated --format=freeze 2>/dev/null | grep -c .)")
  (( ${#outdated} )) && result INFO "Outdated packages" "${(j:, :)outdated}"
fi

progress "checking containers and autostart entries"
# Containers: any runtime with a docker- or podman-compatible CLI (OrbStack, Colima,
# Docker Desktop, Rancher Desktop, Podman). Lists images; flags ports published to all interfaces.
container_images=""
for cli in docker podman; do
  command -v $cli >/dev/null && $cli info >/dev/null 2>&1 || continue
  imgs=$($cli images --digests --format '{{.Repository}}:{{.Tag}}@{{.Digest}}' 2>/dev/null | sort -u)
  container_images+="$imgs"$'\n'
  open_ports=$($cli ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E '0\.0\.0\.0:|\[::\]:|:::' )
  if [[ -n "$open_ports" ]]; then
    result WARN "Container ports ($cli)" "published to all interfaces: ${(j:; :)${(f)open_ports}} (use -p 127.0.0.1:…)" \
      "$(print -r -- "$open_ports" | grep -c .) containers published to all interfaces"
  else
    result PASS "Container ports ($cli)" "none published to all interfaces"
  fi
  result INFO "Container images ($cli)" "$(print -r -- "$imgs" | grep -c .) images (listed by check --json)"
done

# Autostart entries: launchd jobs are where macOS malware typically persists. Counted are only
# jobs that start by themselves (RunAtLoad or KeepAlive) and are not disabled; jobs that are only
# registered and start on demand (MachServices) are not. A job that is new since the last run is a
# warning sign, so it is reported; the first run only records the current state.
disabled=$( { launchctl print-disabled gui/$(id -u); launchctl print-disabled system; } 2>/dev/null \
  | sed -nE 's/^[[:space:]]*"([^"]+)" => (disabled|true).*/\1/p')
autostart=""
for f in ${=AUTOSTART_DIRS:-~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons}; do
  for p in $f/*.plist(N); do
    label=$(plutil -extract Label raw -o - "$p" 2>/dev/null) || label=${p:t:r}
    print -r -- "$disabled" | grep -qxF -- "$label" && continue
    runs=$(plutil -extract RunAtLoad raw -o - "$p" 2>/dev/null)
    keep=$(plutil -extract KeepAlive raw -o - "$p" 2>/dev/null)
    [[ "$runs" == true || "$keep" == true ]] \
      || plutil -extract KeepAlive xml1 -o - "$p" 2>/dev/null | grep -q '<dict>' \
      || plutil -extract StartInterval raw -o - "$p" >/dev/null 2>&1 \
      || plutil -extract StartCalendarInterval xml1 -o - "$p" >/dev/null 2>&1 || continue
    autostart+="$label"$'\n'
  done
done
autostart=$(print -r -- "$autostart" | grep . | sort -u)
known=$(state_get autostart_known)
if [[ -n "$known" ]]; then
  new=$(comm -13 <(print -r -- "$known") <(print -r -- "$autostart") | grep .)
  if [[ -n "$new" ]]; then
    # names: run records them as known, so a later check no longer lists them; last-report.txt keeps them
    result WARN "New autostart entries" "${(j:, :)${(f)new}} (since the last check; turn off if not needed)" \
      "$(print -r -- "$new" | grep -c .) new (names: ${APP_DIR/#$HOME/~}/last-report.txt)"
  fi
fi
state_set autostart_known "$autostart"
result INFO "Autostart entries" "$(print -r -- "$autostart" | grep -c .) start by themselves (listed by check --json)"

# Vulnerability check, entirely on the device: syft builds a software inventory (SBOM) of
# developer tooling (Homebrew, R libraries, Python site-packages, global npm packages),
# OSV-Scanner matches it offline against OSV.dev, including advisories on malicious
# packages, as for container images. Applications in /Applications are not scanned: no
# reliable advisory source exists for them, and the list would reveal private apps; they
# are covered by the update rules. The inventory never leaves the device; the report
# contains only the findings. Fixable = a fixed version exists and the package is managed
# by the user directly; packages bundled inside Homebrew formulas are fixed by brew upgrade.
findings=""
vuln_due=true
if [[ "$cmd" == run ]] && ! $force; then
  last_vuln=$(state_get last_vuln); [[ "$last_vuln" == <-> ]] || last_vuln=0
  (( $(date +%s) - last_vuln < VULN_INTERVAL_DAYS * 86400 )) && vuln_due=false
fi
if $offline || ! $vuln_due; then
  result INFO "Vulnerability check" "skipped ($($offline && echo offline || echo "runs weekly"))"
elif command -v syft >/dev/null && command -v osv-scanner >/dev/null; then
  state_set last_vuln $(date +%s)
  progress "scanning developer packages for known vulnerabilities (about a minute)"
  tmp=$(mktemp -d)
  targets=() kinds=()
  add() { [[ -d "$2" ]] && { targets+=("$2"); kinds+=("$1"); } }
  command -v brew >/dev/null && add brew "$(brew --prefix)"
  # All R and Python installations in the usual places, not only the first on PATH:
  # R from CRAN/rig and Homebrew, user libraries; Python from Homebrew, python.org, the user
  # site, pyenv, uv, pipx and conda. Virtual environments inside projects are not searched.
  for l in /Library/Frameworks/R.framework/Versions/*/Resources/library(N/) ~/Library/R/*/*/library(N/) \
           /opt/homebrew/lib/R/*/site-library(N/) \
           /opt/homebrew/lib/python3.*/site-packages(N/) \
           /Library/Frameworks/Python.framework/Versions/*/lib/python3.*/site-packages(N/) \
           ~/Library/Python/*/lib/python/site-packages(N/) \
           ~/.pyenv/versions/*/lib/python3.*/site-packages(N/) \
           ~/.local/share/uv/{tools,python}/*/lib/python3.*/site-packages(N/) \
           ~/.local/pipx/venvs/*/lib/python3.*/site-packages(N/) \
           ~/{miniforge3,mambaforge,miniconda3,anaconda3}{,/envs/*}/lib/python3.*/site-packages(N/) \
           ~/.nvm/versions/node/*/lib/node_modules(N/); do
    add user "$l"
  done
  command -v npm >/dev/null && add user "$(npm root -g 2>/dev/null)"
  for (( i = 1; i <= ${#targets}; i++ )); do
    print -r -- "${kinds[i]}" > "$tmp/$i.kind"
    print -r -- "${targets[i]/#$HOME/~}" > "$tmp/$i.target"
    # Library/Taps holds the formula catalogues of Homebrew taps, not installed software
    syft scan "dir:${targets[i]}" -q --exclude './Library/Taps/**' -o syft-json > "$tmp/$i.json" 2>/dev/null
  done
  python3 - "$tmp" <<'PY'
import glob, json, os, sys
d = sys.argv[1]
keep = ("pkg:brew/", "pkg:cran/", "pkg:pypi/", "pkg:npm/", "pkg:gem/")
seen, components, where, unknown, known = set(), [], {}, set(), set()
for f in sorted(glob.glob(d + "/*.json")):
    kind = open(f[:-5] + ".kind").read().strip()
    target = open(f[:-5] + ".target").read().strip()
    for a in json.load(open(f)).get("artifacts", []):
        purl = (a.get("purl") or "").split("?")[0]
        if not purl.startswith(keep):
            continue
        base = purl.split("@")[0]
        # Entries without a version (e.g. a gemspec whose version is computed at runtime)
        # are dropped if the same package is also found with a version, otherwise reported
        # as "version unknown" without an alert.
        if a["version"] in ("", "UNKNOWN"):
            unknown.add(base)
            continue
        known.add(base)
        key = (a["name"].lower(), a["version"])
        managed = kind == "user" or (kind == "brew" and purl.startswith("pkg:brew/"))
        if managed:
            where.setdefault(key, set()).update({"user", "at:" + target})
        else:
            # bundled inside a Homebrew formula or cask: name it from the Cellar/Caskroom path
            for loc in a.get("locations", []):
                parts = loc.get("path", "").strip("/").split("/")
                for anchor in ("Cellar", "Caskroom"):
                    if anchor in parts and parts.index(anchor) + 1 < len(parts):
                        where.setdefault(key, set()).add("brew:" + parts[parts.index(anchor) + 1])
            where.setdefault(key, set()).add("bundled")
        if purl not in seen:
            seen.add(purl)
            components.append({"type": "library", "name": a["name"], "version": a["version"], "purl": purl})
json.dump({"bomFormat": "CycloneDX", "specVersion": "1.5", "components": components},
          open(d + "/sbom.cdx.json", "w"))
json.dump({f"{k[0]}\t{k[1]}": sorted(v) for k, v in where.items()}, open(d + "/where.json", "w"))
json.dump(sorted(u.split("/", 1)[1] for u in unknown - known), open(d + "/unknown.json", "w"))
PY
  osv-scanner scan -L "$tmp/sbom.cdx.json" --offline-vulnerabilities --download-offline-databases \
    --format json > "$tmp/osv.json" 2>/dev/null
  findings=$(python3 - "$tmp" <<'PY'
import json, sys
d = sys.argv[1]
where = json.load(open(d + "/where.json"))
try:
    results = json.load(open(d + "/osv.json")).get("results", [])
except Exception:
    results = []
out = {"malicious": [], "fixable": [], "other": [], "version_unknown": json.load(open(d + "/unknown.json"))}
for r in results:
    for p in r.get("packages", []):
        pkg, vulns = p["package"], p.get("vulnerabilities", [])
        ids = sorted({v["id"] for v in vulns})
        fixed = any(e.get("fixed") for v in vulns for a in v.get("affected", [])
                    for rg in a.get("ranges", []) for e in rg.get("events", []))
        loc = where.get(f"{pkg['name'].lower()}\t{pkg['version']}", [])
        entry = {"ecosystem": pkg["ecosystem"], "name": pkg["name"], "version": pkg["version"],
                 "ids": ids[:10], "advisories": len(ids), "max_severity": max((g.get("max_severity") or "" for g in p.get("groups", [])), default="")}
        formulas = sorted(l[5:] for l in loc if l.startswith("brew:"))
        if formulas:
            entry["formulas"] = formulas
        dirs = sorted(l[3:] for l in loc if l.startswith("at:"))
        if dirs:
            entry["where"] = dirs
        if any(i.startswith("MAL-") for i in ids):
            out["malicious"].append(entry)
        elif fixed and "user" in loc:
            out["fixable"].append(entry)
        else:
            out["other"].append(entry)
print(json.dumps(out))
PY
)
  rm -rf "$tmp"
  read mal fix oth <<< "$(print -r -- "$findings" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["malicious"]), len(d["fixable"]), len(d["other"]))')"
  if (( mal )); then
    result FAIL "Malicious packages" "$mal (listed by check --json; remove immediately and inform the CISO)"
  else
    result PASS "Malicious packages" "none"
  fi
  if (( fix )); then
    # where they are, so that it is clear which installation to update or remove
    fix_where=$(print -r -- "$findings" | python3 -c '
import collections, json, sys
per = collections.Counter(w for e in json.load(sys.stdin)["fixable"] for w in e.get("where", ["?"]))
print(", ".join(f"{w} {n}" for w, n in per.most_common(6)) + (f", {len(per) - 6} more" if len(per) > 6 else ""))')
    result WARN "Vulnerable packages" "$fix fixable in $fix_where (update within 14 days, or remove installations you no longer use; details: check --json)" \
      "$fix fixable (details: cynkra-endpoint-check check)"
  else
    result PASS "Vulnerable packages" "none fixable"
  fi
  unk=$(print -r -- "$findings" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["version_unknown"]))')
  (( unk )) && result INFO "Version unknown" "$unk packages could not be checked (listed by check --json)"
  if (( oth )); then
    # Packages bundled in Homebrew formulas are updated by the formula maintainers, not by
    # brew upgrade; the only lever is removing tools that are not needed. Summarised per formula.
    adv_summary=$(print -r -- "$findings" | python3 -c '
import collections, json, sys
other = json.load(sys.stdin)["other"]
per = collections.Counter(f for e in other for f in e.get("formulas", []))
rest = sum(1 for e in other if not e.get("formulas"))
parts = [f"{f} {n}" for f, n in per.most_common(8)]
if len(per) > 8:
    parts.append(f"{len(per) - 8} more formulas")
line = ""
if parts:
    line = "in Homebrew formulas: " + ", ".join(parts) + " (fixed when the formula is updated; uninstall tools you do not use)"
if rest:
    line += ("; " if line else "") + f"{rest} without a fix yet"
print(line)')
    result INFO "Other advisories" "$oth advisories, nothing to do now: $adv_summary"
  fi
else
  result WARN "Vulnerability check" "needs syft and osv-scanner (brew install syft osv-scanner)"
fi

host=$(scutil --get LocalHostName 2>/dev/null || hostname)
# Device ID: hash of the serial number, enough to tell devices apart without storing the serial
serial=$(ioreg -l | awk -F'"' '/IOPlatformSerialNumber/{print $4; exit}' | shasum -a 256 | cut -c1-12)
header="cynkra endpoint check
Date:     $(date '+%Y-%m-%d %H:%M')
User:     $(id -un)
Device:   $host, ID $serial
macOS:    $(sw_vers -productVersion) ($(sw_vers -buildVersion))$($in_vm && echo ", virtual machine")
"
summary=$([[ $fails -eq 0 ]] && echo "Result: all checks passed" || echo "Result: $fails check(s) failed")

json_report() {
  printf "%s" "$rows" | python3 -c '
import json, sys
user, host, serial, macos, date, fails, autostart, images, findings = sys.argv[1:10]
checks = [{k: v for k, v in zip(["status", "check", "detail", "summary"], l.split("\t", 3)) if v}
          for l in sys.stdin.read().splitlines() if l]
json.dump({"date": date, "user": user, "host": host, "device_id": serial,
           "macos": macos, "failed": int(fails), "checks": checks,
           "autostart": [l for l in autostart.splitlines() if l],
           "container_images": [l for l in images.splitlines() if l],
           "findings": json.loads(findings) if findings else None},
          sys.stdout, indent=2, ensure_ascii=False)
' "$(id -un)" "$host" "$serial" "$(sw_vers -productVersion)" "$(date '+%Y-%m-%dT%H:%M')" "$fails" "$autostart" "$container_images" "$findings"
}

# Manual check: print only, write no files
if [[ "$cmd" == check ]]; then
  if $json; then
    json_report; echo
  else
    printf "%s\n%s\n%s\n" "$header" "$report" "$summary"
  fi
  exit 0
fi

# Scheduled run: keep the last report in the app directory
mkdir -p "$APP_DIR"; out="$APP_DIR/last-report"
if [[ ! -t 1 ]]; then  # log line only; in a terminal show the full report too
  printf "%s\n%s\n%s\n" "$header" "$report" "$summary" > "$out.txt"
else
  printf "%s\n%s\n%s\n" "$header" "$report" "$summary" | tee "$out.txt"
fi
json_report > "$out.json"

# Scheduled run: report to the central overview and notify the person if something is to do
overall=ok
print -r -- "$rows" | grep -q '^WARN' && overall=warn
(( fails )) && overall=fail
# Local log: full details. Central report: the check name and its summary only, never the
# detail, which can contain names of files, keys, variables, apps, containers or extensions
todo=$(print -r -- "$rows" | awk -F'\t' '$1=="FAIL"||$1=="WARN"{print $2": "$3}')
sent=$(print -r -- "$rows" | awk -F'\t' '$1=="FAIL"||$1=="WARN"{print $2($4!=""?": "$4:"")}')
log "status $overall; ${(j:; :)${(f)todo}}"

last=$(state_get last_report); [[ "$last" == <-> ]] || last=0
# Only devices registered to a cynkra address report; anyone else using the public tap sends nothing
[[ "$(state_get owner)" == ?*@cynkra.com ]] || FORM_URL=""
if [[ -n "$FORM_URL" ]] && { $force || [[ "$overall" != "$(state_get last_status)" ]] || \
     (( $(date +%s) - last >= REPORT_INTERVAL_HOURS * 3600 )); }; then
  model=$(sysctl -n hw.model)
  code=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$FORM_URL" \
    --data-urlencode "$ENTRY_DEVICE_ID=$serial" \
    --data-urlencode "$ENTRY_OWNER=$(state_get owner)" \
    --data-urlencode "$ENTRY_MODEL=$model" \
    --data-urlencode "$ENTRY_OS_VERSION=$(sw_vers -productVersion)" \
    --data-urlencode "$ENTRY_STATUS=$overall" \
    --data-urlencode "$ENTRY_DETAILS=${(j:; :)${(f)sent}}" \
    --data-urlencode "$ENTRY_SCRIPT_VERSION=$SCRIPT_VERSION") || code=000
  if [[ "$code" == 200 ]]; then
    state_set last_report $(date +%s); state_set last_status $overall; log "report sent ($overall)"
  else
    log "report failed (HTTP $code); retry at the next run"
  fi
fi

# Notify: FAIL as an alert, repeated at most every NOTIFY_INTERVAL_HOURS;
# WARN as a notification, only when a warning is new or has changed since the last run
warns=$(print -r -- "$rows" | awk -F'\t' '$1=="WARN"{print $2": "$3}')
new_warns=$(comm -13 <(state_get warns_seen | sort) <(print -r -- "$warns" | sort) | grep .)
state_set warns_seen "$warns"
last=$(state_get last_notify); [[ "$last" == <-> ]] || last=0
if [[ "$overall" == fail ]] && { $force || (( $(date +%s) - last >= NOTIFY_INTERVAL_HOURS * 3600 )); }; then
  msg=$(print -r -- "$rows" | awk -F'\t' '$1=="FAIL"{print $2": "$3}')
  osascript - "$msg" "$HELP_URL" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set msg to item 1 of argv
  set helpUrl to item 2 of argv
  if helpUrl is "" then
    display alert "Security check: action needed" message msg as critical buttons {"OK"} default button "OK" giving up after 900
  else
    set r to display alert "Security check: action needed" message msg as critical buttons {"Later", "Open guide"} default button "Open guide" giving up after 900
    if button returned of r is "Open guide" then open location helpUrl
  end if
end run
APPLESCRIPT
  state_set last_notify $(date +%s)
elif [[ -n "$new_warns" ]] || { $force && [[ -n "$warns" ]]; }; then
  msg=$(print -r -- "${new_warns:-$warns}" | head -1)
  # the detail is too long for a notification; show where the fix is explained instead
  [[ "$msg" == "Plaintext credentials:"* ]] && msg="Plaintext credentials found; how to fix: $GUIDE_URL"
  osascript - "$msg" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  display notification (item 1 of argv) with title "Security check" subtitle "Please take care of it soon"
end run
APPLESCRIPT
fi
