# repo-sync

One script to copy APT repository definitions and their GPG signing keys from
one machine to another — typically from MX Linux to a fresh Debian install.

It replaces the old collection of `esporta-*.sh` / `registra-*.sh` scripts:
everything is now a single file with a checkbox interface.

## Supported repositories

| Repository | Official key source used for verification |
|---|---|
| MX Linux | — (no stable public reference) |
| Google Chrome | `https://dl.google.com/linux/linux_signing_key.pub` |
| TeamViewer | `https://linux.teamviewer.com/pubkey/currentkey.asc` |
| Visual Studio Code | `https://packages.microsoft.com/keys/microsoft.asc` |
| VSCodium | `https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg` |
| Claude Desktop | `https://downloads.claude.ai/claude-desktop/key.asc` — fingerprint pinned in the script |

## Usage

```
./repo-sync.sh export     # on the source machine
./repo-sync.sh import     # on the target machine (asks for root)
./repo-sync.sh            # asks which mode to run
```

1. **Source machine** — run `./repo-sync.sh export`. The script scans
   `/etc/apt/sources.list` and `/etc/apt/sources.list.d/`, lists the
   repositories it actually finds, and saves the selected ones into `data/`.
2. **Copy the whole `repo-sync` folder** (script + `data/`) to the target
   machine — USB stick, `scp`, shared folder.
3. **Target machine** — run `./repo-sync.sh import`. It re-creates the
   repository files and the keys, then runs `apt update`.

## The checkbox interface

```
  ❯ [✓] Google Chrome
    [ ] TeamViewer               already installed
    [✓] Claude Desktop
    [✓] Verify keys against official sources   recommended — needs network
```

| Key | Action |
|---|---|
| `↑` `↓` (or `k` `j`) | move |
| `Space` | tick / untick |
| `A` | select all / none |
| `Enter` | confirm |
| `Q` or `Esc` | cancel |

**What is ticked by default**

- *Export*: every repository whose key is **not yet** in the `data/` folder.
- *Import*: every repository **not yet** present on this system.

So a plain `Enter` does the sensible thing: only what is missing.

Anything already present is left unticked, and if you tick it anyway the
script asks for confirmation **one repository at a time**, showing the exact
files that would be overwritten, before touching anything.

## Key verification

In import mode the last checkbox enables verification. For each repository the
script compares the fingerprint of the exported key with the official one —
either the fingerprint pinned in the script (Claude Desktop) or the key
downloaded from the vendor's published URL.

- **Match** → installation continues.
- **Mismatch** → the run **stops immediately** and nothing is written to
  `/etc/apt`. Both fingerprints are printed so you can see what differs.
- **Cannot be checked** (no network, no public reference, `gpg` missing) →
  you are asked whether to continue anyway.

Verification happens *before* any file is installed, so a bad key never
reaches the system.

## Where the keys are restored

The export writes a `manifest` file recording the original absolute path of
every key. On import each key goes back to exactly that path, so the
`signed-by=` option in the repository line keeps pointing at a valid file.
This matters for repositories like Claude Desktop, whose key lives in
`/usr/share/keyrings/claude-desktop-archive-keyring.asc`.

## Layout after an export

```
repo-sync/
├── repo-sync.sh
├── README.md
└── data/
    ├── chrome/
    │   ├── repo.list
    │   ├── manifest
    │   └── keys/google-chrome.gpg
    └── claude/
        ├── repo.list
        ├── manifest
        └── keys/claude-desktop-archive-keyring.asc
```

## Adding a repository

Add one line to the `CATALOGUE` array at the top of the script:

```
"id;Display name;apt match regex;key filename glob;official key URL;pinned fingerprint"
```

Fields are separated by `;` so the regex may use `|`. The last two fields are
optional — leave them empty and that repository will simply be reported as
"cannot be checked" during verification.

## Notes

- Export runs as a normal user and calls `sudo` only to read `/etc/apt`;
  the `data/` folder is left owned by the real user so it can be copied
  freely.
- Import re-runs itself with `sudo` if needed, and writes everything as
  `root:root` with mode `644` (`755` for key directories).
- `gpg` is used to read fingerprints, `curl` or `wget` to fetch official keys.
  Without them the script still works, only verification is unavailable.
- Colours are disabled automatically when the output is not a terminal, or
  when `NO_COLOR` is set.
