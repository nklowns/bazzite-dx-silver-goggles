# AWCC Build Process

O **AWCC** (Alienware Command Center Companion) é um software open-source de controle de hardware para notebooks Dell/Alienware no Linux. Ele fornece:

- Controle de fans e G-Mode
- Modos de performance
- Efeitos de iluminação RGB

| Repositório | Papel |
|---|---|
| [`tr1xem/AWCC`](https://github.com/tr1xem/AWCC) | Upstream estável (padrão) |
| [`nklowns/AWCC`](https://github.com/nklowns/AWCC) | Fork pessoal (features experimentais) |

---

## 📦 RPM Canônico (`files/rpm-ostree/awcc-dev.rpm`)

O arquivo `files/rpm-ostree/awcc-dev.rpm` é o **binário canônico** usado durante o build da imagem. Ele é:

- Compilado via `just build-awcc` usando o spec ativo (`AWCC_SPEC`)
- Comprometido diretamente no git (exceção no `.gitignore` via `!files/rpm-ostree/awcc-dev.rpm`)
- Instalado em tempo de build nativamente via módulo `rpm-ostree` no `recipe.yml`

> **Por que comprometer o RPM?**
> O BlueBuild não suporta multi-stage builds. Em vez de compilar o AWCC em tempo de CI (lento e frágil), o binário é pré-compilado e comprometido. Este é o mesmo padrão usado por projetos como o `winblues7`.

### Dois Spec Files

| Arquivo | Propósito | Padrão? |
|---|---|---|
| `build_files/awcc.spec` | Release estável via tag `vX.Y.Z` do upstream `tr1xem/AWCC` | ✅ **Principal** |
| `build_files/awcc.dev.spec` | Build de commit específico do fork pessoal `nklowns/AWCC` | Experimental |

O spec ativo é controlado pela variável `AWCC_SPEC` (default: `awcc.spec`).

---

## 🔄 Como Atualizar o AWCC

### 1. Compilar o RPM

O target `just build-awcc` é **dual**: opera em modo estável ou local dependendo do argumento.

```bash
# Modo estável (padrão) — baixa tarball do upstream tr1xem/AWCC conforme awcc.spec:
just build-awcc 2>&1 | tee output/build-awcc.log

# Modo dev — compila a partir de source local do fork nklowns/AWCC:
just build-awcc ~/dev/linux/uBlueOs/dell_related/AWCC 2>&1 | tee output/build-awcc-dev.log

# Usando o spec de dev explicitamente:
AWCC_SPEC=awcc.dev.spec just build-awcc ~/dev/linux/uBlueOs/dell_related/AWCC 2>&1 | tee output/build-awcc-dev.log
```

O RPM resultante é salvo em `files/rpm-ostree/awcc-dev.rpm` automaticamente.

### 2. Atualizar a versão estável

Edite `build_files/awcc.spec` com a nova tag upstream:

```diff
- Version: 1.17.0
+ Version: <nova-versao>
```

A `Source0` busca automaticamente `https://github.com/tr1xem/AWCC/archive/refs/tags/v%{version}.tar.gz`.

### 3. Comprometer o novo binário

```bash
git add -f files/rpm-ostree/awcc-dev.rpm
git commit -m "chore(awcc): update to v<versao>"
```

---

## 🏗️ Processo de Build Interno

O `just build-awcc` executa um container `fedora:43` efêmero com:

1. Instalação das dependências de build (`cmake`, `meson`, `ninja`, libs de sistema)
2. **Modo local**: adapta o spec para usar source local (sem fetch de URL), empacota em tarball, injeta versão `dev.local`
3. **Modo estável**: baixa o tarball via `spectool` direto do GitHub e compila sem modificação
4. Copia o RPM resultante (sem debuginfo) para `files/rpm-ostree/awcc-dev.rpm`

### Dependências do Build

| Pacote | Razão |
|---|---|
| `cmake`, `ninja-build`, `meson` | Sistema de build do AWCC |
| `gcc-c++` | Compilação C++ |
| `libX11-devel`, `libxkbcommon-devel` | Input de teclado |
| `glfw-devel` | Janela OpenGL |
| `systemd-devel`, `libudev-devel` | Integração systemd/udev |
| `libglvnd-devel` | OpenGL vendor-neutral dispatch |
| `wayland-devel` | Suporte Wayland |

---

## 🔧 Arquivos de Configuração do Sistema

O AWCC usa os seguintes arquivos instalados via módulo `files` (em `files/system/`):

| Arquivo | Propósito |
|---|---|
| `usr/lib/tmpfiles.d/awcc.conf` | Cria `/var/lib/awcc` com permissões corretas |
| `usr/lib/systemd/system-preset/00-silver-goggles.preset` | Habilita `awccd.service` |
| `usr/share/polkit-1/rules.d/99-awcc.rules` | Permite controle de fans sem sudo |
| `etc/modules-load.d/acpi_call.conf` | Garante o módulo `acpi_call` no boot |

O mascaramento de `thermald.service` é gerenciado declarativamente no `recipe.yml` via módulo `systemd`.

---

## ♻️ Hot-Swap (Sem Rebuild da Imagem)

Para iterar no AWCC sem fazer full image build:

```bash
# Validar versão
rpm -qi awcc

# Build + apply live no sistema atual (sem reboot):
just hot-swap-awcc /path/to/AWCC-source

# Ou passo a passo:
just build-awcc /path/to/AWCC-source
just install-awcc

# Reverter:
just uninstall-awcc   # rpm-ostree apply-live --reset
```

---

## ⚠️ Compatibilidade

- **`thermald.service`** é **mascarado** intencionalmente (conflita com o driver de fans do AWCC)
- **`systemd-udev-settle.service`** é mascarado para estabilidade VFIO/IOMMU
- O kernel já inclui `acpi_call` in-tree no Bazzite (não precisa de DKMS)
