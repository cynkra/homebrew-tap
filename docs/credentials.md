# Credentials without plaintext files

`cynkra-endpoint-check` warns about **Plaintext credentials** when it finds tokens, passwords or API keys in your dotfiles or tool configs.
This guide explains the rule behind the warning and shows, per tool, how to follow it without losing convenience.
The first part is the overview; the sections after it are the details the warnings link to.

## Principle

**A secret should reach only the code that needs it, when it needs it.**

The realistic risk is accidental exposure: backups, synced folders, git repositories, screen sharing, tools and AI agents that read your files, an exported variable that every process inherits, RStudio saving copies of the session environment.
Following the principle removes that risk completely.
Malicious code running as you is a different problem; that is the job of the other endpoint controls and of tokens that can do little.

FileVault does not help here: it protects your files only while the Mac is off.

## Where secrets live

In a password manager (1Password, Bitwarden) or the macOS keychain.
Never in dotfiles, `.Renviron`, `.env` files, scripts or repositories.
Secrets you no longer use are deleted and revoked at the provider.

## How to use them

It depends on who needs the secret:

| Who needs it | How | Details |
|---|---|---|
| A CLI with its own login (`gh`, `aws`, `gcloud`, `docker`, git over HTTPS) | Log in normally; the CLI keeps the token in the keychain | [git](#git), [gh](#gh), [AWS](#aws), [Docker](#docker), [CLI plugins](#cli-plugins) |
| Your own code (R, shell, Python) | Fetch it at the point of use, so only the function that needs it sees it | [Point of use](#point-of-use), [R](#r) |
| A third-party tool that only reads an environment variable | Set it for that one command | [Env vars](#env-vars) |
| A tool that only reads a config file | Keep a reference in the file, or write the file when needed | [Config files](#config-files) |
| GitHub from R | `gitcreds` and `gh`, no `GITHUB_PAT` | [R](#r) |

Avoid the workarounds that look safe but are not: `export X=$(op read …)` in `.zshrc` and `Sys.setenv(X = …)` in `.Rprofile` keep the secret off the disk, but put it into every shell or R session and everything started from it.

## High-value secrets

Ordinary secrets (an API key for a hobby project, a read-only token) are fine in the keychain.
High-value ones (password manager master passwords, production access, write access to customer repositories) need a confirmation for every use:

- in 1Password, `op` asks for Touch ID;
- in the keychain, create the entry with `-T ""`: then every read asks for confirmation.
  Entries created with `security` without it can be read by any process running as you, without a prompt.

```sh
security add-generic-password -a "$USER" -s prod-db -T "" -w   # asks for the value
```

Where the provider allows it, also give the token narrow scopes and an expiry date.

## Rotate

A secret that has ever been in a git repository, a backup, a synced folder (iCloud, Dropbox, …) or a screen share must be replaced: create a new one at the provider and revoke the old one right away.
Moving it into 1Password does not undo the earlier exposure.

## What the check does

`cynkra-endpoint-check` reminds you of these rules in the common places: shell startup files and the files they source, `.Renviron`, `.Rprofile`, and the credential files of git, AWS, npm, PyPI, gh and Docker.
It catches honest mistakes; it can't guarantee the rules.
Project `.env` files, scripts and tool caches are not checked; keeping secrets out of them is up to you.

# Details

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

## Point of use

In code you control, read the secret where it is used instead of from the environment.
From 1Password:

```sh
op read op://Private/OpenAI/credential
```

From the keychain (store once, then read):

```sh
security add-generic-password -a "$USER" -s openai -w     # asks for the value
security find-generic-password -a "$USER" -s openai -w
```

In a shell function, so the key exists only while the command runs:

```sh
deploy() { DEPLOY_TOKEN=$(op read op://Private/deploy/token) ./deploy.sh "$@"; }
```

For R, see [R](#r).

## Env vars

For third-party tools that only read an environment variable (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, …), set it for that one command.
Put **references** instead of values into a file; it holds no secret and is safe to keep in a dotfiles repo:

```sh
# ~/.config/secrets.env
OPENAI_API_KEY=op://Private/OpenAI/credential
ANTHROPIC_API_KEY=op://Private/Anthropic/credential
```

```sh
op run --env-file ~/.config/secrets.env -- some-tool
alias withkeys='op run --env-file ~/.config/secrets.env --'   # in ~/.zshrc
withkeys some-tool
```

For GitHub tokens: `GH_TOKEN=$(gh auth token) some-tool`.

Then delete the `export …=<value>` lines from `~/.zshrc` and friends, and don't replace them with `export X=$(op read …)`: that slows down every new shell and puts the key back into the environment of every process you start.

`op run` does not reach apps started from the Dock or with `open -a` (RStudio, Positron, VS Code): macOS starts them without your shell's environment.
For code in those apps, fetch at the [point of use](#point-of-use).

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
npm does: put `${NPM_TOKEN}` into `~/.npmrc` and set the variable for the command:

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

**GitHub:** remove `GITHUB_PAT` from `~/.Renviron` and store the token where git keeps it ([git](#git) first), once:

```r
gitcreds::gitcreds_set()
```

pak, remotes, usethis and gh find it there on their own; nothing needs `GITHUB_PAT` any more.
In your own code, ask for it where you need it:

```r
token <- gh::gh_token()
httr2::request("https://api.github.com/user") |>
  httr2::req_auth_bearer_token(gh::gh_token()) |>
  httr2::req_perform()
```

Don't put `Sys.setenv(GITHUB_PAT = gh::gh_token())` into `.Rprofile`: it keeps the token off the disk, but puts it back into every R session and everything it starts.
The safe route needs no setup at all.

**Other API keys:** store them in the keychain with the keyring package and read them at the point of use:

```r
keyring::key_set("openai")              # once, asks for the value
api_key <- keyring::key_get("openai")
```

Or from 1Password: `system2("op", c("read", "op://Private/OpenAI/credential"), stdout = TRUE)`.
Both work in RStudio and Positron started from the Dock, where `op run` doesn't reach.

## Python

For uploads with twine, use the keyring instead of `password` in `~/.pypirc`:

```sh
keyring set https://upload.pypi.org/legacy/ __token__
```

Or set `TWINE_PASSWORD` for the command ([Env vars](#env-vars)).
In your own code, `keyring.get_password("openai", "<user>")` reads from the macOS keychain at the point of use.

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

## Dotfiles repo

If you keep your dotfiles in git, add a pre-commit hook that blocks secrets:

```sh
brew install gitleaks
printf '#!/bin/sh\nexec gitleaks git --pre-commit --staged\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Older gitleaks versions use `gitleaks protect --staged`.

## False positive

The check reports variables whose names look like secrets (`*_TOKEN`, `*_KEY`, …), so a non-secret such as `MAPBOX_PUBLIC_KEY` or an OAuth client ID can show up.
Add the variable name, or a whole file as `~/...`, as a line to the ignore list:

```sh
mkdir -p ~/Library/Application\ Support/cynkra-endpoint-check
echo MAPBOX_PUBLIC_KEY >> ~/Library/Application\ Support/cynkra-endpoint-check/plaintext-ignore
```

Lines starting with `#` are comments.
The list stays on your Mac.
