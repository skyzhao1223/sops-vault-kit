# Changelog

## 0.2.0 — 2026-09-22

### Added

- `vault kdbx [file]` — export as KeePassXML 2.x for KeePassXC / KeePassium
  (iPhone): groups from name prefixes, TOTP seeds as `otpauth://` (codes work
  right after import), non-allowlist fields flagged ProtectInMemory. Pure
  stdlib, zero new dependencies.
- `docs/threat-model.zh.md` — what the kit defends, what it does not, and why.
- README screenshot (real headless-Chrome capture of `vault html` on a demo vault).
- Smoke suite covers kdbx export (parseable XML, entry count, TOTP present): 30 assertions.

## 0.1.1 — 2026-09-22

### Fixed

- `sops set` cannot navigate an empty `systems: {}` map on Linux (works on macOS):
  `vault new` / `vault set` now fall back to a whole-file round trip
  (decrypt → jq merge → re-encrypt → verify → atomic replace) when path
  navigation fails. Caught by the Ubuntu CI leg.
- bash 3.2 (stock macOS `/bin/bash`) parsed `$KEY_FILE（` as one multibyte variable
  name → `unbound variable` on macOS CI runners. All variables immediately followed
  by fullwidth characters are now braced.
- Smoke suite now surfaces failing command output and an env banner (platform,
  bash and sops versions) instead of swallowing them.
- **The actual Ubuntu failure**: `install.sh` honors `XDG_CONFIG_HOME` when placing
  the age key, but `vault` hard-coded `$HOME/.config` — on any machine where
  `XDG_CONFIG_HOME` is set (GitHub runners do), every key-requiring command died with
  a misleading macOS-path error. `vault` now resolves `${XDG_CONFIG_HOME:-$HOME/.config}`
  exactly like sops and the installer. Smoke suite now sets a deviated
  `XDG_CONFIG_HOME` to regression-cover this.
- `install.sh` no longer swallows a failing post-install `doctor` (it previously
  printed a warning and exited 0, masking the key-resolution bug above).
- `check_key` error message lists every location actually searched.

## 0.1.0 — 2026-09-22

First public release.

### Added

- `install.sh` one-command bootstrap: dependency check, age key generation at the
  platform-default sops location, allowlist `.sops.yaml`, encrypted empty vault,
  git init + first commit, `~/.local/bin/vault` symlink, post-install `doctor`
- `vault` CLI (32 commands): browse (`ls`/`peek`/`meta`/`search`/`find-secret`),
  reveal (`get`/`copy`/`show`/`cat`/`view`/`html`), write (`new`/`set`/`rm`/`edit`),
  TOTP (RFC 6238), safety (`audit`/`shape`/`doctor`), lifecycle
  (`save`/`log`/`backup`/`restore`/`keycard`/`reencrypt`/`clean`), `import`, `version`
- Allowlist (fail-closed) encryption template: every field encrypted except the
  explicitly public names in `unencrypted_regex` — unknown fields are encrypted by default
- `AGENTS.md` shipped into every generated vault: 13 operating rules for coding
  agents (structure-only access, four-step clipboard protocol, zero plaintext echo)
- Browser card view (`vault html`): grouped entries, masked-by-default values,
  click-to-copy, live TOTP
- `vault import`: CSV migration from Bitwarden / 1Password / Chrome / generic
  exports (auto format detection, existing entries skipped, secrets piped via stdin)
- `vault shape`: clipboard pre-flight check (length/charset/known prefix/sha256
  fingerprint — never the content) enabling the verify-after-write round trip
- `vault keycard`: printable offline key backup card, with QR when `qrencode` is installed
- Smoke test suite (27 assertions, isolated HOME) + GitHub Actions CI on macOS & Ubuntu
- Shell completions: `completions/vault.bash`, `completions/vault.zsh`

### Fixed (pre-release hardening, caught by the smoke suite)

- `git bundle verify` missing `-C` — `backup`/`restore` failed when run outside the vault directory
- `vault doctor` key-permission check used BSD-only `stat -f` — now falls back to GNU `stat -c` (Linux)
- doctor "latest backup" probe aborted under `set -o pipefail` when no backups existed yet
- `find-secret` only searched password/token/totp — now searches every string field
- `vault rm` on a missing entry leaked a raw sops error — now fails with a clear message
- `vault copy` was macOS-only — now falls back to `wl-copy`/`xclip`/`xsel` on Linux
