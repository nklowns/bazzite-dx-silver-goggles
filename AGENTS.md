# Bazzite-DX-Silver-Goggles — AI Agent Guide

Single source of truth for AI agents in this repository (`CLAUDE.md` and `GEMINI.md` are symlinks to this file).

Personal customization layer targeting **Dell G15 5520** (Intel i7-12700H, NVIDIA RTX 3060), KDE/NVIDIA, Fedora 44. Builds a declarative, immutable OCI container image with the [BlueBuild](https://blue-build.org) framework.

- **Base image**: `ghcr.io/ublue-os/bazzite-nvidia` — DX tooling is applied by this repo's own `recipes/dx.yml`, following `bazzite-dx` patterns.
- **Entry point**: `recipes/recipe.yml`. Everything flows from there.
- Use the `[Silver Goggles]` prefix for agent-created issues or messages.

## 🛠️ Commands

```bash
just check          # Validate: Just syntax + bluebuild validate + ShellCheck
just build          # Compile image via BlueBuild (requires podman/docker)
just rebase-local   # Apply built image to running system (reboot required)
just rollback-local # Undo last rebase (reboot required)
just rebase-official # Return to upstream Bazzite image (reboot required)

just lint           # ShellCheck all scripts
just format         # shfmt all scripts
just clean          # Remove build artifacts

just build-awcc                    # Build stable AWCC RPM (version matched to base image)
just build-awcc /path/to/AWCC      # Build dev AWCC RPM from local source
just hot-swap-awcc /path/to/AWCC   # Build + apply AWCC live (no reboot)
just uninstall-awcc                # Revert hot-swap (live, rpm-ostree apply-live --reset)

just status         # Image config, local images, tooling versions
just g15-status     # Dell G15 hardware health check
just act            # Simulate GitHub Actions locally (requires --privileged for buildah)
```

Requirements: `just`, `podman` (or `docker`), `bluebuild` CLI. Install the CLI if missing:
```bash
podman run --pull always --rm ghcr.io/blue-build/cli:latest-installer | bash
```

## 🏗️ Architecture

### Modular Hybrid Build Model

```
recipe.yml              ← Entry point (declarative orchestration)
├── files module        ← Overlays files/system/ onto /
├── dx.yml              ← EXTENSIONS: Cockpit, Docker, Libvirt, eBPF tools, fonts
│   └── local modules   ← Encapsulated logic: dx-flavor (branding/policy), dx-udev
├── silver-goggles.yml  ← HARDWARE: Dell G15 kargs, AWCC RPM (rpm-ostree), thermald mask
├── casting.yml         ← CASTING: AirPlay/FCast/scrcpy receivers + iOS bridges (opt-in via ujust)
├── initramfs module
├── dx-verify           ← System integrity auditor (custom module in modules/)
├── os-release          ← OCI metadata
└── signing             ← cosign
```

`recipes/build-recipe.yml` is **generated** by `scripts/generate-recipe.sh` at CI time — never edit it manually.

### Expert Monolith Layers

1. **CORE** — Fedora/uBlue base modules (`bazzite-nvidia` upstream).
2. **EXTENSIONS** — extra packages and repos (`dx.yml`).
3. **TUNING** — kernel and performance optimization (native `kargs` module).
4. **HARDWARE** — Dell G15 customization (AWCC, dGPU, services).
5. **IDENTITY** — visual identity and branding.

### Key Directories

| Path | Purpose |
|------|---------|
| `recipes/` | Build declarations (`recipe.yml`, `dx.yml`, `silver-goggles.yml`, `casting.yml`, generated `build-recipe.yml`) |
| `files/system/` | Static files overlaid onto `/` at build time via the `files` module |
| `files/system/usr/lib/tmpfiles.d/` | Atomic symlinks (L+ pattern) — Flatpak overrides and symlinks |
| `files/system/usr/lib/environment.d/` | System-wide environment variables (CHROME_EXTRA_FLAGS, etc.) |
| `files/system/etc/modules-load.d/` | Kernel module loading (acpi_call) |
| `files/justfiles/` | Host-side `ujust` recipes (66-silver-goggles.just, 67-casting.just, 95-bazzite-dx.just), injected via the `justfiles` module |
| `files/system/usr/share/ublue-os/casting/` | Staged casting assets (user units + `uxplayrc.tmpl`), wired into `$HOME` by `ujust` on request |
| `files/rpm-ostree/` | Pre-compiled RPMs committed to git (awcc-dev.rpm) |
| `modules/` | Custom BlueBuild modules (dx-flavor, dx-udev, dx-verify) |
| `build_files/` | AWCC RPM specs (stable: `awcc.spec`; dev fork: `awcc.dev.spec`) |
| `just/` | Modular Just recipe files (build, dev, maint, status) |
| `scripts/` | Utility/generation scripts (`generate-recipe.sh`) |
| `disk_config/` | Bootc Image Builder (BIB) configs for QCOW2/ISO output |
| `image-versions.yaml` | Pins the base image digest (updated by Renovate PRs; consumed by `generate-recipe.sh`) |

**Justfile split**: root `Justfile` = development tasks (build, rebase, lint, AWCC); `files/justfiles/66-silver-goggles.just` = modular host-side `ujust` recipes.

## 🛡️ Atomic State Policy (MANDATORY)

Immutable/atomic host — imperative system mutations on the live host are forbidden. Everything is baked into the image at build time.

1. **Static files** go under `files/system/` (the `files` module overlays them onto `/`). Never mutate `/etc` directly.
2. **Flatpak overrides**: NEVER use `flatpak override` or `sudo cp` in scripts. Use `tmpfiles.d` with the **`L+` (symlink with overwrite)** pattern linking `/usr/share/flatpak/overrides/` → `/var/lib/flatpak/overrides/`.
3. **Global env vars** go in `files/system/usr/lib/environment.d/*.conf`. Never `export` in profile scripts.
4. **Service enable/mask** is declared via the `systemd` module in `recipe.yml` OR generated by local modules at build time (e.g., `dx-flavor` presets). Reference: `thermald.service` masked (AWCC compat), `systemd-udev-settle.service` masked (VFIO/IOMMU stability). Do not add preset files manually.
5. **Kernel args** go via the `kargs` module (plus local-module tuning if needed). Never use imperative boot scripts.
6. **Image transformation**: build-time scripts (local modules) are the authorized escape hatch for branding, policy enforcement, and config that static overlays can't express.

### Scripting Conventions

- Shell scripts must pass `shellcheck` (`just lint`); format with `shfmt` (`just format`).
- Custom BlueBuild modules follow the pattern in `modules/` and should include an integrity check where possible (see `dx-verify`).

## ⚙️ AWCC RPM Workflow

`files/rpm-ostree/awcc-dev.rpm` is committed to the repo and installed at image build time via the `rpm-ostree` module.

| Command | Spec used | Source |
|---|---|---|
| `just build-awcc` | `awcc.spec` (default) | Downloads tarball from `tr1xem/AWCC`, version synced with base image |
| `AWCC_SPEC=awcc.dev.spec just build-awcc <src>` | `awcc.dev.spec` | Local source from `nklowns/AWCC` fork (pinned commit) |

After rebuilding, commit the RPM: `git add -f files/rpm-ostree/awcc-dev.rpm && git commit`.
Rapid iteration: `just hot-swap-awcc <path>` (live apply, no reboot); revert with `just uninstall-awcc`.
Full workflow: [`docs/AWCC-BUILD.md`](docs/AWCC-BUILD.md).

## 📱 Casting & Mobile Bridge (`recipes/casting.yml`)

Receives screen/media from iOS and Android. Split by discovery mechanism, and the split is
architectural — **not** a configuration gap:

| Path | Tool | Discovery | Tailnet |
|---|---|---|---|
| iOS/macOS screen + audio | `uxplay` (`ujust airplay-setup`) | mDNS | ❌ never |
| iOS audio | `shairport-sync` (system unit, disabled) | mDNS | ❌ never |
| media casting | FCast flatpaks (`ujust fcast-setup`) | mDNS **or manual IP** | ✅ TCP 46899 |
| Android screen + audio | `scrcpy` (`ujust android-mirror <host>`) | ADB over TCP | ✅ |
| input/clipboard/files | KDE Connect (`ujust kdeconnect-tailnet-add <host>`) | broadcast **or manual IP** | ✅ Android · ❌ iOS |
| iOS files/apps | `libimobiledevice-utils`, `ifuse`, `ideviceinstaller` | USB (usbmuxd) | ⚠️ USB only |

**Do not try to make AirPlay or Miracast work over Tailscale.** Tailscale carries no
multicast/broadcast, and the iOS AirPlay picker offers no manual-address entry. The tailnet-capable
tools above are tailnet-capable precisely because a hostname can be typed by hand.

**KDE Connect over the tailnet is Android-only in practice.** A custom device is only an extra
unicast destination for the UDP identity packet; the phone must then dial TCP 1716 back. Measured
here with both phones on the same tailnet, off Wi-Fi, same probe: the Android answered on 1716 and
established a link at tailnet addresses (`100.108.150.113:1716 <- 100.115.193.18:60774`), while the
iPhone returned connection *refused* — packets arriving, nothing listening — with `tailscale ping`
answering fine through the carrier. Android holds the socket via a persistent foreground service;
iOS does not. For iOS file transfer use `tailscale file cp` (Taildrop), which needs no listener on
either side.

Two traps when verifying any of this:
- *refused* is a phone-side problem (nothing listening); *timeout* is a routing/firewall one. They
  look alike from the desk and point at opposite halves of the stack.
- A **stale link masks a working tailnet link.** kdeconnectd keeps reporting a device reachable at
  its previous LAN address through a socket whose peer is gone — TCP notices nothing without
  traffic or keepalives, so `ss` still shows `ESTAB`. `--refresh` does not fix it; only restarting
  `app-org.kde.kdeconnect.daemon@autostart.service` drops the links and forces re-discovery, which
  is why `kdeconnect-tailnet-add` does exactly that. Also note `kdeconnect-cli` prints "via LAN"
  even for a tailnet link, because that is the backend's name, not the path.

**FCast over the tailnet is verified end-to-end.** With the Android on cellular (routed through the
carrier, not the local network — confirmed by a distinct IPv6 prefix and a via-gateway route), TCP
46899 at its tailnet address returned the FCast protocol greeting `{"version":3}` plus keepalive
pings, byte-identical to the on-LAN result.

**scrcpy over the tailnet works, and the port is the catch.** Verified against an SM-A307GT
(Android 11): `adb pair` and `adb connect` both succeeded against its tailnet address, `adb shell`
returned real output, the socket was `100.108.150.113:34988 -> 100.115.193.18:38124`, and
`scrcpy --tcpip=<tailnet-ip>:<port>` — the exact form `android-mirror` uses — mirrored the screen.
Two things that cost time if unknown:
- Android 11+ Wireless debugging listens on a **random port that rotates on every toggle** — 5555
  belongs to the older `adb tcpip 5555` flow and gives "Connection refused" otherwise. `adb mdns
  services` finds the real port on the LAN but never across the tailnet, so a remote device's port
  must be read off its screen. Running `adb tcpip 5555` after connecting pins a stable port that
  survives toggling (not a reboot).
- Pairing and connecting use **different random ports**, and the pairing one exists only while its
  dialog is open. "Connection refused" means nothing is listening; "failed to connect" means the
  TCP connection worked and the TLS handshake did not, i.e. this host is not paired.

Conventions this layer follows:
- The whole mobile surface is consolidated here, not split across recipes: `usbmuxd`,
  `libimobiledevice-utils`, `ifuse` and `ideviceinstaller` were moved out of `dx.yml`'s
  "Host Integration & Peripheral Bridges" section (a pointer comment remains there).
- Both user units follow the graphical-session pattern proven by
  `files/system/usr/share/ublue-os/user-setup.hooks.d/45-sunshine-graphical-session-fix.sh`:
  `After=graphical-session.target plasma-kwin_wayland.service`, `Requisite=` (never
  `Wants=`/`Requires=`, which would spawn a standalone compositor at boot under user
  lingering and steal the DRM device from the real login session),
  `WantedBy=graphical-session.target` (never `default.target`), and an `ExecStartPre`
  that polls for the Wayland socket instead of trusting unit-active — on NVIDIA/prime
  `plasma-kwin_wayland.service` reports active 20-30s before the compositor serves
  clients. A socket test is used rather than `busctl get-property`, which would
  resurrect the portal and kwin as a side effect of asking.
- Nothing is enabled at boot. `casting.yml` declares no `systemd` module; assets are staged
  read-only in `/usr/share/ublue-os/casting/` and `67-casting.just` installs them into
  `~/.config/systemd/user` on request — same pattern as `remote-ide-setup`.
- UxPlay ships `pin` + `reg` in `uxplayrc.tmpl`: no receiver accepts an anonymous client.
- **`vs xvimagesink`, not `waylandsink`** — the single hardest-won line in `uxplayrc.tmpl`.
  Measured against one iPhone on KDE Wayland / RTX 3060: `waylandsink` renders correct geometry
  with the content shredded into displaced horizontal bands, and `GST_DEBUG=2` names the cause —
  `<videodmabufpool0> no caps in config` (`gstvideopool.c:226`), a dmabuf pool negotiated without
  caps, hence a wrong stride. `glimagesink` opens a window and renders nothing. `xvimagesink`
  (XWayland, system memory, no dmabuf negotiation) is correct. **The decoder is not involved:** the
  corruption was byte-for-byte the same under `nvh264dec` and under software `avdec`, and the
  journal carried no decoder error in either case — which is also why "comment out `vd nvh264dec`"
  is not a valid isolation step here (decodebin re-selects nvcodec on its own; only the `avdec`
  option forces software). Re-test `waylandsink` after GStreamer updates.
- **Three UxPlay traps, all found only at runtime, all fixed in-tree:**
  - `read_config_file()` splits every non-`#` line into argv entries. It *does* honour `'` and `"`
    as item delimiters, so any value with a space must be quoted — unquoted `n Silver Goggles`
    becomes three entries and uxplay exits with `unknown option Goggles`. The template also carries
    `nh`, without which the advertised name is `Silver Goggles@bazzite.drake-ayu.ts.net`.
  - `ExecStart` wraps uxplay in `stdbuf -oL -eL`, and that is load-bearing. uxplay only calls
    `setbuf(stdout, NULL)` under `_WIN32`, so on Linux glibc fully buffers stdout whenever it is not
    a tty — always, under systemd. The pairing pin goes to stdout, so unbuffered it reaches the
    journal only when the process exits: the observed symptom was `*** ERROR: Client Authentication
    Failure (client proof not validated)` on the phone side, because the pin the user was supposed
    to type had never been displayed. Verified end-to-end after the fix: pin printed live, iPhone
    (`iPhone14,5`, `AirPlay/950.7.1`) paired and registered, `raop_rtp_mirror starting mirroring`.
- `casting-status` captures `systemctl is-active` with `|| true`, never `|| echo <fallback>`:
  `is-active` already prints the state on stdout *and* exits non-zero for anything but active, so a
  fallback prints both strings on one line.
- `files/system/usr/lib/firewalld/services/{uxplay,fcast}.xml` are definitions only, bound to no
  zone. The default `FedoraWorkstation` zone already opens `1025-65535/tcp+udp` and `tailscale0`
  sits in `trusted`, so `ujust casting-firewall` is a no-op there and says so.
- `adb` comes from the `android-platform-tools` **cask** in `cli.Brewfile` (Homebrew 6.x installs
  casks on Linux). The Fedora `android-tools` RPM stays commented out in `dx.yml` on purpose —
  enabling it would put a second `adb` in `PATH`.
- `nqptp` is absent from Fedora, so `shairport-sync` is AirPlay **1** only. UxPlay's audio-only
  mode (`-async`) covers AirPlay 2 ALAC.

## 🔀 Testing Forks & Branch Overrides

To test a fork of the base image:
1. Edit `base-image` in `recipes/recipe.yml` (e.g., `ghcr.io/nklowns/bazzite-dx-nvidia:latest`).
2. `just build`.
3. Revert after testing.

## 🚀 CI/CD & Deployment

`.github/workflows/build.yml` on push to main:
1. **check** job — `just check` (lint + validate).
2. **bluebuild** job — builds, signs (cosign), and pushes to `ghcr.io/nklowns/bazzite-dx-silver-goggles`.

`.github/workflows/build-disk.yml` — manual workflow for QCOW2/ISO disk images via BIB.

Rebase a system to the published image:
```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest
```

### Local Build

```bash
just build 2>&1 | tee output/build.log
```

### Local GHA Testing (`act`)

```bash
just act   # Simulates GitHub Actions locally (requires --privileged for buildah)
```

### Self-Hosted Runner (Distrobox)

Keep the host clean — run the runner in a container:
1. `distrobox-create --name gha-runner --image fedora:44 --init`
2. `distrobox-enter gha-runner`
3. Install deps (`git`, `podman`, `curl`) and configure the runner manually.
4. `sudo ./svc.sh install/start` to run as a service inside the container.

## 🏁 Safety & Rollback

- **Undo system rebase**: `just rollback-local` (reboot required).
- **Return to official image**: `just rebase-official` (reboot required).
- **Undo AWCC hot-swap**: `just uninstall-awcc` (live transient removal via `rpm-ostree apply-live --reset`).

## 🧠 System State Identification

`rpm-ostree status` deployment markers:
- **● Signed** — production state (rebased from `ghcr.io/nklowns/bazzite-dx-silver-goggles`).
- **● Unverified** — local testing state (rebased from `localhost/`).
- **LocalPackages** — active hot-swap on top of the base image.

## 📚 BlueBuild Reference (Context7 MCP)

- `blue-build.org/reference` — technical reference for build logic.
- `blue-build.org/learn` — tutorials and educational material.
- `blue-build.org/how-to` — practical guides for specific build tasks.
- `/blue-build/modules` — reusable module catalog.
- `/ublue-os/image-template` — foundation of this repository's structure.
- `/ublue-os/bazzite-dx` — upstream DX patterns reference.

For grep-level lookups of upstream implementations, prefer the local clones in `../ublue-os/` and `../blue-build/` (see workspace `AGENTS.md`).
