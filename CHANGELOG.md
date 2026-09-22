# Changelog

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
