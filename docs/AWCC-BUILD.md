# AWCC Build Process

O **AWCC** (Alienware Command Center Companion) é um software open-source de controle de hardware para notebooks Dell/Alienware no Linux. Ele fornece:

- Controle de fans
- Modos de performance (G-Mode)
- Efeitos de iluminação RGB

**Repositório upstream:** [`nklowns/AWCC`](https://github.com/nklowns/AWCC)

---

## 📦 RPM Canônico (`files/awcc-dev.rpm`)

O arquivo `files/awcc-dev.rpm` na pasta `files/` é o **binário canônico** usado durante o build da imagem. Ele é:

- Compilado a partir da **tag de release estável** definida em `build_files/awcc.spec`
- Comprometido diretamente no git (exceção no `.gitignore` via `!files/awcc-dev.rpm`)
- Instalado em tempo de build pelo módulo `type: script` → `scripts/00-install-awcc.sh` (em `files/scripts/`)

> **Por que comprometer o RPM?**
> O BlueBuild não suporta multi-stage builds. Em vez de compilar o AWCC em tempo de CI (lento, frágil), optamos por pré-compilar e comprometer o binário. Este é o mesmo padrão usado por projetos como o `winblues7`.

### Dois Spec Files

| Arquivo | Propósito | Padrão? |
|---|---|---|
| `build_files/awcc.spec` | Release estável via tag `vX.Y.Z` do upstream `tr1xem/AWCC` | ✅ **Principal** |
| `build_files/awcc.dev.spec` | Build de commit específico do fork pessoal `nklowns/AWCC` | Experimental |

---

## 🔄 Como Atualizar o AWCC

Quando o upstream lançar uma nova versão:

### 1. Atualizar o spec file (release estável)

Edite `build_files/awcc.spec` com a nova tag upstream:
```diff
- Version: 1.17.0
+ Version: <nova-versao>
```
A `Source0` busca automaticamente `https://github.com/tr1xem/AWCC/archive/refs/tags/v%{version}.tar.gz`.

> **Usando a versão de desenvolvimento?**
> Para testar um commit específico do fork `nklowns/AWCC`, use `just build-awcc <src>`.

### 2. Recompilar o RPM

```bash
# Para a versão estável (padrão), o spec baixa o tarball automaticamente:
just build-awcc

# Para a versão dev (fork pessoal com source local):
just build-awcc /path/to/AWCC-source
```

### 3. Comprometer o novo binário

```bash
git add -f files/awcc-dev.rpm
git commit -m "chore(awcc): update to v<versao> (commit <sha-curto>)"
```

---

## 🏗️ Processo de Build Interno

O target `just build-awcc [source]` executa um container `fedora:43` efêmero com:

1. Instalação das dependências de build (`cmake`, `meson`, `ninja`, libs de sistema)
2. Adaptação do spec file para usar fonte local (sem fetch de URL)
3. Execução do `rpmbuild` em ambiente isolado
4. Cópia do RPM resultante para `files/awcc-dev.rpm` no repo

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
| `usr/lib/systemd/system-preset/00-silver-goggles.preset` | Habilita `awccd.service`, mascara `thermald.service` |
| `usr/share/polkit-1/rules.d/99-awcc.rules` | Permite controle de fans sem sudo |
| `etc/modules-load.d/acpi_call.conf` | Garante o módulo `acpi_call` no boot (controle de fans) |

---

## ⚠️ Compatibilidade

- **`thermald.service`** é **mascarado** intencionalmente (conflita com o driver de fans do AWCC)
- **`systemd-udev-settle.service`** é mascarado para estabilidade VFIO/IOMMU
- O kernel já inclui `acpi_call` in-tree no Bazzite (não precisa de DKMS)
