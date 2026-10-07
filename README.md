# cynkra Homebrew tap

Tools cynkra employees install on their devices.

## cynkra-endpoint-check

Read-only check of the security baseline of a Mac (FileVault, firewall, updates, screen lock, sudo, SSH keys, Find My Mac, vulnerable developer packages and more), as required by cynkra's endpoint policy.
It changes nothing on the device and needs no admin rights.

Set up in three steps; all three are needed:

```sh
brew install cynkra/tap/cynkra-endpoint-check
cynkra-endpoint-check owner name@cynkra.com  # your cynkra address, e.g. jannes@cynkra.com; without it reports are anonymous
brew services start cynkra-endpoint-check    # runs at login and once a day, reports to the central overview
```

Show the result at any time:

```sh
cynkra-endpoint-check check                  # about 2 min with the vulnerability scan
cynkra-endpoint-check check --offline        # quick check without network, about 1 s
```

Updates arrive with `brew upgrade`.
Remove with `brew services stop cynkra-endpoint-check && brew uninstall cynkra-endpoint-check`.

What the check reports: the status of each check and the findings; no software list, files or browsing history leave the device. Plaintext credentials are reported by file and variable name only, never the value.

## Security of this tap

Whoever can change this repository can run code on every device that uses it.
Protection:

- `main` changes only by pull request, with signed commits; no force push, no deletion (repository ruleset).
- Release tags `v*` cannot be moved or deleted, and the formula pins a tagged release by checksum.
- The organisation owners have admin rights on all cynkra repositories; the rulesets apply to them too, and changing a ruleset is recorded in the organisation's audit log.
- A second person's approval for every pull request is not yet required while the check is under development; it will be turned on afterwards.

## Tests

`zsh tests/run.zsh` runs the checks against stubbed system commands (`tests/stubs`), one condition per case; CI runs them on every pull request together with a real run on a macOS runner and the formula audit.
