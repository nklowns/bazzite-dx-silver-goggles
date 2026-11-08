# Investigação: Fedora 45 e `bazzite-nvidia-open`

> Status: **investigação**, não decisão. Escrito em 2026-11-08, com dados do
> upstream local e do registry (`ghcr.io`) consultados na mesma data.

## 1. Pergunta

Vale trocar a base de `ghcr.io/ublue-os/bazzite-nvidia` (F44, pin
`44.20261026`) por `bazzite-nvidia-open` em Fedora 45?

São **duas mudanças independentes** empacotadas na mesma pergunta:

- **A**: Fedora 44 → 45.
- **B**: flavor `nvidia-lts` → `nvidia-open`.

Tratá-las como uma coisa só torna qualquer falha ambígua.

## 2. O que o upstream diz (verificável no clone local)

`bazzite/build.py` é a tabela canônica das variantes:

| Imagem | `nvidia_flavor` | `kernel_flavor` | Kernel |
| :--- | :--- | :--- | :--- |
| `bazzite-nvidia` | `nvidia-lts` | `ogc-lts` | `6.18.60-ogc1.1.fc45` |
| `bazzite-nvidia-open` | `nvidia-open` | `ogc` | `7.3.3-ogc1.1.fc45` |

`DEFAULTS.fedora_version = 45` — o `main` do Bazzite já builda F45. As duas
variantes usam a mesma base (`container_target: bazzite-nvidia`, `base_image_name:
kinoite`), então a diferença é **flavor de driver + série de kernel**, não desktop.

## 3. O que existe de fato no registry (2026-11-08)

| Imagem | Tag F45 | Digest | Criada |
| :--- | :--- | :--- | :--- |
| `bazzite` | `45.20261105` | — | 2026-11-05 |
| `bazzite-nvidia` | `45.20261105` | `sha256:1d86fe5e788d651827757cbcdb01b17b1b5727995c0691419d6136b28cd50c97` | 2026-11-05T23:05Z |
| `bazzite-nvidia-open` | `45.20261105` | `sha256:9c3c4df94a7731238021549ed3fc951c3ae5e1fee37667d16754f37ae0f73134` | 2026-11-05T23:02Z |

Detalhe que custa tempo se não souber: **a tag `:45` não existe**. O que existe é
`stable-45` e a tag datada `45.20261105` (`latest`/`stable` também apontam para ela).

Pin atual do repo: `44.20261026` / `sha256:4b5ba68…`. Ou seja, estamos **um release
de distro atrás**, sem risco de salto acidental porque a tag é explícita.

## 4. O que muda de verdade

### 4.1 Kernel: 6.18 LTS → 7.3 corrente

| Impacto | Detalhe |
| :--- | :--- |
| `gpu_unlock.ko` | `kmod-sign.yml` builda contra o **digest pinado**, então acompanha sozinho — mas o módulo precisa **compilar** contra 7.3 |
| akmods | `v4l2loopback`, `kvmfr`, `xone` etc. vêm do conjunto akmods da própria base; trocar o flavor troca o conjunto |
| `nvidia-drm.modeset=1` | karg existe por uma regressão da F44; revalidar na F45 antes de manter |
| NVIDIA + LTS | o `nvidia-lts` existe justamente para reduzir quebra de módulo out-of-tree. Sair dele é trocar estabilidade por kernel novo |

### 4.2 Driver: `nvidia-lts` → `nvidia-open`

- `nvidia-open` = kernel modules abertos (userspace proprietário). RTX 3060 Laptop
  (GA106M, Ampere) é Turing+ — **suportada**.
- O `gpu_unlock` (Zagitta/gpu-unlock, ref `990a14e9`) faz shim em cima do driver.
  Historicamente alvo do driver proprietário. **Não verificado** contra o layout do
  módulo aberto. Este é o risco número 1 da troca.
- Efeitos colaterais a checar: NVENC (Sunshine), PRIME offload, suspend/resume,
  `nvidia-persistenced` (temos drop-in de device nodes), HDMI.

### 4.3 Custo mecânico da troca de nome

`bazzite-nvidia` está hardcoded em **7 lugares**:

```
.github/workflows/build.yml:78          just generate-recipe "bazzite-nvidia" "latest"
.github/workflows/kmod-sign.yml:32      select(.name == "bazzite-nvidia") | .image + "@" + .digest
scripts/generate-recipe.sh:6            TARGET_IMAGE="${1:-bazzite-nvidia}"
just/build.just:7                       build target_image="bazzite-nvidia"
just/build.just:14                      build-nocache target_image="bazzite-nvidia"
just/build.just:30                      echo "…ghcr.io/{{ user }}/bazzite-nvidia:…"  (cosmético)
just/maint.just:29                      just generate-recipe "bazzite-nvidia" "latest"
```

Mais o `customManager` do Renovate, que casa por `name: <imagem>` em
`image-versions.yaml`.

## 5. Recomendação cética

**Não empacotar A e B.** Sequência:

1. **A primeiro** — bump F44 → F45 mantendo `bazzite-nvidia` (LTS).
   Uma variável só: se quebrar, é a distro.
2. **B depois**, em branch própria (`feat/nvidia-open`), com a mesma F45.
   Uma variável só: se quebrar, é o kernel/driver.
3. Só adotar B se o checklist abaixo passar **inteiro**; caso contrário voltar e
   registrar o porquê em `AGENTS.md`.

Justificativa de não fazer B só porque "é mais novo": o ganho real de `nvidia-open`
numa GA106M é quase nulo em recursos; o custo é perder o canal LTS de kernel e
mexer no `gpu_unlock`, que é o artefato mais frágil da imagem (kmod assinado com
MOK, `vermagic` exato, fail-soft).

## 6. Checklist de verificação (executável)

Antes de qualquer merge de B:

- [ ] `kmod-sign.yml` compila `gpu_unlock.ko` contra o kernel da candidata
      (`7.3.3-ogc1.1.fc45`) e `modinfo -F vermagic` casa exatamente.
- [ ] `ujust gpu-unlock-status` reporta ativo; BF16 disponível em `nvidia-smi`.
- [ ] `nvidia-smi` mostra o driver esperado; `nvidia-persistenced` sobe.
- [ ] `lsmod | grep -E 'nvidia|nvidia_drm|nvidia_modeset'` sem taint inesperado.
- [ ] HDMI externo funciona (regressão de `modeset` na F44).
- [ ] Suspend/resume com sessão Wayland.
- [ ] `v4l2loopback` cria `/dev/video9` (câmera virtual do OBS).
- [ ] `kvmfr` continua **mascarado** por padrão (`/etc/modules-load.d/kvmfr.conf` vazio).
- [ ] Sunshine: NVENC disponível, `/dev/uinput` ok, Web UI em `:61395`.
- [ ] Looking Glass client conecta no guest (o `.ko` do host é independente).
- [ ] Podman rootless + CDI NVIDIA (`/etc/cdi/nvidia.yaml` gerado).

## 7. O que não foi verificado

- Conteúdo real das imagens F45 (só digest/metadata; não puxamos layers).
- Compatibilidade do `gpu_unlock` com `nvidia-open` — exige build real.
- Se o `nvidia-drm.modeset=1` ainda é necessário (regressão documentada na F44).
- Se a remoção do Sunshine da base (ver `docs/TRENDS-2026-2027.md`, T5) já chegou
  na `45.20261105`.

## 8. Resultado do primeiro build: F45 é composefs-native

O PR #181 falhou no primeiro job de pacotes, com erro explícito:

```
error: This system was not booted via libostree.
Currently, most rpm-ostree commands only work on ostree-based host systems.
```

**Causa:** a mudança Fedora `ComposefsAtomicDesktops` habilita composefs por
padrão nas imagens **bootc** dos Atomic Desktops. Com raiz composefs, não existe
sysroot libostree para o `rpm-ostree install` operar — e o módulo `rpm-ostree` do
BlueBuild chama exatamente esse comando.

**Consequência:** o módulo `rpm-ostree` está morto para F45+. O substituto é o
módulo `dnf` (dnf5), que funciona em build de container independente do backend —
o mesmo caminho que `bazzite`, `bazzite-dx` e `bluefin` já usam nos respectivos
Containerfiles.

**O que foi feito:** os quatro módulos `rpm-ostree` (`dx.yml`, `casting.yml` ×2,
`silver-goggles.yml`) foram convertidos para `dnf`, com a mesma lista de pacotes e
o mesmo repo do cloud-hypervisor. `just check` passou.

**O que isso muda na conclusão:** a migração de toolchain deixou de ser preferência
arquitetural e virou **pré-requisito de update**. O bump F45 não é um diff de 3
linhas; ele força a primeira metade da migração (dnf5). A segunda metade —
Containerfile + `build_files` — passa a ser o caminho natural, não uma aposta.

**Fica em aberto:** se o F44 era ostree e o F45 composefs, confirmar pelo
`ostree admin status` num host F45, e verificar se algum outro módulo BlueBuild
depende de libostree (`kargs`, `initramfs`, `systemd` são candidatos).

