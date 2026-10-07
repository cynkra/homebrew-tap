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
  for a in "$@"; do  # TEST_VSCODE_EXT=<id>: an installed VS Code extension
    [[ "$a" == TEST_VSCODE_EXT=* ]] && mkdir -p "$tmp/.vscode/extensions/${a#*=}-1.0.0"
  done
  local out=$(cd $tmp && env -i HOME=$tmp PATH="$stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
    SOCKETFILTERFW=$stubs/socketfilterfw FAKE_DEFAULTS_FMMEnabled=1 "$@" /bin/zsh $script check --offline 2>&1)
  local line=$(print -r -- "$out" | grep -E "^(PASS|FAIL|WARN|INFO) +$check( |$)")
  rm -rf $tmp
  if [[ "$line" == "$want "* ]]; then
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

print "$passed passed, $failed failed"
(( failed == 0 ))
