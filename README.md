# sops-vault-kit

English | [中文](README.zh.md)

[![CI](https://github.com/skyzhao1223/sops-vault-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/skyzhao1223/sops-vault-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A local-first, **AI-manageable** encrypted credential vault: one `install.sh` gives you a
[sops](https://github.com/getsops/sops) + [age](https://age-encryption.org) + git vault with a 30-command
CLI, a browser card view, TOTP, security audit, offline key backup cards, and a built-in `AGENTS.md`
that teaches coding agents how to operate it **without ever seeing your plaintext secrets**.

No server. No cloud account. No subscription. Everything lives in one encrypted file on your disk.

```sh
git clone https://github.com/skyzhao1223/sops-vault-kit && cd sops-vault-kit
./install.sh          # → ~/Vault, age key generated, git initialized, `vault` on PATH
vault keycard         # print your offline key backup card (do this immediately)
```

## Screenshot

`vault html` — the zero-dependency browser view (grouped cards, masked secrets,
click-to-copy, live TOTP):

![vault html browser view](docs/screenshot.png)

## Why another vault?

Password managers (KeePassXC, Bitwarden, 1Password) store **binary blobs for humans**: no diff, no
audit trail, and giving an AI agent access means handing over the master password. Ops tools
(HashiCorp Vault, Infisical) are **servers**: heavy, and overkill for personal credentials.

This kit sits in between, built for how people actually work with coding agents in 2026:

- **Structure is plaintext, values are ciphertext.** Allowlist encryption: every field is encrypted
  unless explicitly public (`url`, `appid`, `env`, `owner`, `note`…). An agent (or you, via `grep`)
  can see the whole catalog — which systems exist, who owns them, how to reach them — while secrets
  stay sealed. New field names are encrypted **by default**: the failure mode is over-encryption,
  never a silent plaintext leak.
- **One plaintext at a time.** `vault get`/`reveal` decrypts exactly one field on demand.
- **git is the audit trail.** Every change is a commit; `git log -p` shows which metadata changed
  when; rollback any single change.
- **AI operating rules ship with the vault.** `AGENTS.md` lands inside your vault directory: 13 rules
  binding any coding agent that works there (never echo values, prefer structure-only commands, the
  4-step clipboard protocol, never touch the age private key…). The human/AI boundary is documented
  where the agent will actually read it.

## What you get

| Area | Commands |
| --- | --- |
| Browse | `vault ls` · `peek` (no key needed) · `meta` (JSON structure, no decryption) · `search` · `find-secret` (reverse lookup: which entries use this secret) |
| Reveal | `vault get` · `copy` (clipboard, never printed) · `show` · `cat` / `view` / `html` (browser card UI with click-to-copy) |
| Write | `vault new` (auto-generated 24-char password) · `set` (accepts `-` for **stdin**) · `rm` · `edit` (VS Code via `sops edit`) |
| TOTP | `vault totp` (RFC 6238, seeds stored encrypted) |
| Safety | `audit` (allowlist/leak checks) · `shape` (**clipboard pre-flight**: length/charset/prefix/sha256 fingerprint, never the content) · `doctor` |
| Lifecycle | `save` (git commit) · `log` · `backup` (single-file bundle, keeps 5) · `restore` (never overwrites, verifies decryptability) · `keycard` (printable offline key card, QR if `qrencode` present) · `reencrypt` · `clean` |
| Migrate | `vault import dump.csv` — Bitwarden / 1Password / Chrome / generic CSV, auto-detected; existing entries skipped, secrets piped via stdin (never in process args) |

### The clipboard protocol (why `shape` exists)

Clipboard contents are messy — you might have copied a whole `appkey: xxx` line, or something with
stray whitespace. The kit's answer, also encoded as a rule for agents:

```sh
pbpaste | vault shape                        # 1. pre-flight: shape + fingerprint only, never content
pbpaste | vault set "services/stripe" appkey -   # 2. value flows clipboard → pipe → encrypted file
vault get "services/stripe" appkey | tr -d '\n' | vault shape
                                             # 3. fingerprint matches step 1 → verified
```

The secret never appears in shell arguments, shell history, process listings, or agent transcripts.

## Security model

| Asset | Protection |
| --- | --- |
| Secret values | sops AES-256-GCM, per-value; allowlist mode (fail-closed) |
| Vault file | 600 perms; lives wherever you put it; encrypted bundle backups safe for any cloud |
| age private key | 600 perms, platform-default sops location, **never leaves your machine**; `vault keycard` makes an offline paper backup (the only irrecoverable single point — do it) |
| Agents / AI | structure only (`meta`/`ls`); values only through the clipboard protocol or explicit user action; rules enforced socially via the shipped `AGENTS.md` |
| Deletion | git history retains encrypted values (by design — that's your rollback); rotate secrets you consider burned |

Honest limits: local processes running as your user can read the vault (the pre-existing threat
model of any local store — FileVault is your friend); `vault html` writes a 600-perm plaintext page
to `/tmp` until `vault clean`.

## Docs

- [Threat model](docs/threat-model.md) ([中文](docs/threat-model.zh.md)) — what is defended, what is not, and why
- [Migration guide](docs/migration.md) — import from Bitwarden / 1Password / Chrome
- [Contributing](CONTRIBUTING.md) — repo rules (bash 3.2, fail-closed, BSD+GNU), release process

## Requirements & platforms

- `sops`, `age`, `git`, `jq`, `python3` (macOS: `brew install sops age`)
- **macOS first** (native `pbcopy`/`pbpaste`, iCloud backup default). **Linux is fully supported**
  by CI: `vault copy` falls back to `wl-copy`/`xclip`/`xsel`; the clipboard protocol examples use
  `pbpaste` — substitute `wl-paste` or `xclip -o` there. Windows via WSL.
- Shell completions: `source completions/vault.bash` (bash) or put `completions/vault.zsh` on your
  zsh `fpath` as `_vault`.

## Companion

**[dsh-plugin-sops-vault](https://github.com/skyzhao1223/dsh-plugin-sops-vault)** — sidebar panel
for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness): the same vault as a GUI,
with the model deliberately given *zero* tools.

## License

MIT © skyzhao1223
