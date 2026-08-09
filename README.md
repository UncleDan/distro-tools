# distro-tools

Standalone scripts that share the same interface: coloured output, checkbox
lists driven by the arrow keys, and the same `YY.MM` version number. None of
them depends on the others — copy just the one you need.

| Script | What it does |
|---|---|
| `repo-sync.sh` | copies APT repositories and their signing keys between machines |
| `rename-distro.sh` | changes the name a Linux install reports about itself |
| `clean-cache.sh` | clears caches and regenerable data, for one user or all of them |
| `install-scripts.sh` | symlinks the others into `/usr/local/bin` so they run from anywhere |

---

# repo-sync.sh

Copies APT repository definitions and their GPG signing keys from one machine
to another — typically from MX Linux to a fresh Debian install.

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
   repositories it actually finds, and saves the selected ones into `data/repo/`.
2. **Copy the whole folder** (script + `data/`) to the target
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

- *Export*: every repository whose key is **not yet** in `data/repo/`.
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

1. **Keys about to be installed**, taken from `data/repo/`.
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

Everything both scripts write lives under a single `data/` folder:

```
distro-tools/
├── repo-sync.sh
├── rename-distro.sh
├── clean-cache.sh
├── README.md
└── data/
    ├── repo/                       # repo-sync.sh
    │   ├── chrome/
    │   │   ├── repo.list
    │   │   ├── manifest
    │   │   └── keys/google-chrome.gpg
    │   └── claude/
    │       ├── repo.list
    │       ├── manifest
    │       └── keys/claude-desktop-archive-keyring.asc
    └── rename/                     # rename-distro.sh
        └── 20260809-104911/
            ├── etc/{issue,issue.net,lsb-release}
            └── usr/lib/os-release
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

---

# rename-distro.sh

Changes the name the system reports about itself, across `/etc/os-release`,
`/etc/lsb-release`, `/etc/issue`, `/etc/issue.net` and `/etc/motd`.
Backups go to `data/rename/<timestamp>/`.

## Usage

```
./rename-distro.sh show                      # print the current values
./rename-distro.sh apply "Name" [Ver] [ID]   # back up, then rewrite
./rename-distro.sh restore                   # put a previous backup back
./rename-distro.sh                           # asks what to do
```

`apply` and `restore` re-run themselves with `sudo`. `apply` with no name asks
for name, version and ID one at a time; the ID defaults to a slug of the name
(`"My Distro"` → `my-distro`).

The old positional form still works: `./rename-distro.sh "My Distro" 1.0`.

## What happens on apply

1. A checkbox list of the five files, pre-ticked for the ones that exist.
2. A preview of every key that will be written, and a confirmation.
3. A backup into `data/rename/<timestamp>/`, keeping the original paths.
4. The rewrite, followed by the resulting values.

`os-release` and `lsb-release` are edited key by key: only `NAME`,
`PRETTY_NAME`, `ID`, `VERSION`, `VERSION_ID` (and the `DISTRIB_*` equivalents)
change, everything else in the file is left alone, and a key that is missing is
appended rather than silently dropped. `VERSION` and `VERSION_ID` are only
touched when you pass a version.

`issue`, `issue.net` and `motd` have no key structure, so they are **replaced**
— a custom banner in them is lost, which is what the backup is for.

## Restore

`./rename-distro.sh restore` lists the saved sessions newest first, shows which
file goes back where, and asks before overwriting.

```
  ❯ (•) 20260809-102013            4 file(s)
```

## Notes

- If `/etc/os-release` is a symlink (commonly into `/usr/lib/`), the script
  follows it and edits — and backs up — the real file.
- File ownership and permissions are preserved: the content is rewritten in
  place rather than the file being replaced.
- Some desktop environments and login managers cache the distribution name;
  a reboot, or at least a new session, may be needed before it shows up
  everywhere.
- This only changes what the system *says*. Package sources, branding
  artwork and installed distro packages are untouched.

---

# clean-cache.sh

Removes caches, thumbnails, crash dumps, browser session leftovers and other
regenerable files for Thunderbird, Firefox, LibreWolf, Chrome, Chromium,
pCloud and Konqueror/KDE.

## Usage

```
./clean-cache.sh                    # show the help
./clean-cache.sh -c                 # current user, non-interactive
./clean-cache.sh -a                 # pick the users, then the applications
./clean-cache.sh -c -i              # current user, but ask first
./clean-cache.sh --dry-run          # report only, delete nothing
./clean-cache.sh firefox chrome     # current user, only these (implies -c)
./clean-cache.sh --tb-mail none     # keep Thunderbird mail stores
./clean-cache.sh --list             # print the application ids
```

Called with no argument at all it prints the help and exits — cleaning always
takes an explicit request.

## Scope

`-c` cleans the current user's home non-interactively: it still reports
everything it removes, but asks nothing — no lists, no confirmation. Every
application found is processed and no root privileges are needed. This is the
cron-friendly mode. Naming applications on the command line implies it.
Add `-i` if you want the lists and the confirmation in this mode too.

`-a` / `--all` re-runs with `sudo` and opens two lists: first the user
accounts (real accounts with a home directory, plus `root`), then the
applications. Both are pre-ticked for what is actually there — a user with
nothing to clean is listed but unticked, and an application is offered only
when it is present in **at least one** of the selected users:

```
  ❯ [✓] alice                        3 app(s) — /home/alice
    [✓] bob                          1 app(s) — /home/bob
    [ ] svcuser                      nothing to clean

    [✓] Thunderbird                  found in 1 of 2 users
    [✓] Chromium                     found in 1 of 2 users
```

Naming applications on the command line skips the second list. Sizes are
reported per user and as a total.

## What is deleted

| Application | Removed |
|---|---|
| Firefox / LibreWolf | profile `cache`, `cache2`, `thumbnails`, `startupCache`, `offlinecache`, `storage/temporary`, `storage/cache`, Sync logs, session backups, `*.bak` `*.tmp` `*.corrupt`, crash minidumps, plus mesa/IPC caches for Firefox |
| Thunderbird | profile caches, `global-messages-db.sqlite`, `*.msf` indexes, crash reports, temporary files, and the local mail stores (see below) |
| Chrome / Chromium | `~/.cache` profile caches, `GPUCache`, `ShaderCache`, `Code Cache`, `DawnCache`, `GrShaderCache`, `Crash Reports`, `*.tmp` `*.log` `*.dmp` |
| pCloud | cache and thumbnails, in both the `~/.pcloud` and `~/.local/share/pcloud` layouts |
| Konqueror / KDE | Konqueror and KIO caches, KDE thumbnails (current and legacy), Plasma theme/SVG/icon caches, `*.kcache`, drkonqi crash reports |

`storage/default` is left alone (persistent extension data), and Konqueror
cookies and history are left alone as well.

## Profiles

For Firefox, LibreWolf and Thunderbird **every** profile is cleaned, not just
the ones that happen to sit inside the application folder. Profiles are
collected from:

- every subdirectory of the application folder, symlinks included;
- every `Path=` entry in `profiles.ini`, relative or absolute;
- the native, Flatpak (`~/.var/app/…`) and Snap (`~/snap/…`) locations.

An absolute `Path=` pointing outside the owning user's home is refused and
reported — `profiles.ini` is user-writable, and in `-a` mode this runs as
root.

Chrome and Chromium profiles (`Default`, `Profile 1`, …) were already covered
by a recursive scan; their Flatpak and Snap prefixes are now included too.

Every profile is announced as it is processed, and one that has nothing left
to clear says so rather than staying silent:

```
  Thunderbird
    ▪ profile t1.default
    − t1.default/cache2 — 19.53 KB
    ▪ profile t3.empty
      nothing to remove
```

The same applies to an application with nothing to do — it reports "nothing to
remove" instead of printing an empty section.

**Thunderbird mail stores.** `Mail/` and `ImapMail/` can be handled three
ways, set with `--tb-mail`:

| Mode | Effect |
|---|---|
| `full` | the folders are emptied completely, message filters included |
| `filters` | everything goes except `msgFilterRules.dat` — **the default** |
| `none` | left untouched (`--no-tb-mail` is the same thing) |

IMAP accounts resync from the server, but **POP3 mail and Local Folders are
gone for good** in the first two modes.

In `-a` mode the choice is asked once, as a single-choice list preset to
"delete except message filters", and applies to every selected user:

```
  ❯ ( ) Delete the whole folders       message filters included
    (•) Delete except message filters  keeps msgFilterRules.dat
    ( ) Do not delete them             Mail/ and ImapMail/ untouched
```

Passing `--tb-mail` on the command line skips that question. In `-c` mode the
default (`filters`) applies without asking.

## Safety

- An application is skipped when one of its processes is running **for that
  user** (`pgrep -x -u`), so cleaning alice does not fail because bob has
  Firefox open.
- `-a` and `-i` ask for confirmation before deleting. `-c` on its own does
  not — that is the point of it — so try `--dry-run` first, which never
  deletes and only reports the sizes.
- Only deletions happen — no file is created in anyone's home, so ownership
  is never disturbed.

---

# install-scripts.sh

Puts the other scripts on your `PATH` by symlinking them into
`/usr/local/bin`, dropping the `.sh` extension:

```
/usr/local/bin/clean-cache  ->  <this folder>/clean-cache.sh
```

After that `clean-cache -c`, `repo-sync export` and `rename-distro show` work
from any directory.

## Usage

```
./install-scripts.sh              # ask what to do
./install-scripts.sh install      # link them
./install-scripts.sh remove       # remove the links
./install-scripts.sh status       # show what is linked
./install-scripts.sh install --dir ~/bin
```

`install` and `remove` re-run themselves with `sudo`; `status` does not need
root. `--dir` puts the links somewhere else — `~/.local/bin` or `~/bin` if you
would rather not touch a system directory.

## Behaviour

The list offers every `.sh` in the folder, itself included, pre-ticked for
those not linked yet:

```
  ❯ [✓] clean-cache
    [ ] repo-sync                already linked
    [ ] rename-distro            name taken by another link
```

A name that is already taken is left unticked; tick it anyway and you are
asked, one at a time, whether to replace it — showing where the existing link
points, or warning that it is a regular file rather than a link.

`remove` only ever deletes symlinks that point back into this folder, so an
unrelated `/usr/local/bin/repo-sync` belonging to something else is left
alone. The scripts themselves are never touched.

## Notes

- These are links, not copies: **the folder has to stay where it is**. Move it
  and the links dangle — run `remove` first, or `install` again afterwards.
- Each script resolves its own symlink before looking for its `data/` folder,
  so `repo-sync` called from `/tmp` still finds `data/repo/` next to the real
  script.
- If the link directory is not on your `PATH`, the script says so instead of
  leaving you wondering why the short name does not work.
