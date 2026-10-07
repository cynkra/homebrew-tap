# cynkra Homebrew tap

Tools cynkra employees install on their devices.

## cynkra-baseline

Read-only check of the security baseline of a Mac (FileVault, firewall, updates, screen lock, sudo, SSH keys, Find My Mac, vulnerable developer packages and more), as required by cynkra's endpoint policy.
It changes nothing on the device and needs no admin rights.

```sh
brew install cynkra/tap/cynkra-baseline
cynkra-baseline owner name@cynkra.com        # e.g. jannes@cynkra.com
brew services start cynkra-baseline    # runs at login and once a day
cynkra-baseline check                  # show the result now (about 2 min with the vulnerability scan)
cynkra-baseline check --offline        # quick check without network, about 1 s
```

Updates arrive with `brew upgrade`.
Remove with `brew services stop cynkra-baseline && brew uninstall cynkra-baseline`.

What the check reports: the status of each check and the findings; no software list, files or browsing history leave the device.

## Security of this tap

Whoever can change this repository can run code on every device that uses it.
Protection:

- `main` changes only by pull request, with signed commits; no force push, no deletion (repository ruleset).
- Release tags `v*` cannot be moved or deleted, and the formula pins a tagged release by checksum.
- The organisation owners have admin rights on all cynkra repositories; the rulesets apply to them too, and changing a ruleset is recorded in the organisation's audit log.
- A second person's approval for every pull request is not yet required while the check is under development; it will be turned on afterwards.

## Tests

`zsh tests/run.zsh` runs the checks against stubbed system commands (`tests/stubs`), one condition per case; CI runs them on every pull request together with a real run on a macOS runner and the formula audit.
