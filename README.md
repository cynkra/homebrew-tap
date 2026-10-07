# cynkra Homebrew tap

Tools cynkra employees install on their devices.

## cynkra-baseline

Read-only check of the security baseline of a Mac (FileVault, firewall, updates, screen lock, sudo, SSH keys, Find My Mac, vulnerable developer packages and more), as required by cynkra's endpoint policy.
It changes nothing on the device and needs no admin rights.

```sh
brew install cynkra/tap/cynkra-baseline
cynkra-baseline owner name@cynkra.com        # e.g. jannes@cynkra.com
brew services start cynkra-baseline    # runs at login and once a day
cynkra-baseline check                  # show the result now
```

Updates arrive with `brew upgrade`.
Remove with `brew services stop cynkra-baseline && brew uninstall cynkra-baseline`.

What the check reports: the status of each check and the findings; no software list, files or browsing history leave the device.

## Security of this tap

Whoever can write to this repository can run code on every device that uses it.
Therefore: write access for cynkra's CISO and Co-CISO only, changes by reviewed pull request with signed commits, and the formula points to a tagged release with checksum.
