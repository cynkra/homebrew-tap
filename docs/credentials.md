# Credentials without plaintext files

`cynkra-endpoint-check` warns about **Plaintext credentials** when it finds tokens, passwords or API keys in your dotfiles or tool configs.
This guide shows how to move them into 1Password or the macOS keychain without losing the convenience.
Each section is short; jump to the one the warning points to.

## Why

FileVault protects your files only while the Mac is off; once you are logged in, every file is readable.
Any process you start (an npm `postinstall` script, an R or Python package, an AI agent) can read your dotfiles and inherits every exported environment variable.
The aim is that a secret reaches only the process that needs it, and only when it needs it.

## Setup

Once per Mac, so that the commands below work with Touch ID:

```sh
brew install 1password-cli
```

In the 1Password app: **Settings › Developer › Integrate with 1Password CLI**.
Then check that it works; this asks for Touch ID:

```sh
op vault list
```

References to secrets have the form `op://<vault>/<item>/<field>`, for example `op://Private/OpenAI/credential`.
Copy one with **Copy Secret Reference** in the item's field menu in the 1Password app.

## CLI plugins

For CLIs that 1Password supports (`gh`, `aws`, `glab`, `doctl`, `hcloud`, …, see `op plugin list`), a plugin is the easiest fix: the command works as before, and the token comes from 1Password with a Touch ID prompt.

```sh
op plugin init gh      # asks which 1Password item holds the token
echo 'source ~/.config/op/plugins.sh' >> ~/.zshrc
```

Then remove the token from wherever it was before (`.zshrc`, `~/.config/gh/hosts.yml`, …).

## Env vars

For API keys that tools read from environment variables (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, …).
Put **references** instead of values into a file; it holds no secret and is safe to keep in a dotfiles repo:

```sh
# ~/.config/secrets.env
OPENAI_API_KEY=op://Private/OpenAI/credential
ANTHROPIC_API_KEY=op://Private/Anthropic/credential
```

Run a command with the keys set only for that command:

```sh
op run --env-file ~/.config/secrets.env -- python train.py
```

Shorter with an alias in `~/.zshrc`:

```sh
alias withkeys='op run --env-file ~/.config/secrets.env --'
withkeys python train.py
```

Then delete the `export …=<value>` lines from `~/.zshrc` and friends.

Avoid `export OPENAI_API_KEY=$(op read op://…)` in `~/.zshrc`: it slows down every new shell and puts the key back into the environment of every process you start.

## Config files

For tools that read a token only from a file, keep a template with references and write the file when needed:

```sh
# ~/.npmrc.tpl
//registry.npmjs.org/:_authToken={{ op://Private/npm/token }}
```

```sh
op inject -i ~/.npmrc.tpl -o ~/.npmrc
```

The file then holds the token again, so prefer the env-var form where the tool supports it.
npm does: put `${NPM_TOKEN}` into `~/.npmrc` and set the variable with `op run`:

```sh
# ~/.npmrc
//registry.npmjs.org/:_authToken=${NPM_TOKEN}
```

```sh
NPM_TOKEN=op://Private/npm/token   # line in ~/.config/secrets.env
withkeys npm publish
```

The same template approach works for `~/.netrc`.

## git

git can keep HTTPS credentials in the macOS keychain instead of `~/.git-credentials`:

```sh
git config --global credential.helper osxkeychain
rm ~/.git-credentials
```

For GitHub, `gh auth setup-git` is an alternative: git then asks `gh` for the token.
The next `git push` asks for the credentials once and stores them in the keychain.

## gh

A token in `~/.config/gh/hosts.yml` means `gh` was logged in with `--insecure-storage`.
Log in again; by default `gh` stores the token in the keychain:

```sh
gh auth logout && gh auth login
```

Or use the [CLI plugin](#cli-plugins): `op plugin init gh`.

## AWS

For accounts with AWS IAM Identity Center (SSO), use short-lived credentials:

```sh
aws configure sso
aws sso login --profile <profile>
```

Otherwise keep the static key in 1Password with the [CLI plugin](#cli-plugins): `op plugin init aws`.
Then delete `aws_access_key_id` and `aws_secret_access_key` from `~/.aws/credentials`.

## Docker

Let Docker keep registry logins in the keychain.
In `~/.docker/config.json`:

```json
{ "credsStore": "osxkeychain" }
```

`osxkeychain` needs `brew install docker-credential-helper`; Docker Desktop uses `"desktop"` instead.
Then log in again (`docker login …`); the `auths` entries no longer contain the token.

## R

`GITHUB_PAT` in `~/.Renviron`: remove the line and store the token where git keeps it ([git](#git) first), then in R:

```r
gitcreds::gitcreds_set()
```

usethis, gh, remotes and pak find the token there.
For other API keys used from R, start R or RStudio through `op run` ([Env vars](#env-vars)), e.g. `withkeys R`.

## Python

For uploads with twine, use the keyring instead of `password` in `~/.pypirc`:

```sh
keyring set https://upload.pypi.org/legacy/ __token__
```

Or set `TWINE_PASSWORD` with `op run` ([Env vars](#env-vars)).

## SSH

Use the 1Password SSH agent: the keys stay in 1Password, and each use asks for Touch ID.
Turn it on in **Settings › Developer › Use the SSH agent**, then in `~/.ssh/config`:

```
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

Import your existing key into 1Password and delete the file, or at least give it a passphrase:

```sh
ssh-keygen -p -f ~/.ssh/id_ed25519
```

## Rotate

A key that has ever been in a git repository, a backup or a synced folder (iCloud, Dropbox, …) must be rotated: create a new one at the provider and revoke the old one.
Moving it into 1Password does not undo the earlier exposure.

## Dotfiles repo

If you keep your dotfiles in git, add a pre-commit hook that blocks secrets:

```sh
brew install gitleaks
printf '#!/bin/sh\nexec gitleaks git --pre-commit --staged\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Older gitleaks versions use `gitleaks protect --staged`.

## False positive

The check reports variables whose names look like secrets (`*_TOKEN`, `*_KEY`, …), so a non-secret such as `MAPBOX_PUBLIC_KEY` can show up.
Add the variable name, or a whole file as `~/...`, as a line to the ignore list:

```sh
mkdir -p ~/Library/Application\ Support/cynkra-endpoint-check
echo MAPBOX_PUBLIC_KEY >> ~/Library/Application\ Support/cynkra-endpoint-check/plaintext-ignore
```

Lines starting with `#` are comments.
The list stays on your Mac.
