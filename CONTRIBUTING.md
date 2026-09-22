# Contributing to sops-vault-kit

Thanks for your interest! This project has a deliberately tiny surface — a bash
CLI, a few single-purpose Python helpers, one HTML template, and one installer —
so contributions stay reviewable.

## Development setup

```sh
git clone https://github.com/skyzhao1223/sops-vault-kit && cd sops-vault-kit
# deps: sops, age, git, jq, python3   (macOS: brew install sops age)
bash tests/smoke.sh        # full lifecycle in a throwaway HOME (~40s, no network)
```

There is no build step: `bin/vault` runs as-is. CI (`.github/workflows/ci.yml`)
runs the smoke suite on **macOS and Ubuntu** with pinned sops/age release
binaries — if it passes locally it should pass there.

## Rules of the repo

1. **bash 3.2 compatibility is mandatory** (stock macOS `/bin/bash`): no
   associative arrays, no `${var,,}`, no `readarray`. Brace every variable
   immediately followed by a non-ASCII character (`"${VAR}（…）"` — bash 3.2
   mis-parses multibyte adjacency; see CHANGELOG 0.1.1).
2. **Fail closed**: anything encryption-related must degrade to
   "more encrypted", never "more plaintext".
3. **No plaintext on disk**: new commands that touch secret values must pipe
   them (stdin/`$(cat)`), never write plaintext files except the documented,
   600-perm, `vault clean`-covered views/exports.
4. **Never print a value** in confirmations, errors, or logs — fingerprints
   (`vault shape`) and lengths only.
5. **BSD + GNU**: `stat`, `sed`, `mktemp`, `ls` all differ. Branch on
   `uname -s` (see `cmd_doctor`) or use portable forms. The Ubuntu CI leg is
   the referee.
6. Python helpers: stdlib only, Python 3.9+ (system python on macOS).
7. Every behavior change lands with a smoke assertion in `tests/smoke.sh`.

## Where things live

```
bin/vault              the CLI (dispatch in main(); helpers top-of-file)
bin/vault-audit.py     allowlist/leak audit (reads ciphertext only)
bin/vault-shape.py     clipboard pre-flight (never prints content)
bin/vault-render.py    injects vault JSON into the HTML template
bin/vault-import.py    CSV → JSONL (Bitwarden/1Password/Chrome/generic)
bin/vault-kdbx.py      decrypted JSON → KeePassXML 2.x
bin/vault-view.html    browser card view template
templates/             seeded into a new vault by install.sh
tests/smoke.sh         the whole test suite (39+ assertions)
```

## Release process (maintainers)

1. Bump `VAULT_VERSION` in `bin/vault` **and** the version assertion in
   `tests/smoke.sh`.
2. Add a `CHANGELOG.md` entry (Added / Fixed / Changed).
3. `bash tests/smoke.sh` → green; push; wait for CI on both platforms.
4. `git tag -a vX.Y.Z && git push origin vX.Y.Z`; `gh release create`.

## Ideas welcome

Check the roadmap in [README.md](README.md#roadmap). High-value starters:
Linux clipboard wiring for the `shape` protocol docs (`wl-paste`/`xclip -o`
examples), more import formats (Firefox, Dashlane, Enpass), an English CLI
proofread, `vault doctor` checks for backup age.
