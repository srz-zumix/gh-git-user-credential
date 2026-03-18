# gh-git-user-credential

A [gh](https://cli.github.com/) extension that selects the appropriate `gh auth git-credential` call based on `git config user.name`.

Combine it with [gitconfig `includeIf`](https://git-scm.com/docs/git-config#_conditional_includes) to switch `user.name` / `user.email` per directory, and **multiple GitHub accounts are handled automatically**.

## Installation

```sh
gh extension install srz-zumix/gh-git-user-credential
```

## Prerequisites

- [GitHub CLI (`gh`)](https://cli.github.com/) installed
- Each GitHub account you want to use logged in via `gh auth login`

```sh
# Example: log in with two accounts
gh auth login -h github.com -u personal-user
gh auth login -h github.com -u work-user
```

## Setup

### 1. `~/.gitconfig` — configure the credential helper

```gitconfig
[credential "https://github.com"]
    helper = !gh git-user-credential
```

For GitHub Enterprise, add an entry for your host as well.

```gitconfig
[credential "https://github.example.com"]
    helper = !gh git-user-credential
```

### 2. Switch users with `includeIf`

Use `includeIf` to apply a different `user.name` per directory.

```gitconfig
# ~/.gitconfig

[user]
    name  = personal-user
    email = personal@example.com

# Use the work account under ~/work/
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig-work
```

```gitconfig
# ~/.gitconfig-work

[user]
    name  = work-user
    email = work@company.com
```

With this configuration, repositories under `~/work/` will have `user.name = work-user`, and `gh-git-user-credential` will call `gh auth token -u work-user` to authenticate.

## How it works

1. Read the current username from `git config user.name`.
2. Retrieve a token via `gh auth token -h github.com -u <user.name>` and export it as `GH_TOKEN`.
3. For non-github.com hosts, retrieve a token via `gh auth token -u <user.name>` and export it as `GH_ENTERPRISE_TOKEN`.
4. Delegate to `gh auth git-credential` with the original arguments.

## Verification

```sh
# Check that the credential helper works correctly
echo "protocol=https
host=github.com" | git credential fill
```

## License

[MIT](LICENSE)
