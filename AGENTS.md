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

## 🔌 Reserved Port Range (DX Services)

This is a developer workstation — arbitrary projects spin up arbitrary dev servers (`8080`, `3000`, `5173`, `8081`, `11434`, etc). Always-on system/DX services exposed over the tailnet must therefore never squat a common dev port. Convention: **`61300-61399`**, plus the bare tailnet domain (`443`/root) reserved for nothing (kept free so a project can `tailscale serve` its own thing there without a fight).

| Service | Local port | Tailnet |
| :--- | :--- | :--- |
| code-server | `61337` | `https://<tailscale-fqdn>:61337` (`ujust code-up`) |
| NOMAD Command Center | `61380` | `https://<tailscale-fqdn>:61380` (`ujust remote-nomad-setup` / `ujust nomad-up`) |
| NOMAD dozzle (log viewer) | `61381` | not exposed over tailnet by default |
| NOMAD Ollama (GPU inference) | `61382` | never — no authentication, no rate limiting. The Command Center reaches it over the container network (`http://ollama:11434`), not this port (`ujust ollama-up`) |
| AI Studio Visual (ComfyUI) | `61384` | `https://<tailscale-fqdn>:61384` (`ujust visual-up` / `ujust remote-visual-setup`) — ComfyUI, CyberRealistic V9, SD 1.5, LTX-Video & LivePortrait Neural Facial Animation |
| AI Studio Audio (Speaches) | `61386` | `https://<tailscale-fqdn>:61386` (`ujust audio-up` / `ujust remote-audio-setup`) — OpenAI-compatible Speech API (Piper TTS, ChatTTS & Faster-Whisper STT, 100% CPU / 0 MB VRAM) |
| cockpit | `61390` | `https://<tailscale-fqdn>:61390` (`ujust cockpit-up`) — moved off `9090`, which is Prometheus' default and which `cockpit.socket` binds on every boot whether Cockpit is used or not (`LISTEN *:9090` measured on an idle host). Socket-activated, so the move costs nothing at boot |
| KasmVNC WebRTC Desktop | `61391` | `https://<tailscale-fqdn>:61391` (`ujust remote-kasmvnc-setup`) — Browser-native HTML5 desktop with bidirectional browser clipboard sync |
| Apache Guacamole | `61392` | `https://<tailscale-fqdn>:61392` (`ujust guacamole-up`) — HTML5 client for RDP/VNC backends. *Note: KDE Plasma 6 Wayland RDP (KRDP) / VNC (KRFB) require active screen session portals; Sunshine (`61395`) is preferred for remote host streaming.* |
| Sunshine Web UI | `61395` | `https://<tailscale-fqdn>:61395` (`ujust sunshine-up` / `ujust remote-sunshine-setup`) — proxies `https+insecure://127.0.0.1:47990` with real TLS via `tailscale serve`. Sunshine Web UI restricted to loopback (`origin_web_ui_allowed = pc`) |

**Publish on `127.0.0.1`, not `0.0.0.0`, and do not rely on firewalld to make up the difference.** `tailscale0` lives in firewalld's `trusted` zone, which accepts everything, so anything bound to all interfaces is reachable by every device on the tailnet with no `tailscale serve` and no firewall rule. This was measured, not assumed — with the NOMAD stack briefly published on `0.0.0.0`, `http://<host>:61381/` returned the Dozzle log viewer and `http://<host>:61382/api/tags` answered from Ollama, both unauthenticated. The convention is therefore: services bind loopback, and `ujust remote-*-setup` publishes them through `tailscale serve`, which also gets them real TLS instead of plain HTTP. code-server (`bind-addr: 127.0.0.1:61337`) and Cockpit (`ListenStream=127.0.0.1:61390`) already work this way. Across a tailnet, actual access control is Tailscale ACLs — firewalld only ever governed the LAN.

Adding a new always-on DX service: pick the next free port in `61300-61399`, wire it the same way (compose/env + firewalld service XML + `ujust` echoes/URLs), and add a row here.

## 🥾 Boot Impact Policy (this is a gaming + dev box, not a server)

Bazzite serves two conflicting jobs on the same hardware — play and develop — and every service enabled at boot is CPU/RAM/VRAM the game or the build isn't getting, plus slower cold start. The only things this layer's own recipes enable by default are:

- **`tailscale` + `sunshine`** — the actual remote-access path into the system, and the one thing that stays on. Note the mechanism, because it was described wrongly here before: neither is enabled *by the image*. `tailscaled.service` ships `preset: disabled` and is turned on by upstream's own `ujust tailscale enable` (`80-bazzite.just`); Sunshine likewise. They show up in `ujust boot-audit` as "enabled outside the image" and that is correct and intended — the audit reports facts, it does not label them violations.
- Socket-activated units already established pre-NOMAD (`cockpit.socket`, `docker.socket`, `podman.socket`, `virtqemud.socket` and siblings in `recipes/dx.yml`) — near-zero idle cost since the daemon only spawns on first connection. Not something this change revisits.

Everything else — **NOMAD (Command Center, mysql, redis, dozzle, Ollama, and any Supply Depot app), code-server, VS Code Remote Tunnels, casting receivers (uxplay/FCast/scrcpy)** — is opt-in: `nomad.yml`/`casting.yml` carry no `systemd` module at all, so their units ship inert until a `ujust ...-up`/`...-setup` call activates them. **Do not add a `systemd: enabled:` block to `nomad.yml` or `casting.yml`** — that would turn an on-demand feature into permanent background load (mysql/redis daemons, a container socket held open, VRAM pressure from Ollama) fighting the same RTX 3060 a game session needs. If a future service seems to want boot-enablement, that's a signal to re-check this policy with the user first, not a default to reach for.

### `enable` is not opt-in on this image — lingering is on

This paragraph used to end at "…does `systemctl --user enable --now`", and that sentence quietly contradicted itself. Lingering is enabled for the desktop user:

```
$ loginctl show-user "$USER" -p Linger
Linger=yes
$ ls /var/lib/systemd/linger/
<username>
```

Without lingering, an enabled *user* unit starts at **login**. With it, the unit starts at **boot** with no login at all, and keeps running after logout. So `systemctl --user enable` is not "remember my preference for this session" — it is the same permanent-background-load commitment the policy above forbids, arriving by a different door. It is the user-scope equivalent of a container's `restart: unless-stopped`.

**Rule: `ujust ...-up` recipes use `systemctl --user start`, never `enable`.** The `[Install]` section stays in the units so someone can deliberately opt into always-on, but nothing in this repo should enable a user unit on the user's behalf.

**This is not hypothetical, and the host is already drifting.** Measured — every one of these currently starts at boot, not at login:

```
uxplay                    enabled     ide-tunnel@code           enabled
code-server               enabled     ide-tunnel@code-insiders  enabled
tailscale-systray         enabled     agy-warmup.timer          enabled
```

Two VS Code tunnel servers at ~10 s each plus a 23 s warmup, all before the desktop is usable — and `uxplay`/`code-server` are precisely the services this section calls "opt-in and manual". They *were* opted into; nothing ever accounted for the accumulation.

**`ujust boot-audit` is a diagnostic, not a watchdog, and the distinction is not pedantry.** An earlier version of this paragraph ended "the policy is only as real as the thing that checks it", pointing at that command — which promises supervision a manual command cannot provide. The evidence is `uupd.timer`: it sat inert for an unknown length of time, the machine quietly stopped auto-updating, and no watchdog would have caught it because nobody was running one. What caught it was investigating something else and looking.

So run it when you ask *"what is actually on this machine?"* — after a rebase, when something behaves oddly, or before changing what starts at boot. Expect roughly twenty lines, most of them intentional: `tailscaled` and `sunshine` are supposed to be there, and `docker`/`libvirtd` may well be too. It reports facts and labels nothing a violation, because it cannot tell your deliberate choice from accumulated drift — only you can.

A baseline file plus an acknowledge command was considered and rejected: it would solve a problem other than the one that actually occurred, and add state that itself needs maintaining. If real supervision is ever wanted, the shape is a timer that reports or `uupd` failing loudly — a different decision, not taken here.

The exception this section makes for `lock-on-session-start.service` belongs with the rule rather than hidden in a recipe: `ujust autologin-setup` **enables** it, which the rule above forbids. It is a oneshot that locks the screen and exits, so it competes for none of the CPU/RAM/VRAM this policy protects, and leaving it disabled would leave autologin unguarded — an open desktop is strictly worse than the login screen it replaced.

## 🏗️ Architecture

### Modular Hybrid Build Model

```
recipe.yml              ← Entry point (declarative orchestration)
├── files module        ← Overlays files/system/ onto /
├── dx.yml              ← EXTENSIONS: Cockpit, Docker, Libvirt, eBPF tools, fonts
│   └── local modules   ← Encapsulated logic: dx-flavor (branding/policy), dx-udev
├── silver-goggles.yml  ← HARDWARE: Dell G15 kargs, AWCC RPM (rpm-ostree), thermald mask
├── casting.yml         ← CASTING: AirPlay/FCast/scrcpy receivers + iOS bridges (opt-in via ujust)
├── nomad.yml           ← OFFLINE KNOWLEDGE & AI: Project NOMAD (Quadlet units + ujust; nothing enabled)
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
6. **OFFLINE KNOWLEDGE & AI** — Project NOMAD offline stack (`nomad.yml`).

### Key Directories

| Path | Purpose |
|------|---------|
| `recipes/` | Build declarations (`recipe.yml`, `dx.yml`, `silver-goggles.yml`, `casting.yml`, `nomad.yml`, generated `build-recipe.yml`) |
| `files/system/` | Static files overlaid onto `/` at build time via the `files` module |
| `files/system/usr/lib/tmpfiles.d/` | Atomic symlinks (L+ pattern) — Flatpak overrides and symlinks |
| `files/system/usr/lib/environment.d/` | System-wide environment variables (CHROME_EXTRA_FLAGS, etc.) |
| `files/system/etc/modules-load.d/` | Kernel module **opt-outs**: an empty `/etc/modules-load.d/<x>.conf` masks the same-named file under `/usr/lib/modules-load.d/`. `kvmfr.conf` is 0 bytes on purpose (dx-verify registers it as "Mask: KVMFR Autoload"), so do not "fix" it. Modules this layer actually wants loaded are declared under `/usr/lib/modules-load.d/` — e.g. `br_netfilter` in `ip_tables.conf`. Nothing here loads `acpi_call`, and nothing can: see the AWCC note below |
| `files/system/usr/lib/systemd/user/` | **User units, image-resident and read-only.** `ujust` only activates them — never copies them into `$HOME`, which would shadow the image copy and freeze the host on it. Note `start` vs `enable`: see the lingering subsection under Boot Impact Policy |
| `files/system/etc/containers/systemd/users/` | **Rootless Quadlet units** (`.container`/`.network`) for the NOMAD stack, turned into `.service` by a systemd generator. Under `/etc` and not `/usr` because rootless Quadlet has **no `/usr` search path** — `man podman-systemd.unit` lists only `$XDG_RUNTIME_DIR/containers/systemd/`, `~/.config/containers/systemd/`, `/etc/containers/systemd/users/$(UID)` and `/etc/containers/systemd/users/`. The rootful list *does* include `/usr/share/containers/systemd/`, so going rootful would restore the `/usr` placement — at the cost of the security property that made podman the right engine (see the socket note in README). This is not a breach of Atomic State Policy item 1, which forbids mutating `/etc` imperatively at runtime, not shipping into it via the `files` module |
| `files/justfiles/` | Host-side `ujust` recipes (66-silver-goggles.just, 67-casting.just, 68-nomad.just, 95-bazzite-dx.just), injected via the `justfiles` module |
| `files/system/usr/share/ublue-os/casting/` | Staged casting **config template** (`uxplayrc.tmpl`) copied into `$HOME` by `ujust` on request. The units themselves live in `usr/lib/systemd/user/` |
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

### `/usr` is declarative. `/etc` is only seeded. Know which one you are writing to.

"Declarative and immutable" is true of `/usr` and merely *advisory* for `/etc`, and conflating the two produced nearly every wrong diagnosis this layer has recorded. **26 of the 112 files this image ships land in `/etc`** — not the periphery: all six NOMAD Quadlet units, `cockpit.conf`, the resolved DNS drop-in, `/etc/skel`.

| | `/usr` (86 files) | `/etc` (26 files) |
| :--- | :--- | :--- |
| Image replaces on rebase | always | **only if you never touched it** |
| You edit it | impossible, read-only | your edit wins forever |
| You delete it | impossible | **your deletion wins forever, silently** |
| Image re-asserts later | yes | **never** |

ostree performs a three-way merge on `/etc` at deployment time, so a local change — including a deletion — outranks the image from then on. That is the OS working as designed: the administrator outranks the vendor. It is also why declaring something is not the same as it being applied.

**Measured consequences, so nobody has to rediscover them:**

- `uupd.timer` was **inert** — the machine had stopped auto-updating, with no error, no failed unit, nothing. `ostree admin config-diff` reported it as `D`.
- `ublue-nvctk-cdi.service` was likewise `D`, and the base image had been enabling it all along: both deployments on disk carry the symlink under `usr/etc/systemd/system/multi-user.target.wants/`, including the one predating the line that "added" it.
- Adding `systemd: enabled:` to a recipe therefore **repairs nothing on an upgraded host**. It works on a fresh install. On this one, only `systemctl enable` does.

**Practical rules:**

1. Prefer `/usr` whenever the mechanism allows it. Rootless Quadlet is the notable case where it does not — see the Key Directories note.
2. A recipe's `systemd: enabled:` declares intent and documents a dependency. Do not treat it as a guarantee, and do not "fix" a disabled unit by re-declaring it.
3. Runtime provisioning (`bazzite-dx-groups`) is the reliable path for anything that must actually be true on an existing host. It ran successfully on the very boot where the declarative unit enablement did not.
4. `ujust boot-audit` reports both directions of divergence. The direction that hurts is the quiet one — what the image enables and the host does not.

### Rules

1. **Static files** go under `files/system/` (the `files` module overlays them onto `/`). Never mutate `/etc` directly.
2. **Flatpak overrides**: NEVER use `flatpak override` or `sudo cp` in scripts. Use `tmpfiles.d` with the **`L+` (symlink with overwrite)** pattern linking `/usr/share/flatpak/overrides/` → `/var/lib/flatpak/overrides/`.
3. **Global env vars** go in `files/system/usr/lib/environment.d/*.conf`. Never `export` in profile scripts.
4. **Service enable/mask** is declared via the `systemd` module in `recipe.yml` OR generated by local modules at build time (e.g., `dx-flavor` presets). Reference: `thermald.service` masked (see the Thermal section for the measured reason — *not* "AWCC compat", which was wrong), `systemd-udev-settle.service` masked (VFIO/IOMMU stability). Do not add preset files manually — and note this rule was being violated by a hand-written `00-silver-goggles.preset` that duplicated `enable awccd.service` / `disable thermald.service` already declared in `silver-goggles.yml`. It was redundant, not merely untidy: BlueBuild's `systemd` module runs `systemctl -f enable` / `systemctl mask` directly (`blue-build/modules/modules/systemd/systemd.sh:38,56`), so it never consulted the preset. Deleted.
5. **Kernel args** go via the `kargs` module (plus local-module tuning if needed). Never use imperative boot scripts.
6. **Image transformation**: build-time scripts (local modules) are the authorized escape hatch for branding, policy enforcement, and config that static overlays can't express.
7. **User units live in `files/system/usr/lib/systemd/user/`, never copied into `$HOME`.** A `ujust`
   recipe's job is `systemctl --user enable`, which writes only a symlink under
   `~/.config/systemd/user/<target>.target.wants/`. Opt-in is preserved: a unit sitting in
   `/usr/lib/systemd/user/` starts nothing until enabled. Copying the unit into `$HOME` instead
   breaks the atomic contract twice over — `~/.config/systemd/user` takes **precedence** over
   `/usr/lib/systemd/user`, so the copy shadows the image forever, and a `if [[ ! -f ]]` guard
   then freezes the host on whichever version it first ran. Both happened here: a host booted an
   image containing the `stdbuf` pairing-pin fix and the `code-server` hardening commit (7f52615)
   while still running the pre-fix units. Precedent on-image: bazzite ships
   `bazzite-user-setup.service` and `ublue-user-setup.service` this way, and `sunshine.service` is
   enabled straight out of `/usr/lib/systemd/user/`. When migrating a unit out of `$HOME`, delete
   the stale copy and `systemctl --user reenable` — plain `enable` leaves the now-dangling
   `*.wants` symlink untouched. Enabled template instances (`ide-tunnel@code.service`) are **not**
   listed by `list-unit-files 'ide-tunnel@*.service'` (that reports only the template, "indirect
   disabled"); enumerate the `*.target.wants/` symlinks instead.

### 🎙️🎨 AI Studio Architecture (Visual & Audio)

The AI Studio stack follows a **Single Unified Mode** architecture based on **Rootless Podman Quadlets** and persistent SSD storage:

- **AI Studio Visual (`aistudio-visual.container`, Port :61384)**:
  - Backed by ComfyUI, CyberRealistic V9, SD 1.5, and LivePortrait Neural Facial Animation.
  - Accelerated via NVIDIA CUDA on RTX 3060 Laptop GPU.
  - **Zero Boot-Time Pip Installs**: All Python packages live permanently on SSD in `/var/srv/visual/site-packages` and mount into `PYTHONPATH`. Starts in **< 2 seconds**.
  - Recipes: `70-aistudio-visual.just` (`ujust visual-up`, `ujust visual-down`, `ujust visual-status`, `ujust visual-animate`, `ujust visual-enable-boot`).

- **AI Studio Audio (`aistudio-audio.container`, Port :61386)**:
  - Backed by Speaches AI (Piper TTS, Faster-Whisper STT, OpenAI-compatible `/v1/audio/*` endpoints) and ChatTTS (expressive conversational speech with laughter `[laugh]` and natural pauses).
  - Runs **100% on CPU** (i7-12700H 14 cores / 64GB DDR5), preserving 100% GPU VRAM for visual generation and gaming.
  - Recipes: `71-aistudio-audio.just` (`ujust audio-up`, `ujust audio-down`, `ujust audio-status`, `ujust clone-voice`, `ujust audio-enable-boot`).

- **Deliverables Policy (Strict XDG Standards)**:
  - All visual outputs (8K Portraits & MP4 Videos): `${XDG_PICTURES_DIR:-$HOME/Pictures}/AI_Studio/`
  - All audio outputs (WAV/MP3 Speech & Soundtracks): `${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio/`

### Scripting Conventions

- Shell scripts must pass `shellcheck` (`just lint`); format with `shfmt` (`just format`).
- Custom BlueBuild modules follow the pattern in `modules/` and should include an integrity check where possible (see `dx-verify`).

### dx-verify: presence is not behaviour

The registry started as `file|`/`bin|` asserts, which check that an asset exists. That is why a
dead udev rule, a device unit that never appears and a nonexistent `acpi_call` all passed green
for as long as they did. Two providers now check behaviour instead:

- **`unit|<path>`** — runs `systemd-analyze verify` (`--user` inferred from the path) and fails on
  any diagnostic. It must grep the *output*: measured, `verify` exits **0** for a unit containing
  `BogusKey=yes` and for one whose `ExecStart` does not exist. `/home/linuxbrew` lines are
  filtered, since Homebrew is installed at runtime and "Command … is not executable" is expected
  in the build container. Known blind spots, so nobody over-trusts it: legacy aliases draw no
  warning at all (`BindTo=` is silently accepted for `BindsTo=`), and references to units or
  devices absent on the target are fine by it.
- **`nostage|<dir>`** — greps the installed justfiles for any recipe that `install`s a `.service`
  into `$HOME`/`$UNIT_DIR`, i.e. a regression against Atomic State Policy item 7. Purely static, so
  it works in a build container with no user session.
Both were checked against injected regressions, not just the clean tree — a check that has never
failed is a check you have not tested. A third provider (`nocontent|`, asserting a pattern is
absent) was written to keep `[Install]` out of `fcast-receiver.service` and then deleted with that
unit: a provider with no target is dead weight. **A udev-rule assert was deliberately not added:** matching
`DRIVER==` against real devices needs the target hardware, and `udevadm info -e` in CI describes
the build runner, so it would have to pass vacuously. After the `g15-thermal` deletion no shipped
rule matches on `DRIVER==` at all; if one is added, verify it on the machine, because the build
cannot.

## ⚙️ AWCC RPM Workflow

`files/rpm-ostree/awcc-dev.rpm` is committed to the repo and installed at image build time via the `rpm-ostree` module.

| Command | Spec used | Source |
|---|---|---|
| `just build-awcc` | `awcc.spec` (default) | Downloads tarball from `tr1xem/AWCC`, version synced with base image |
| `AWCC_SPEC=awcc.dev.spec just build-awcc <src>` | `awcc.dev.spec` | Local source from `nklowns/AWCC` fork (pinned commit) |

After rebuilding, commit the RPM: `git add -f files/rpm-ostree/awcc-dev.rpm && git commit`.
Rapid iteration: `just hot-swap-awcc <path>` (live apply, no reboot); revert with `just uninstall-awcc`.
Full workflow: [`docs/AWCC-BUILD.md`](docs/AWCC-BUILD.md).

### 🌡️ Thermal: use the in-tree interface, not `acpi_call`

**`acpi_call` does not exist on this image and is not worth chasing.** It is out-of-tree, absent
from the kernel tree (`modinfo acpi_call` → not found), and absent from every uBlue akmods set —
this image ships 20+ kmods (xone, v4l2loopback, openrazer, kvmfr, evdi, framework-laptop…) and no
`acpi_call`, with zero references to it anywhere in the `ublue-os/` clones. AWCC drives G-mode by
writing raw ACPI through `pkexec` to `/proc/acpi/call`
(`dell_related/AWCC/src/AcpiUtils.cpp:208-216`, `Daemon.cpp:234`), so **the app's G-mode and fan
controls are silently no-ops here.** Building an akmod for it would mean tracking the custom `-ogc`
kernel across every bump, with signing, for a feature the kernel already provides.

The in-tree replacement is already loaded and covers everything AWCC wants:

| Surface | Path | Measured |
|---|---|---|
| Thermal profiles | `/sys/class/platform-profile/platform-profile-0` (`name=alienware-wmi`, `DRIVER=alienware-wmi-wmax`) | `low-power quiet balanced balanced-performance performance custom` |
| Per-fan boost + telemetry | `/sys/class/hwmon/hwmon*` where `name=alienware_wmi` | `fan1/2_input,max,min`, `fan1/2_boost`, `temp1/2_input` (CPU/GPU) |

`performance` ⇒ `fan_boost=100`; `balanced` ⇒ `fan_boost=0` (fans stop entirely at ~48 °C idle);
writing `fan1_boost=60` under `balanced` spun the CPU fan to 3316 RPM with the GPU fan still at 0.
That *is* G-mode, upstreamed. **`tuned`/`tuned-ppd` own this in userspace** (they serve
`net.hadess.PowerProfiles`, KDE powerdevil is a client) and they *follow* `platform_profile`:
writing `balanced` to the sysfs node flipped `tuned-adm active` to `balanced-bazzite` on its own.
So use `tuned-adm profile …`, the KDE power widget, or that sysfs node — never a boot-time script
racing the daemon.

#### Do not try to "fix" AWCC's thermals, and do not migrate to alienfx-linux for them

Upstream's prescription is DKMS. On the still-open AWCC issue #124 the maintainer answers "the acpi
module is not in kernel install acpicall-dkms and modprobe acpi_call", and issue #111 — *literally*
this image's error, `Unknown thermal mode returned: 0xffffffff` — was closed as **stale**, not
fixed. DKMS is not available on an atomic host, and no uBlue akmods set carries `acpi_call`.

`dell_related/alienfx-linux` (same author, the repo AWCC's README points at) is **not** the escape
hatch for this, despite `AlienFan-SDK/src/AlienFan-SDK.cpp` reading exactly the right surfaces
(`/sys/class/hwmon` for `name == alienware_wmi`, `/sys/class/platform-profile`) and even
implementing `SetFanBoost()` as an `ofstream` on `fanN_boost`. Its CLI exposes **no fan command at
all** — 14 subcommands: nine for lights, `getpowerprofile`/`supportedprofiles`/`setpowerprofile`,
`status`, `reset`. And the profile half duplicates what `tuned` and the KDE power widget already do.
AWCC is also not deprecated (182★ vs 25★, 1.19.0, new devices as recently as June 2026); its
roadmap marks `[x] New backend for thermal mode (AlienFan-SDK)` but the code contradicts that —
zero `hwmon`/`platform-profile` references anywhere in `AWCC/src`, and `Thermals.cpp` still goes
through `AcpiUtils` → `/proc/acpi/call`.

So: **AWCC stays for lights** (`LightFX.cpp` is libusb, independent of ACPI, which is why the
keyboard zones work and always did), profiles come from tuned/KDE, and if per-fan boost is ever
wanted the cheap path is ours, not upstream's — a `dx-udev` rule granting group write on
`fanN_boost` plus a `ujust`, on the sysfs nodes measured below. Worth remembering the measurement
before building that: on CPU load it buys ~0 MHz. If alienfx-linux is ever packaged, pin its
`FetchContent` deps — libusb-cmake, loguru and hidapi are all declared with floating
`GIT_TAG main`/`master`.

#### What max fan actually buys (measured, so stop guessing)

`stress-ng --cpu 20` for 80 s on AC, same load under both profiles:

| | `balanced` | `performance` |
|---|---|---|
| CPU temp under load | **99 °C** | **99 °C** |
| Fan RPM under load | 3738 → 3802 | 4750 → 4842 (`fan1_max` = 4800) |
| Sustained avg clock @75 s | 3023 MHz | **3035 MHz** |
| Idle, 45 s after load | 2091 RPM / 57 °C | **4796 RPM** / 57 °C — never spins down |

**~1000 extra RPM bought ~0 MHz.** On a full-core load this chip is Tjmax/power limited, not
airflow limited, so forcing `performance` at boot costs constant maximum fan noise and returns
nothing measurable. It also never comes back down. The boot-time forcing was *deliberate* — a way
to avoid enabling G-mode by hand — which is why the numbers matter: the on-demand path (KDE power
widget, or `tuned-adm profile throughput-performance-bazzite`) gives the same thing for one click,
and `balanced` ramps 0 → ~3800 RPM under load on its own.

**Deleting `g15-thermal` was necessary but not sufficient, and the rest is host config, not
image.** After booting the image without it, the machine still came up at `performance` with
`fan_boost=100` and both fans at 4830 RPM at 56 °C. Two persistent writers, neither in the image:
`/etc/tuned/active_profile` held `throughput-performance-bazzite` with `profile_mode=manual`, and
`~/.config/powerdevilrc` had `[AC][Performance] PowerProfile=performance` (battery was already
`balanced`, low battery `power-saver`) — so KDE re-asserts performance through tuned-ppd at every
login while on AC. The image change removed a redundant *second* writer, not the order itself.

One more trap: **picking a profile in the KDE power widget is runtime-only.** Selecting Balanced
moved `net.hadess.PowerProfiles` `ActiveProfile` to `balanced` and dropped the fans to 0 RPM, but
left `powerdevilrc` untouched (verified by mtime), so the next login would have restored
`performance`. Persisting it needs the config key — System Settings → Power Management, or
`kwriteconfig6 --file powerdevilrc --group AC --group Performance --key PowerProfile balanced`.

#### GPU-bound load is the opposite result — and the reason `g15-boost` exists

Same question, GPU side. Load was an OpenCL FMA burn (100 % SM, 115 W of a 130 W board limit);
both profiles were run twice, from a cold start each time (`gpu ≤ 62 °C`, `cpu ≤ 60 °C`) and in both
orders, because the first round gave `performance` a 6 °C heat-soak handicap from the previous run
and would have inverted the conclusion:

| elapsed | `balanced` (fans ~3800) | `performance` (fans ~4800) |
|---|---|---|
| 20 s | 79 °C · 1852 MHz · 115 W | 76 °C · 1860 MHz · 115 W |
| 40 s | 84 °C · 1830 MHz · 115 W | 81 °C · 1845 MHz · 115 W |
| 60 s | 87 °C · 1792 MHz · 109 W · **SW_THERMAL** | 84 °C · 1837 MHz · 115 W · POWER_CAP |
| 80 s | 87 °C · 1710 MHz · 94 W · **SW_THERMAL** | 87 °C · 1815 MHz · 115 W · POWER_CAP |

**Here the airflow pays: ~+105 MHz sustained and +20 W of usable board power at 80 s, and
`SW_THERMAL` is held off by 20 s or more** — under `performance` the GPU was still limited by its
*power* cap where `balanced` had already fallen back to a *thermal* one. The CPU-only result was
~0 MHz for the same 1000 RPM, and the asymmetry has a cause: the GPU has power headroom that only
cooling can unlock, while the CPU is already Tjmax-limited at its power ceiling.

That is an argument for a wrapper, not a global default — quiet at idle, loud only while something
is on the GPU. Two things ship for it, neither needing root, because `tuned-ppd` serves
`net.hadess.PowerProfiles` and polkit lets the active session set `ActiveProfile` exactly as the
KDE widget does (verified: `busctl --system set-property … ActiveProfile s performance` flipped
`fan_boost` to 100 with no password):

- **`/usr/bin/g15-boost <command>`** — sets `performance`, runs the command, restores the previous
  profile from an `EXIT`/`INT`/`TERM`/`HUP` trap. Meant as a Steam launch option:
  `g15-boost %command%`. Measured limit: bash defers a trap while a foreground child runs, so a
  `SIGTERM` to the wrapper restores only after the child exits (`kill -TERM` at t+5 s of a 30 s
  child kept `performance` until t+30 s) — which is the behaviour you want anyway, since the game
  is still running. `SIGKILL` of the wrapper is the one uncovered case.
- **`ujust g15-profile [profile]`** — prints the active profile, the sysfs view, the provider's
  choices and current fan boost/RPM; with an argument, switches. It goes through PowerProfiles
  rather than the sysfs node on purpose: two writers is what produced the permanent max-fan bug,
  and the daemon wins the next event.

Both stay away from `fanN_boost` writes, which *would* need root — the profile switch already
delivers `boost=100`, which is the whole measured win.

That measurement is also the honest justification for **masking `thermald`**. The old "AWCC compat"
reason does not survive contact: `thermald` writes RAPL (msr/mmio) and binds cooling devices, and
the only cooling devices on this host are `Processor` (×18) and `PCIe_Port_Link_Speed` — no fan —
while AWCC drives fans over WMAX ACPI commands. No shared node, and AWCC's thermal half cannot run
here anyway. The defensible reason is the table: the CPU already sits at Tjmax with the EC and
PROCHOT in control, so adding userspace RAPL capping would take sustained clock away with nothing
to gain. Fedora does enable `thermald` for desktops (`90-default.preset:419`) and upstream Bazzite
does not mask it, so this is a deliberate local deviation, and it should be re-tested if the
thermal picture changes (e.g. after an `alienfx-linux` migration restores real fan control).

**`g15-thermal.service` and `99-g15-thermal.rules` were deleted for exactly that reason**, and the
reason is worth keeping written down because it inverts the obvious reading. The unit looked
harmless — its `acpi_call` branch was dead, so it fell through to
`echo performance > /sys/firmware/acpi/platform_profile`, which reads as redundant. It was not:
`tuned-adm recommend` returns **balanced** on this hardware, tuned then followed the unit's write
up to `throughput-performance-bazzite`, and `alienware-wmi` mapped that to `fan_boost=100`. Net
effect: the laptop idled at ~4100-4784 RPM on both fans at 48-53 °C, permanently, caused by the
very unit meant to "trigger G-mode". Its trigger path was broken too — the rule's second line
matched `SUBSYSTEM=="platform", DRIVER=="alienware-wmi"` while the real device is `SUBSYSTEM=wmi`,
`DRIVER=alienware-wmi-wmax`, and `BindTo=dev-platform-dell\x2dwmi.device` named a nonexistent
device unit, so systemd stopped the oneshot in the same second it finished.

## 📱 Casting & Mobile Bridge (`recipes/casting.yml`)

Receives screen/media from iOS and Android. Split by discovery mechanism, and the split is
architectural — **not** a configuration gap:

| Path | Tool | Discovery | Tailnet |
|---|---|---|---|
| iOS/macOS screen + audio | `uxplay` (`ujust airplay-setup`) | mDNS | ❌ never |
| media casting | FCast flatpak app, launched by hand (`ujust fcast-setup` installs it) | mDNS **or manual IP** | ✅ TCP 46899 |
| Android screen + audio | `scrcpy` (`ujust android-mirror <host>`) | ADB over TCP | ✅ |
| input/clipboard/files | KDE Connect (`ujust kdeconnect-tailnet-add <host>`) | broadcast **or manual IP** | ✅ Android · ❌ iOS |
| iOS files/apps | `libimobiledevice-utils`, `ifuse`, `ideviceinstaller` | USB (usbmuxd) | ⚠️ USB only |

**Do not try to make AirPlay or Miracast work over Tailscale.** Tailscale carries no
multicast/broadcast, and the iOS AirPlay picker offers no manual-address entry. The tailnet-capable
tools above are tailnet-capable precisely because a hostname can be typed by hand.

**KDE Connect over the tailnet is Android-only in practice.** A custom device is only an extra
unicast destination for the UDP identity packet; the phone must then dial TCP 1716 back. Measured
here with both phones on the same tailnet, off Wi-Fi, same probe: the Android answered on 1716 and
established a link at tailnet addresses (`<tailnet-ip-1>:1716 <- <tailnet-ip-2>:60774`), while the
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
returned real output, the socket was `<tailnet-ip-1>:34988 -> <tailnet-ip-2>:38124`, and
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
- `uxplay.service` follows the graphical-session pattern proven by
  `files/system/usr/share/ublue-os/user-setup.hooks.d/45-sunshine-graphical-session-fix.sh`:
  `After=graphical-session.target plasma-kwin_wayland.service`, `Requisite=` (never
  `Wants=`/`Requires=`, which would spawn a standalone compositor at boot under user
  lingering and steal the DRM device from the real login session),
  `WantedBy=graphical-session.target` (never `default.target`), and an `ExecStartPre`
  that polls for the Wayland socket instead of trusting unit-active — on NVIDIA/prime
  `plasma-kwin_wayland.service` reports active 20-30s before the compositor serves
  clients. A socket test is used rather than `busctl get-property`, which would
  resurrect the portal and kwin as a side effect of asking.
- Nothing is enabled at boot. `casting.yml` declares no `systemd` module; `uxplay.service` ships
  inert in `/usr/lib/systemd/user/` and `airplay-setup` only `enable`s it on request — same pattern
  as `remote-ide-setup`. See Atomic State Policy item 7 for why it is not copied into `$HOME`. FCast
  has no unit at all; see below.
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
    `nh`, without which the advertised name is `Silver Goggles@<tailscale-fqdn>`.
  - `ExecStart` wraps uxplay in `stdbuf -oL -eL`, and that is load-bearing. uxplay only calls
    `setbuf(stdout, NULL)` under `_WIN32`, so on Linux glibc fully buffers stdout whenever it is not
    a tty — always, under systemd. The pairing pin goes to stdout, so unbuffered it reaches the
    journal only when the process exits: the observed symptom was `*** ERROR: Client Authentication
    Failure (client proof not validated)` on the phone side, because the pin the user was supposed
    to type had never been displayed. Verified end-to-end after the fix: pin printed live, iPhone
    (`iPhone14,5`, `AirPlay/950.7.1`) paired and registered, `raop_rtp_mirror starting mirroring`.
- **`*-setup` only `enable`s; it stages no unit at all.** `uxplayrc` is user config and is still
  never overwritten, but the units carry no tunables and live in `/usr/lib/systemd/user/`. The
  earlier copy-into-`$HOME` version pinned each host to whatever the image shipped on first run:
  after the `stdbuf` fix landed and `latest.20260727` was booted, the running `ExecStart` was still
  the old bare `/usr/bin/uxplay`, because `~/.config/systemd/user/uxplay.service` already existed.
  Both recipes therefore delete a legacy non-symlink copy and `reenable`. A user drop-in also wins
  over the image unit — same failure mode from the other direction, and the reason the local
  `10-line-buffered.conf` drop-in had to be removed after the fix shipped.
- **FCast has no systemd unit, on purpose — it is a windowed Flatpak app.** `ujust fcast-setup`
  installs `org.fcast.Receiver` (and the sender with `with_sender=yes`), prints the addresses to
  type into senders, and stops there. You launch it from the app menu when you want to receive
  something; closing the window quits it; nothing starts it at login. `ujust fcast-off` exists only
  as a rescue for a copy left running with no window, and `casting-status` reports the live copy
  count rather than a unit state.
  **This replaced a unit, and the unit is the cautionary tale.** Wrapping a GUI Flatpak in
  `fcast-receiver.service` bought nothing the desktop launcher does not already do, and it cost
  three separate runtime bugs on this machine: a `restart` in `fcast-setup` that opened a window
  merely because you asked to install the app; `Restart=on-failure` blamed for duplicate windows it
  never caused (no `Scheduled restart` line exists in any journal here); and finally the migration
  block calling `systemctl --user reenable` — which is disable+enable — creating
  `~/.config/systemd/user/graphical-session.target.wants/fcast-receiver.service` and making the
  receiver open by itself on the next boot, on an image that had just been updated to stop exactly
  that. Around it had accreted `Requisite=graphical-session.target`, a Wayland-socket
  `ExecStartPre` poll, `ExecStartPre=-flatpak kill`, `Restart=no` and
  `SuccessExitStatus=137 143`. On an atomic host the rule is simpler than any of that: **systemd
  units are for daemons; a Flatpak with a window is launched by the desktop.**
- **Two upstream FCast bugs still matter when using it, and the local advice is just "don't open it
  twice".** Reported as [futo-org/fcast#119](https://github.com/futo-org/fcast/issues/119) and
  [#120](https://github.com/futo-org/fcast/issues/120). Measured here: instance A binds TCP 46899;
  instance B panics on `receiver-core/src/lib.rs:978  called Result::unwrap() on an Err value:
  Address already in use (os error 98)` on the `main-async-worker` thread, so the *thread* dies and
  the process does not — B's window stays up with no listener and reports **"Your device isn't
  connected to a network"**, pointing at the network and meaning the opposite. And
  `Slint: Failed to create system tray icon: 0` on KDE Wayland means a running copy has no tray
  handle, so the app menu is the only way back to it, which produces case B. Note the Flatpak's own
  session bus policy already grants `org.kde.StatusNotifierWatcher=talk` and the host watcher is
  live (`kded6`, and another app's tray item works), but no appindicator/dbusmenu/ksni library
  exists inside the sandbox — filed as a strong hypothesis, not a verified root cause. A healthy
  copy does exit cleanly (`Result=success`, status 0) when its window is closed.
- `casting-status` captures `systemctl is-active` with `|| true`, never `|| echo <fallback>`:
  `is-active` already prints the state on stdout *and* exits non-zero for anything but active, so a
  fallback prints both strings on one line.
- `files/system/usr/lib/firewalld/services/{uxplay,fcast}.xml` are definitions only, bound to no
  zone. The default `FedoraWorkstation` zone already opens `1025-65535/tcp+udp` and `tailscale0`
  sits in `trusted`, so `ujust casting-firewall` is a no-op there and says so.
- `adb` comes from the `android-platform-tools` **cask** in `cli.Brewfile` (Homebrew 6.x installs
  casks on Linux). The Fedora `android-tools` RPM stays commented out in `dx.yml` on purpose —
  enabling it would put a second `adb` in `PATH`.
- **`shairport-sync` was shipped and then removed — do not add it back without reading this.**
  `nqptp` is absent from Fedora, so it is AirPlay **1** only, while UxPlay's audio-only mode
  (`-async`) already covers AirPlay 2 ALAC *with* pin auth. It was finally exercised before being
  dropped, and it worked, which is not the same as being acceptable: it advertised
  `_raop._tcp` on port 5000 with **`pw=false`** — an anonymous receiver any host on the LAN can
  push audio to, in direct contradiction of the pin-or-nothing rule the rest of this layer
  follows. It also advertised as `…@Bazzite.drake-ayu.ts`, leaking the tailnet hostname into LAN
  mDNS (the same defect `nh` fixes for UxPlay), and it published on every interface including
  `docker0`, `br-*` and container veths. Its unit was `disabled`, so none of that was live — but a
  receiver that is one `systemctl start` away from anonymous LAN audio is not worth carrying for a
  protocol generation UxPlay already serves. Re-adding it means shipping an
  `/etc/shairport-sync.conf` with a password, a fixed name and `interface = "wlan0"` — the stock
  config in the image has every block empty.

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
