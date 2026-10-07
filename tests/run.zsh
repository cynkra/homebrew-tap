#!/bin/zsh
# Unit tests for src/macos-baseline-check.sh: the system commands it calls are replaced by
# stubs in tests/stubs, which report a healthy device unless a FAKE_* variable says otherwise.
# Each case sets one condition and checks the status of one line of the report.
# Usage: zsh tests/run.zsh

root=${0:A:h:h}
script=$root/src/macos-baseline-check.sh
stubs=$root/tests/stubs
failed=0 passed=0

# expect <expected status> <check name> [VAR=value ...]
expect() {
  local want=$1 check=$2; shift 2
  local tmp=$(mktemp -d) a
  for a in "$@"; do  # TEST_VSCODE_EXT=<id>: installed VS Code extension; TEST_FILE=<path>:<line>: file in HOME
    [[ "$a" == TEST_VSCODE_EXT=* ]] && mkdir -p "$tmp/.vscode/extensions/${a#*=}-1.0.0"
    if [[ "$a" == TEST_AGENT=* ]]; then  # TEST_AGENT=<label>:<key>: launchd job in a test directory
      local spec=${a#*=}; mkdir -p "$tmp/agents"
      /usr/bin/plutil -create xml1 "$tmp/agents/${spec%%:*}.plist"
      /usr/bin/plutil -insert Label -string "${spec%%:*}" "$tmp/agents/${spec%%:*}.plist"
      case "${spec#*:}" in
        RunAtLoad) /usr/bin/plutil -insert RunAtLoad -bool true "$tmp/agents/${spec%%:*}.plist" ;;
        StartInterval) /usr/bin/plutil -insert StartInterval -integer 3600 "$tmp/agents/${spec%%:*}.plist" ;;
        OnDemand) /usr/bin/plutil -insert MachServices -dictionary "$tmp/agents/${spec%%:*}.plist" ;;
      esac
    fi
    if [[ "$a" == TEST_KNOWN=* ]]; then  # TEST_KNOWN=<label>: recorded by an earlier run
      mkdir -p "$tmp/Library/Application Support/cynkra-baseline-check"
      print -r -- "${a#*=}" >> "$tmp/Library/Application Support/cynkra-baseline-check/autostart_known"
    fi
    if [[ "$a" == TEST_FILE=* ]]; then
      local spec=${a#*=}; mkdir -p "$tmp/${spec%%:*:h}"; print -r -- "${spec#*:}" >> "$tmp/${spec%%:*}"
    fi
  done
  local out=$(cd $tmp && env -i HOME=$tmp PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
    SOCKETFILTERFW=$stubs/socketfilterfw FAKE_DEFAULTS_FMMEnabled=1 AUTOSTART_DIRS=$tmp/agents ONEPASSWORD_APP=$tmp "$@" /bin/zsh $script check --offline 2>&1)
  local line=$(print -r -- "$out" | grep -E "^(PASS|FAIL|WARN|INFO) +$check( |$)")
  rm -rf $tmp
  if [[ "$want" == NONE && -z "$line" ]] || [[ "$want" != NONE && "$line" == "$want "* ]]; then
    (( passed++ ))
  else
    (( failed++ ))
    print -r -- "not ok: $check should be $want with ${*:-defaults}; got: ${line:-<no line>}"
  fi
}

# healthy device
for c in FileVault Firewall Gatekeeper SIP "Auto security updates" XProtect "Screen lock" \
         "Automatic login" "Passwordless sudo" "Find My Mac" "macOS version" "Pending updates"; do
  expect PASS "$c"
done

# each control off or out of date
expect FAIL FileVault FAKE_FDESETUP="FileVault is Off."
expect FAIL FileVault FAKE_FDESETUP="Decryption in progress"
expect WARN FileVault FAKE_FDESETUP="Encryption in progress"
expect FAIL Firewall FAKE_FIREWALL=disabled
expect FAIL Gatekeeper FAKE_GATEKEEPER=disabled
expect FAIL SIP FAKE_SIP="System Integrity Protection status: disabled."
expect WARN SIP FAKE_SIP="System Integrity Protection status: enabled (Custom Configuration)."
expect FAIL "Auto security updates" FAKE_DEFAULTS_CriticalUpdateInstall=0
expect WARN "Auto update check" FAKE_DEFAULTS_AutomaticDownload=0
expect FAIL XProtect FAKE_XPROTECT_DATE=2020-01-01
expect FAIL "Screen lock" FAKE_DISPLAYSLEEP=20
expect FAIL "Automatic login" FAKE_DEFAULTS_autoLoginUser=someone
expect WARN "Passwordless sudo" FAKE_SUDO_EXIT=0
expect FAIL "Find My Mac" FAKE_DEFAULTS_FMMEnabled=0
expect FAIL "macOS version" FAKE_MACOS=24.6
expect FAIL "macOS version" FAKE_MACOS=15.7
expect PASS "macOS version" FAKE_MACOS=26.6
expect WARN "Pending updates" FAKE_UPDATES="macOS Tahoe|27.0.2"
expect PASS "Pending updates" FAKE_UPDATES="macOS 28|28.0"
expect INFO "Other updates" FAKE_UPDATES="Command Line Tools for Xcode|27.0"

# customer VM
expect INFO "Find My Mac" FAKE_VM=1
expect FAIL "VPN full tunnel" FAKE_VM=1
expect PASS "VPN full tunnel" FAKE_VM=1 FAKE_DEFAULT_IF=utun4
expect FAIL "Fleet agent" FAKE_VM=1
expect PASS "Fleet agent" FAKE_VM=1 FAKE_FLEET_RUNNING=1
expect PASS "AI extensions" FAKE_VM=1 TEST_VSCODE_EXT=ms-python.python
expect FAIL "AI extensions" FAKE_VM=1 TEST_VSCODE_EXT=github.copilot
expect FAIL "AI extensions" FAKE_VM=1 TEST_VSCODE_EXT=anthropic.claude-code

# plaintext credentials: names only, values from 1Password, other variables and paths are fine
expect PASS "Plaintext credentials"
expect WARN "Plaintext credentials" "TEST_FILE=.zprofile:export GH_TOKEN=ghp_abc123"
expect WARN "Plaintext credentials" "TEST_FILE=.zprofile_secrets:export ANTHROPIC_API_KEY=sk-ant-x"
expect WARN "Plaintext credentials" "TEST_FILE=.Renviron:GITHUB_PAT=ghp_abc123"
expect WARN "Plaintext credentials" "TEST_FILE=.git-credentials:https://user:pw@github.com"
expect WARN "Plaintext credentials" "TEST_FILE=.aws/credentials:aws_secret_access_key = abc"
expect PASS "Plaintext credentials" "TEST_FILE=.zprofile:export GH_TOKEN=\$(op read op://Private/gh/token)"
expect PASS "Plaintext credentials" "TEST_FILE=.zshrc:export GITHUB_TOKEN=\$GH_TOKEN"
expect PASS "Plaintext credentials" "TEST_FILE=.zshrc:export SSH_KEY_PATH=~/.ssh/id_ed25519"
expect PASS "Plaintext credentials" "TEST_FILE=.zshrc:export NPM_TOKEN="

# autostart: only jobs that start by themselves, warning for new ones after the first run
expect INFO "Autostart entries" TEST_AGENT=com.example.a:RunAtLoad
expect PASS "FileVault" TEST_AGENT=com.example.a:RunAtLoad
expect WARN "New autostart entries" TEST_AGENT=com.example.a:RunAtLoad TEST_AGENT=com.example.b:StartInterval TEST_KNOWN=com.example.a
expect NONE "New autostart entries" TEST_AGENT=com.example.a:RunAtLoad TEST_KNOWN=com.example.a
expect NONE "New autostart entries" TEST_AGENT=com.example.a:RunAtLoad TEST_AGENT=com.example.c:OnDemand TEST_KNOWN=com.example.a
expect NONE "New autostart entries" TEST_AGENT=com.example.a:RunAtLoad

expect PASS 1Password
expect FAIL 1Password ONEPASSWORD_APP=/nonexistent

# notifications in scheduled runs: <expected count after run 1> <after run 2> [VAR=value ...]
notify() {
  local want="$1 $2"; shift 2
  local tmp=$(mktemp -d) got="" i
  for i in 1 2; do
    (cd $tmp && env -i HOME=$tmp PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" NOTIFY_LOG=$tmp/notify.log \
      SOCKETFILTERFW=$stubs/socketfilterfw FAKE_DEFAULTS_FMMEnabled=1 AUTOSTART_DIRS=$tmp/agents ONEPASSWORD_APP=$tmp "$@" \
      /bin/zsh $script run --offline >/dev/null 2>&1)
    got+="$(cat $tmp/notify.log 2>/dev/null | grep -c .) "
  done
  if [[ "${got% }" == "$want" ]]; then (( passed++ )); else
    (( failed++ )); print -r -- "not ok: notifications with ${*:-defaults} should be $want; got: ${got% }"
    sed 's/^/  /' $tmp/notify.log
  fi
  rm -rf $tmp
}
notify 0 0                                         # healthy device: nothing
notify 1 1 FAKE_FDESETUP="FileVault is Off."       # failed check: alert, repeated after 20 h only
notify 1 1 FAKE_FDESETUP="Encryption in progress"  # warning: once, not again while unchanged

print "$passed passed, $failed failed"
(( failed == 0 ))
