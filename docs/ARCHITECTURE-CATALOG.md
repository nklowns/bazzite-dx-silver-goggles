# Catálogo de camadas e comparação entre imagens

> Levantamento feito em 2026-11-08 sobre os clones de referência em
> `/var/home/cloud/dev/study/upstream/ublue/` (todos sincronizados com o upstream
> nessa data) e sobre este repositório. Objetivo: **medir** o que existe antes de
> propor simplificação.

---

## 1. Inventário do `bazzite-dx-silver-goggles`

### 1.1 Pipeline de build

| Arquivo | Linhas | Papel |
| :--- | ---: | :--- |
| `recipes/recipe.yml` | 53 | Entry point: base, labels, ordem dos módulos |
| `recipes/dx.yml` | 148 | Pacotes DX + serviços + módulos locais + `95-bazzite-dx.just` |
| `recipes/silver-goggles.yml` | 52 | Kargs Dell, pacotes de hardware, `thermald` mascarado, justfiles 66/69/70/71/72 |
| `recipes/casting.yml` | 48 | `uxplay` + pontes iOS/Android + `67-casting.just` |
| `recipes/nomad.yml` | 6 | Só o justfile 68 (Quadlets vêm pelo `files`) |
| `recipes/build-recipe.yml` | 57 | **Gerado** por `scripts/generate-recipe.sh` — não editar |
| `modules/*/` (6) | 687 | `dx-flavor`, `dx-udev`, `dx-cockpit`, `dx-hardening`, `dx-verify`, `gpu-unlock` |

- Base: `ghcr.io/ublue-os/bazzite-nvidia` (digest em `image-versions.yaml`, Renovate).
- Toolchain: **BlueBuild CLI + recipe v1**.
- `just check` = sintaxe just + `bluebuild validate` + ShellCheck.

### 1.2 Pacotes instalados (72 entradas rpm)

| Domínio | Pacotes |
| :--- | :--- |
| Containers | `moby-engine`, `containerd`, `runc`, `docker-cli`, `docker-buildx`, `docker-compose`, `docker-compose-switch`, `podman-compose`, `podman-tui`, `podman-machine`, `crun-wasm` |
| Virtualização | `libvirt`, `libvirt-nss`, `virtiofsd`, `incus`, `incus-agent`, `lxc`, `qemu-kvm`, `qemu-img`, `swtpm(-tools)`, `cloud-hypervisor`, `virt-manager`, `virt-v2v`, `virt-viewer`, `guestfs-tools`, `udisks2-btrfs`, `dmg2img`, `genisoimage` |
| Observabilidade | `bcc`, `bpftop`, `bpftrace`, `iotop`, `nicstat`, `numactl`, `pcp*` (4), `sysprof`, `tiptop`, `trace-cmd`, `wireshark-cli`, `nmap`, `powertop`, `inxi`, `hwinfo` |
| Cockpit | `cockpit-bridge`, `cockpit-machines`, `cockpit-ws` |
| Hardware G15 | `smbios-utils-python`, `policycoreutils`, `looking-glass-client` |
| Mobile | `uxplay`, `usbmuxd`, `libimobiledevice-utils`, `ifuse`, `ideviceinstaller` |
| Build/VCS | `flatpak-builder`, `git-subtree`, `git-svn`, `util-linux-script`, `waypipe`, `qt6-qttools`, `zsh` |
| Ublue | `ublue-setup-services`, `ublue-os-libvirt-workarounds`, `kcli` |

Sobreposição medida:

- **18 dos 64** pacotes de `dx.yml` já são entregues pelo `bazzite-dx` upstream
  (`bcc`, `bpftop`, `bpftrace`, `flatpak-builder`, `git-subtree`, `guestfs-tools`,
  `libvirt`, `nicstat`, `numactl`, `podman-machine`, `podman-tui`, `qemu-kvm`,
  `sysprof`, `tiptop`, `ublue-setup-services`, `virt-manager`, `waypipe`, `zsh`).
- **0** pacotes duplicam o `bazzite` base (só `edk2-ovmf`, que já está comentado).
- `incus` + `lxc` + `libvirt` + `moby-engine` + `podman` coexistem: quatro stacks de
  container/VM no mesmo host, nenhuma delas declarada como opcional.

### 1.3 `files/system` — 223 arquivos + 4 symlinks (3,5 MB)

| Domínio | Arquivos | Observação |
| :--- | ---: | :--- |
| Desktop / UX / IDEs | 39 | inclui `xp_bliss.jpg` (**2,4 MB**, 68 % do peso), 5 ícones, 4× `keybindings.json` idênticos (6,7 KB cada) |
| Acesso remoto | 35 | cockpit, sunshine, rustdesk, guacamole, mediamtx, webcam, remote-ide, krdp |
| Shell / dev env / brew | 32 | `bling.*` (22 KB), `common-aliases.*`, `starship`, `atuin`, 6 Brewfiles (23 KB), `profile.d`, `environment.d` |
| Hardware G15 / virtualização | 28 | `g15-*`, GPU unlock, `udisks-ignore-root`, hook `qemu`, templates libvirt |
| Unidades systemd / tmpfiles / udev | 26 | 12 user units, 10 tmpfiles, 5 udev rules, drop-ins |
| AI / NOMAD / Mesh (suporte) | 18 | templates searxng/recoll, bootstrap de segredos, helpers |
| AI / NOMAD / Mesh (Quadlets) | 17 | todos em `/etc/containers/systemd/users/` |
| Segurança / rede / performance | 16 | DoT, MAC randomization, chrony, sysctl, limits, 6 CIL |
| Outros | 16 | `bazzite-dx-groups` (31 KB!), `project-nomad-*`, `84-bazzite-virt.just` |

### 1.4 Superfície `ujust` — 8 arquivos, 3.972 linhas, 177 receitas

| Arquivo | Linhas | Receitas | Domínio |
| :--- | ---: | ---: | :--- |
| `66-silver-goggles.just` | 1008 | 58 | remote access (sunshine/rustdesk/guacamole/cockpit), code-server, ide-tunnel, g15, gpu-unlock |
| `67-casting.just` | 433 | 11 | AirPlay, FCast, scrcpy, KDE Connect |
| `68-nomad.just` | 441 | 21 | NOMAD, llama, VRAM, firewall |
| `69-audit.just` | 313 | 3 | `boot-audit`, `ports-audit`, `security-audit` |
| `70-aistudio-visual.just` | 523 | 23 | ComfyUI |
| `71-aistudio-audio.just` | 242 | 12 | VoiceStudio |
| `72-agent-mesh.just` | 662 | 42 | SearXNG, Vane, Tor, I2P, Trawl, Recoll, Lightpanda |
| `95-bazzite-dx.just` | 350 | 7 | **fork** do arquivo de 139 linhas do `bazzite-dx` |

### 1.5 Estado declarado

- **kargs (7):** `vconsole.keymap=br`, `kvm_intel.nested=1`, `kvm.ignore_msrs=1`,
  `kvm.report_ignored_msrs=0`, `intel_iommu=on`, `iommu=pt`, `nvidia-drm.modeset=1`.
- **systemd habilitado:** 16 unidades de sistema (`ublue-nvctk-cdi`, `cockpit.socket`,
  `docker.socket`, `podman.socket`, `uupd.timer`, `pmcd/pmlogger/pmproxy`,
  `virt*qemu/network/storage/nodedev` sockets, `swtpm-workaround`, `bazzite-dx-groups`,
  `input-remapper`) + 1 de usuário (`ublue-user-setup`).
- **mascarado:** `thermald.service`.
- **Assets opt-in:** 12 user units, 17 Quadlets, 7 hooks `user-setup`, 6 CIL, 13 overrides Flatpak.
- **`dx-verify`:** 196 asserts (152 `file`, 14 `bin`, 10 `unit`, 10 `group`, 5 `content`, 2 `nocontent`, 1 `target`, 1 `nostage`, 1 `desktop`).

---

## 2. Comparação entre as imagens da família

| Aspecto | `bazzite` | `bazzite-dx` | `bluefin` (dx) | `image-template` | `silver-goggles` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Build | Containerfile + `build_files/*.sh` | Containerfile + `build_files/*.sh` | Containerfile + composição de OCI layers | Containerfile + `build.sh` | **BlueBuild recipe v1** |
| Base | Fedora/uBlue | `bazzite-deck*` | `ublue-os/silverblue-main` + `projectbluefin/common` + `brew` | `bazzite:stable` | `bazzite-nvidia` |
| Seleção de variante | matriz de base | matriz de base (4, **todas deck**) | **build arg** `IMAGE_FLAVOR=dx` | — | repo separado, fixo |
| Como o DX é empacotado | — | `20-install-apps.sh` (116 linhas) | `00-dx.sh` (**145 linhas**) | — | 72 pacotes YAML + 687 linhas de módulos |
| Arquivos próprios | muitos | **23** | **10** (dx) | 0 | **227** |
| Superfície `ujust` própria | 22 arquivos | 2 arquivos | alguns | 0 | **8 arquivos / 3.972 linhas** |
| Verificação | lint + testes org | — | `01-tests-dx.sh` (34 linhas) | `bootc container lint` | `dx-verify` (196 asserts) |
| Política de boot | jogos+dev, serviços fixos | reabilita `tuned`, `uupd`, `input-remapper` | — | — | tudo opt-in fora tailscale/sunshine |

### 2.1 O que isso revela

1. **O `bazzite-dx` mudou de natureza.** Hoje ele é construído a partir de
   `bazzite-deck*` e só publica variantes deck (`bazzite-dx`, `-gnome`,
   `-nvidia`, `-nvidia-gnome`). Não existe mais um `bazzite-dx` desktop comum.
   O `silver-goggles`, que builda de `bazzite-nvidia`, **é na prática o ramo
   desktop do DX** — não um filho dele.
2. **Ninguém mais usa BlueBuild recipes** no conjunto (bazzite, bazzite-dx,
   image-template, bluefin). O `blue-build/cli` segue mantido (último commit
   2026-11-03), mas não é o toolchain que a base testa.
3. **`bluefin` resolveu o mesmo problema com build arg.** DX = 145 linhas de
   script + 10 arquivos, dentro do mesmo repositório, atrás de `IMAGE_FLAVOR=dx`.
   É a referência mais enxuta para "DX como camada, não como imagem".
4. **`projectbluefin/common`** mostra o mecanismo de composição: um OCI layer com
   `system_files/shared` + `system_files/<variante>` (251 arquivos) consumido por
   `COPY --from=common`. É o precedente direto para extrair um "common" pessoal.

---

## 3. Achados concretos (com evidência)

| # | Achado | Evidência |
| :-- | :--- | :--- |
| F1 | Toolchain isolado: único repo da família em recipe v1 | `recipes/*.yml` vs `Containerfile` em todos os outros |
| F2 | 7 arquivos são forks de arquivos do `bazzite-dx`, **todos divergentes** | `Code/User/settings.json`, `gamemode-nested`, `bazzite-dx-groups`, `bazzite-dx-kvmfr-setup`, `bazzite-dx-groups.service`, `blocklist-dx.yaml`, `84-bazzite-virt.just` |
| F3 | `84-bazzite-virt.just` existe **três vezes** na família (bazzite 87 linhas, bazzite-dx 195, local 24 que delega a um script de 13 KB) | o local sobrescreve o do base |
| F4 | `95-bazzite-dx.just` é fork de 350 linhas de um arquivo de 139; adiciona `dx-doctor`, `dx-workspace-*`, `dx-group sync`, `setup-default-brew` | diff completo contra upstream |
| F5 | `dx-verify` é o maior hotspot de manutenção: **74 commits em 2026** (mais que qualquer outro arquivo) | `git log --since=2026-01-01 --name-only` |
| F6 | 4 asserts apontam para arquivos gerados no build (`docker.socket`, `podman.socket`, `99-dx-flavor.preset`, `cockpit/ctop/manifest.json`), não para a árvore | verificação estática |
| F7 | `ublue-nvctk-cdi.service` é habilitado pelo `recipe`, mas o `bazzite-nvidia` já traz o symlink em `usr/etc/systemd/system/multi-user.target.wants/` (medido; ver `AGENTS.md`, seção `/etc` 3-way merge) | `recipes/silver-goggles.yml` + `ostree admin config-diff` |
| F8 | **Path do usuário hardcoded em script de runtime** | `usr/libexec/bazzite-dx-remote-wake-watcher:15-16` contém `/var/home/cloud/dev/personal/os/bazzite-dx-silver-goggles/files/system/usr/bin/bazzite-dx-display-wake` |
| F9 | Conteúdo pessoal no layer base: `xp_bliss.jpg` (2,4 MB), `bling.*` (22 KB), 6 Brewfiles, 4× keybindings idênticos, `starship`/`atuin`/`tealdeer`, overrides de 13 Flatpaks | `files/system/...` |
| F10 | Quatro stacks de container coexistem sem flag de opt-in | `dx.yml` (moby, podman, incus, lxc) |
| F11 | Nomes de terceiros herdados de outro template | `etc/systemd/resolved.conf.d/00-amyos-dns.conf`, `NetworkManager/conf.d/00-amyos-random-mac.conf` |
| F12 | Nada duplica pacotes do `bazzite` base, mas 18/64 duplicam o `bazzite-dx` — o custo é **conceitual** (reimplementamos o DX), não de bytes | comparação de listas |

---

## 4. Invariantes que o desenho novo tem que respeitar

1. **Hardware primeiro.** G15 5520: `alienware-wmi-wmax`, `g15-boost`, `gpu-unlock`
   (kmod assinado + MOK), `udisks-ignore-root`, mask do `thermald`. Nada disso é
   opcional e nada disso existe em outra imagem.
2. **Nada habilitado no boot por padrão** além de `tailscale`/`sunshine` (que o
   upstream liga pelo `ujust`). `nomad.yml`/`casting.yml` não podem ganhar
   `systemd: enabled:`.
3. **`/usr` declarativo, `/etc` só semeado.** Quadlets rootless continuam em
   `/etc/containers/systemd/users/` (única exceção estrutural, já documentada).
4. **Units de usuário em `/usr/lib/systemd/user/`**, nunca copiadas para `$HOME`.
5. **Superfície de rede:** loopback + `tailscale serve`; nunca `0.0.0.0`, nunca 80/443.
6. **Expansão do dono sem acoplar o base.** O que é escolha pessoal (shell, Brewfiles,
   IDEs, wallpaper) tem que poder ser trocado sem rebuild da camada de hardware.

---

## 5. Arquitetura-alvo proposta (rascunho para decisão)

### 5.1 Camadas

```
L0  upstream        ghcr.io/ublue-os/bazzite-nvidia           (não forkamos)
L1  hardware        Dell G15 5520: kargs, g15-*, gpu-unlock,
                    udisks guard, thermald mask, sensors      ~30 arquivos
L2  dx-core         engines, virt, cockpit, observabilidade,
                    remote IDE, audit, groups                 ~60 arquivos
L3  dx-profiles     nomad | aistudio | mesh | casting         opt-in por manifest
L4  persona         shell bling, Brewfiles, IDEs, wallpaper,
                    keybindings, dotfiles                     ~50 arquivos
```

`L1` e `L2` são a imagem publicada. `L3` são perfis que só adicionam assets e
receitas (nada liga no boot). `L4` é uma imagem **separada** (`FROM silver-goggles`)
ou um pacote de dotfiles aplicado por hook idempotente — nunca `/etc/skel` do base.

### 5.2 Mecanismo de composição

- Um único manifesto `profiles.yml` (ou `dx.toml`) lista:
  `hardware: [g15]`, `dx: [core, remote]`, `optional: [nomad, mesh]`, `persona: false`.
- `scripts/generate-recipe.sh` (já existe) passa a gerar o recipe **e** o
  `system_files` por perfil, a partir de `overlays/<perfil>/{files,just,units}`.
- Cada perfil é uma pasta autocontida: `overlays/mesh/{files,just,verify}`. Some e
  volta sem tocar nos outros; `dx-verify` passa a ler o assert de cada perfil em vez
  de um registro único de 196 entradas.

### 5.3 Duas escolhas estruturais em aberto

| Decisão | Opção A | Opção B |
| :--- | :--- | :--- |
| Toolchain | manter BlueBuild recipe (menos trabalho agora, único na família) | migrar para Containerfile + `build_files/NN-*.sh` como bazzite/bazzite-dx/bluefin (alinha com o que a base testa; `dx-flavor`/`dx-hardening` viram scripts numerados) |
| Relação com `bazzite-dx` | manter fork (somos o ramo desktop) | propor upstream de uma variante desktop ao `bazzite-dx` e consumir o que ele já entrega |

### 5.4 O que some, o que fica

- **Sai:** fork do `95-bazzite-dx.just` (adota upstream + um `96-*.just` só com o que é
  nosso), fork do `84-bazzite-virt.just` (upstream + script próprio chamado por ele),
  declaração redundante de `ublue-nvctk-cdi`, path hardcoded do F8.
- **Fica:** hardware G15 inteiro, `dx-verify` reduzido a contratos por perfil,
  `69-audit.just`, receitas remote/AI (como perfis), política opt-in.

---

## 6. Sequência sugerida

> Contexto externo que sustenta essas escolhas: `docs/TRENDS-2026-2027.md`
> (bootc/CNCF, sealed images, composição por camadas, encolhimento da base,
> BlueBuild como ponte, agentes de IA no fluxo de dev).

1. **P0 — nada muda:** este catálogo + um job de CI que roda `bootc container lint`
   e `systemd-analyze verify` nos assets (hoje só `dx-verify` faz, no build).
2. **P1 — reorganização sem mudança de comportamento:** `overlays/<perfil>/…`,
   `generate-recipe.sh` lê o manifesto, asserts migram junto. Build tem que sair
   idêntico (mesmo `rpm -qa`, mesmos arquivos).
3. **P2 — remover forks e duplicatas** (F2, F3, F4, F7, F8, F11).
4. **P3 — separar persona** (F9) em imagem/hook separado.
5. **P4 — decidir toolchain** (5.3) e, se for o caso, reduzir `dx-verify` a contratos.
