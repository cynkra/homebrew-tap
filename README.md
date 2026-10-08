# cynkra Homebrew tap

Tools cynkra employees install on their devices.

## cynkra-endpoint-check

Read-only check of the security baseline of a Mac (FileVault, firewall, updates, screen lock, sudo, SSH keys, Find My Mac, vulnerable developer packages and more), as required by cynkra's endpoint policy.
It changes nothing on the device and needs no admin rights.

Set up in four steps; all four are needed:

```sh
brew trust --formula cynkra/tap/cynkra-endpoint-check  # Homebrew 7 loads third-party formulae only once trusted
brew install cynkra/tap/cynkra-endpoint-check
cynkra-endpoint-check owner name@cynkra.com  # your cynkra address, e.g. jannes@cynkra.com; without it reports are anonymous
brew services start cynkra-endpoint-check    # runs at login and once a day, reports to the central overview
```

Show the result at any time:

```sh
cynkra-endpoint-check check                  # about 2 min with the vulnerability scan
cynkra-endpoint-check check --offline        # quick check without network, about 1 s
cynkra-endpoint-check check --json           # full report as JSON, e.g. > report.json
```

`check` only prints; it writes no report files.

Updates arrive with `brew upgrade`.
Remove with `brew services stop cynkra-endpoint-check && brew uninstall cynkra-endpoint-check`.

What leaves the device: only devices registered with an `@cynkra.com` owner send a short status (status per check, counts, script version) to cynkra's overview once a day; anyone else using this tap sends nothing. No software list, files or browsing history leave the device, and plaintext credentials are reported as a count only (file and variable names stay in the local report).

## Security of this tap

Whoever can change this repository can run code on every device that uses it.
Protection:

- `main` changes only by pull request, with signed commits; no force push, no deletion (repository ruleset).
- Release tags `v*` cannot be moved or deleted, and the formula pins a tagged release by checksum.
- The organisation owners have admin rights on all cynkra repositories; the rulesets apply to them too, and changing a ruleset is recorded in the organisation's audit log.
- A second person's approval for every pull request is not yet required while the check is under development; it will be turned on afterwards.

## Tests

`zsh tests/run.zsh` runs the checks against stubbed system commands (`tests/stubs`), one condition per case; CI runs them on every pull request together with a real run on a macOS runner and the formula audit.
