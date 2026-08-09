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

Run with no argument and the script first shows a single-choice menu —
Export or Import, never both: picking one automatically clears the other.

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
    [✓] Verify signing keys      exported + already installed — needs network
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

In import mode the last checkbox enables verification. Fingerprints are
compared against the official reference — either the one pinned in the script
(Claude Desktop) or the key published at the vendor's URL.

Two sets of keys are checked:

1. **Keys about to be installed**, taken from `data/`.
2. **Keys already present on this system**, for every catalogued repository
   configured in `/etc/apt` that is *not* being reinstalled by this run. This
   turns the option into a small audit of what the machine already trusts.

Outcomes:

| Result | What happens |
|---|---|
| Match | continues |
| Mismatch on a key **to be installed** | run **stops immediately**, nothing is written to `/etc/apt` |
| Mismatch on a key **already installed** | reported in full, then you are asked whether to continue (defaults to no) |
| Cannot be checked (no network, no public reference, key file missing, `gpg` absent) | reported, then you are asked whether to continue (defaults to yes) |

Both fingerprints are printed on a mismatch so you can see exactly what
differs. Verification runs *before* anything is installed, so a bad key never
reaches the system.

**Check-only run** — leave every repository unticked and keep *Verify signing
keys* ticked: the script audits the keys already installed and exits without
touching anything. Useful on a machine that is already fully set up. It exits
non-zero if any installed key fails the check.

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
