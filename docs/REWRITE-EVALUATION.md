# Avaliação da reescrita: alternativas, não uma escolha

> Contexto do dono: imagem pessoal para um G15 5520, base Bazzite, DX como
> plataforma para rodar qualquer coisa (dev, jogos, LLM local). Não é imagem
> generalizada. Nada do que existe hoje pode ser perdido.
>
> Este documento compara **quatro decisões independentes** com critérios
> explícitos, para não repetir a decisão de 2026 (escolher BlueBuild por parecer
> "mais declarativo" sem comparar com o que o upstream mantém).

## 1. Requisitos que qualquer opção precisa satisfazer

| # | Requisito | Como se verifica |
| :-- | :--- | :--- |
| R1 | Pessoal, não genérica | não precisa suportar outra máquina; pode assumir G15 |
| R2 | Hardware completo | kargs, thermals, RGB, GPU unlock, udisks guard, sensores |
| R3 | **Nenhuma capacidade perdida** | checklist da §7 item por item |
| R4 | DX como plataforma | dev, jogos e LLM rodando no mesmo host |
| R5 | Futuro 2026/2027 | bootc/composefs, teste em VM, atualização em dias |
| R6 | Simples e declarativo | adicionar capacidade = 1 pasta/1 linha; zero DSL própria |
| R7 | Não repetir erros do histórico | sem fork de upstream, sem registro crescente, sem feature efêmera no host |

## 2. Critérios e pesos

| Critério | Peso | Por que |
| :--- | ---: | :--- |
| Alinhamento com upstream/futuro | 30 % | F45 já quebrou um módulo nosso; a base define o toolchain |
| Custo de manutenção anual | 25 % | 620 commits em 8 meses, 39 % de dependências |
| Preservação de capacidade | 20 % | requisito explícito do dono |
| Tempo até o primeiro build verde | 15 % | risco de ficar sem atualização durante a migração |
| Legibilidade/declaratividade | 10 % | "declarativo" é meio, não fim |

As notas são julgamento informado por evidência, não medida. Onde há medida, está citada.

## 3. Decisão A — toolchain de build

| Opção | Descrição | Alinhamento | Manutenção | Capacidade | Tempo | Legibilidade | **Total** |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| A1 | BlueBuild recipe (atual) | 2,0 | 3,0 | 4,0 | **5,0** | 3,0 | **3,05** |
| A2 | `Containerfile` + `build_files/NN-*.sh` | **5,0** | **4,5** | 4,5 | 2,0 | **5,0** | **4,38** |
| A3 | Híbrido: `Containerfile` + módulos BlueBuild dentro dele | 3,5 | 3,0 | 4,5 | 4,0 | 3,5 | **3,65** |
| A4 | `bootc image build` nativo | 4,5 | 3,5 | 3,0 | 2,0 | 4,0 | **3,53** |

Evidência que pesa:

- **A1 já falhou em produção**: no F45, `rpm-ostree install` retorna
  `This system was not booted via libostree` porque a base virou composefs. O
  módulo não tem substituto dentro do BlueBuild além de trocar por `dnf`.
- **A2 é o padrão dos quatro repositórios da família** (`bazzite`, `bazzite-dx`,
  `bluefin`, `image-template`). O próprio `image-template`, que é a recomendação
  oficial da uBlue para imagens customizadas, é Containerfile.
- **A3 existe de verdade** (documentado pelo BlueBuild como "módulos a partir de
  Containerfile") e serve como ponte, não como destino: mantém a abstração que
  causou o problema.
- **A4** (`bootc image build`) aparece em material de 2026, mas ainda não é o
  caminho usado pelas imagens que servem de base. Não apostar sem ver ADR.

**Recomendação: A2**, com A3 como ponte opcional se algum módulo for difícil de
portar (ex.: `justfiles`, que é só copiar arquivo).

## 4. Decisão B — composição

| Opção | Descrição | Alinhamento | Manutenção | Capacidade | Tempo | Legibilidade | **Total** |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| B1 | Um repo, uma imagem, tudo inerte | 4,0 | **4,5** | **5,0** | **5,0** | **5,0** | **4,63** |
| B2 | Camada OCI `common` + imagem | 5,0 | 3,0 | 5,0 | 2,5 | 3,5 | **3,90** |
| B3 | Matriz de perfis (`dev`/`play`/`llm`) | 3,5 | 2,5 | 4,0 | 2,0 | 2,5 | **3,00** |
| B4 | Imagem de persona separada | 3,0 | 2,0 | 4,0 | 2,0 | 3,0 | **2,80** |

- B2 é o padrão Bluefin e é ótimo **quando existem duas imagens**. Aqui existe
  uma. Criar uma camada comum para um consumidor é custo sem retorno.
- B3 contradiz R1 (pessoal) e o histórico (features com vida de 48 h): matriz de
  perfis para uma máquina é abstração sem uso.
- B4 já foi decidido contra: dotfiles resolvem, e o CI impede vazamento.

**Recomendação: B1.** Se um dia surgir uma segunda máquina ou uma variante, B2
passa a valer — a estrutura de pastas de B1 prepara isso sem custo.

## 5. Decisão C — onde cada capacidade vive

Não é escolha única; é uma **política**. A regra que preserva capacidade sem
inflar a imagem:

| Tipo de coisa | Onde vive | Por quê |
| :--- | :--- | :--- |
| Hardware (kargs, kmod, udev, thermal) | **imagem** | não há como existir fora |
| Motor (podman, libvirt, uxplay, sunshine) | **imagem** | precisa antes do login/sessão |
| **Runtime alternativo** (moby além de podman, incus/lxc além de libvirt) | **imagem** | alternativa é capacidade; DX é poder escolher |
| Servidor/stack (NOMAD, mesh, aistudio, guacamole) | **container rootless (Quadlet)** | sobreviveu ao histórico; atualiza independente |
| App com GUI (FCast, navegador, RustDesk) | **Flatpak / Brew** | ciclo próprio de update |
| Ferramenta de projeto (node, python, rust, CLIs) | **mise/uv/brew** | não deve arrastar rebuild |
| Preferência (shell, tema, keybinding) | **dotfiles / `skel`** | muda mais que hardware |

Regra de convivência: **um dono por função, sem shim**. Moby e Podman coexistem
porque são alternativas explícitas — `docker` é o CLI do Moby, `podman` é o
Podman, e `podman-docker` não entra porque tornaria o comando ambíguo. O mesmo
vale para libvirt/incus/lxc/cloud-hypervisor: são opções, não duplicatas.

Teste rápido para qualquer item futuro: *"isso precisa existir antes do login do
usuário?"* Se não, não entra. **Não** vale como teste: *"já temos um runtime
parecido?"* — parecido não é igual.

## 6. Decisão D — verificação e atualização

| Opção | Manutenção | Cobertura | **Total** |
| :--- | ---: | ---: | ---: |
| D1 · `dx-verify` com 196 asserts (atual) | 1,5 | 3,0 (presença, não comportamento) | **2,10** |
| D2 · `bootc container lint` + `systemd-analyze` + listas curtas por domínio | 4,5 | 3,5 | **4,05** |
| D3 · D2 + boot em VM (`bcvk`) por release | 4,0 | **5,0** | **4,45** |

Atualização: **PR automático + merge manual** (decidido em 2026-11-08), com alerta
de lag > 14 dias. Auto-merge só depois de D3.

## 7. Checklist de não-regressão (R3)

Tudo que existe hoje e para onde vai. Nada é removido; o que muda é a camada.

| Capacidade | Hoje | Destino |
| :--- | :--- | :--- |
| g15-profile, g15-status, sensores, v4l2loopback, udisks guard, RGB | imagem | **imagem** (L1) |
| GPU unlock (kmod assinado, MOK) | imagem + CI | **imagem** (L1) |
| kargs (IOMMU, nested, modeset) | recipe | **`build_files`** (via `bootc`/kargs) |
| Autologin, lock-on-session, VT guard | imagem | **imagem** |
| Cockpit (+ porta 61390) | imagem + just | **imagem** |
| Sunshine (multi-monitor, LAN, boot) | imagem + just | **imagem** (motor) |
| RustDesk, Guacamole, MediaMTX, webcam receiver | imagem + just | **container/Flatpak + just** |
| code-server, ide-tunnel, remote-ide-setup | imagem + just | **imagem** (motor) |
| `remote-suite` (tailscale serve) | imagem | **imagem** |
| Virtualização (libvirt, incus, qemu, cloud-hypervisor, templates, win/macos utils, VFIO, KVMFR, Looking Glass) | imagem + just | **imagem**; todos mantidos como alternativas funcionais |
| Podman + Quadlets rootless | imagem | **imagem** |
| Moby/containerd/docker-* **como alternativa ao Podman** | imagem | **mantidos**; sem `podman-docker`, para `docker` continuar sendo o Docker |
| Virtualização alternativa (incus, lxc, cloud-hypervisor) | imagem | **mantidos**; cada um com seu CLI, nenhum alias |
| Observabilidade (bpf, pcp, sysprof, tiptop, wireshark, nmap) | imagem | **imagem** (diagnóstico) |
| NOMAD (Command Center, mysql, redis, llama-swap) | Quadlets | **inalterado** |
| llama-* (models-fetch, fit, which, advisor, vram-purge) | just | **inalterado** |
| AI Studio visual + áudio | Quadlets + just | **inalterado** |
| Agent Mesh (searxng, vane, tor, i2p, trawl, recoll, lightpanda) | Quadlets + just | **inalterado** |
| Casting (AirPlay, FCast, scrcpy, KDE Connect) | imagem + Flatpak | **inalterado** |
| KRunner workspaces, bling, aliases, starship/atuin, Brewfiles | imagem/`skel` | **inalterado por ora** (persona) |
| Privacidade (DoT, MAC random, telemetria off), SELinux CIL, zram | imagem | **imagem** |
| `ujust` audits (boot/ports/security) | just | **inalterado** |
| `dx-verify` por domínio | módulo | **`build_files/50-verify.sh` + bcvk** |

Isso responde ao "não limitar nada": a lista é o contrato. A migração só termina
quando cada linha tiver destino verificado.

## 8. Plano por fases (cada uma reversível)

| Fase | Entrega | Prova de não-regressão |
| :--- | :--- | :--- |
| **0** | F45 + dnf5 (PR #181) | build verde no CI |
| **1** | `Containerfile` + `build_files` reproduzindo o recipe atual | `rpm -qa \| sort` e `find /usr /etc` idênticos aos do build anterior |
| **2** | Poda de duplicata e fork: `84`/`95`, path `/var/home/cloud`, nomes `amyos`. Nenhum runtime alternativo é removido | checklist §7 + coexistência dos engines verificada |
| **3** | `bootc container lint` + `bcvk` + `ujust dx-metrics` | boot em VM no CI |
| **4** | Persona fora do caminho crítico (opcional, só se o churn justificar) | rebuild de shell sem rebuild de imagem |

## 9. Riscos e mitigação

| Risco | Probabilidade | Mitigação |
| :--- | :--- | :--- |
| Perder capacidade na fase 1 | média | diff de `rpm -qa` + lista de arquivos + checklist §7 |
| F45 composefs quebrar outro módulo | alta (já quebrou `rpm-ostree`) | converter para dnf agora; validar kargs/initramfs |
| `gpu_unlock` não compilar no kernel 7.3 | média | `kmod-sign` já builda contra o digest pinado; fail-soft |
| Build lento no CI | alta | cache de camadas + `--mount=type=cache` no Containerfile |
| Migração parar no meio | média | cada fase é um PR que deixa o repo verde |

## 10. O que ainda precisa de pesquisa antes da fase 2

1. `bootc image build` nativo: existe, é estável, substitui Containerfile? (não
   antes de ADR do projeto).
2. `nvidia-open` + `gpu_unlock`: exige build real (ver
   `INVESTIGATION-F45-NVIDIA-OPEN.md`).
3. Devcontainers: `podman-docker` cobre `docker.sock` para VS Code/Cursor, ou
   algum workload exige Docker Engine de verdade?
4. `kargs`/`initramfs` no BlueBuild dependem de libostree? (se sim, antecipar a
   fase 1).
