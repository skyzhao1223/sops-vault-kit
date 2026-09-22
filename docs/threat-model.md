# Threat Model

An honest statement of boundaries. **Knowing what is NOT defended is as
important as knowing what is.**（中文版：[threat-model.zh.md](threat-model.zh.md)）

## Assets

| Asset | Location | At-rest protection |
|---|---|---|
| Secret values (passwords / API keys / tokens / TOTP seeds) | `ENC[AES256_GCM,...]` inside `secrets.yaml` | sops/age, allowlist mode (unknown fields encrypted by default) |
| age private key | platform-default sops path (macOS `~/Library/Application Support/sops/age/keys.txt`, Linux `${XDG_CONFIG_HOME:-~/.config}/sops/age/keys.txt`) | file mode 600 |
| Metadata (entry names / URLs / usernames / notes) | plaintext fields in `secrets.yaml`, git history, backup bundles | **none** (public to vault readers by design) |

## Defended

| Threat | Defense |
|---|---|
| Vault file or backup stolen | values are AES-256-GCM ciphertext (per-value IV); bundles are safe on any cloud storage |
| Cloud provider reading secret values | values are encrypted client-side; the key never leaves the machine |
| **A new field silently stored in plaintext** (the classic blacklist failure) | allowlist fail-closed: everything outside `unencrypted_regex` is encrypted |
| Rule drift (`.sops.yaml` edited without re-encrypting) | `vault audit` parses the ciphertext file against the allowlist; `vault doctor` nags |
| Plaintext committed to git | `.gitignore` blocks exports/views/CSVs; `vault audit` scans; git history only ever holds ciphertext |
| Malicious web page driving the local API (with the companion DSH plugin) | plugin API enforces an Origin check; cross-origin → 403 |
| An AI agent reading every plaintext | structure/value split: `meta`/`ls` need no decryption; values only via single-field `get`; the shipped `AGENTS.md` binds agents working in the vault |
| Secrets leaking into shell history / process listings | `vault set … -` (stdin), `pbpaste |` pipes, `vault copy` never echoes |
| Vault corrupted or entries deleted by mistake | per-commit git rollback + `vault restore` (verifies decryptability, never overwrites) |

## NOT defended (stated plainly)

| Threat | Notes | Mitigation |
|---|---|---|
| **Malicious process running as your user** | it can read the vault and the key directly, and can `pbpaste` | the shared boundary of every local store: FileVault/LUKS + don't run untrusted software |
| **Losing the age key** | the vault becomes permanently undecryptable — no backdoor | `vault keycard`: print 2 cards, store in 2 physical locations (QR with qrencode to avoid transcription errors) |
| age key stolen | holder + any backup = full plaintext | guard the card like cash; on compromise: new key + `vault reencrypt` + rotate every secret |
| Shoulder-surfing / screen recording while viewing | after `vault html`/`cat`/panel reveal, plaintext is on screen and in memory | masked by default, reveal one field at a time, `vault clean` destroys on-disk views, close the panel before screen-sharing |
| Browser extensions (when using `vault html`) | extensions with page access can read the revealed DOM | fewer extensions; for sensitive ops use terminal `vault copy` (never rendered) |
| git history retains deleted values | after `vault rm`, old commits still decrypt (with the key) | treat exposed secrets as burned and rotate them; this is the price of rollback |
| The AI chat channel | a value you paste into chat lands in session logs / model context | use the clipboard protocol (`pbpaste | vault set … -`) or paste into the panel; see AGENTS.md rules 11–12 |
| Coercion | no local scheme resists "unlock it or else" | out of scope for software |

## Design trade-offs

- **Allowlist over blacklist**: a blacklist miss = silent plaintext; an allowlist
  miss = one more encrypted field. Asymmetric failure modes; we take the safe side.
- **Metadata stays readable**: structure-in-plaintext is what makes the vault
  greppable and AI-manageable. If even your system list is sensitive, narrow
  `unencrypted_regex` (down to the empty set) and run `vault reencrypt`.
- **No master password**: the age key file *is* the master key (600 perms, never
  typed into a prompt). A password scheme would either hand the password to
  scripts (worse) or require interactive entry on every call (no automation, no AI).
- **git over cloud sync**: diffable, per-change rollback, mergeable conflicts —
  `.kdbx`-style binary sync gives you none of these.
