# O que é o dx-silver-goggles

> Documento definitivo. Substitui as propostas anteriores deste diretório.
> Evidência medida: `ARCHITECTURE-CATALOG.md`. Log de decisão: `BRAINSTORM-DECISIONS.md`.

## 1. Definição

**Uma imagem OCI que estende o Bazzite com três responsabilidades e nenhuma a mais:**

1. **Habilitar o hardware** — Dell G15 5520: perfil térmico, RGB, GPU unlock
   assinado, guarda do disco raiz, sensores.
2. **Empacotar motores** — o que precisa existir no sistema para desenvolver,
   jogar e rodar LLM local. Não ferramentas de projeto: motores.
3. **Ergonomia** — atalhos, receitas `ujust`, integração de desktop.

**Não é**: um fork do Bazzite, uma distro, um framework de imagens, nem uma
reimplementação do `bazzite-dx` (que hoje só publica variantes deck).

## 2. Regra de decisão: entra ou não entra na imagem

| Pergunta | Entra | Não entra |
| :--- | :--- | :--- |
| Precisa de root/kernel/driver? | sim (kargs, kmod, udev, systemd) | — |
| Precisa existir antes do login? | sim (serviço, motor, integração de sessão) | — |
| É ferramenta de projeto (Node, Python, Rust, CLI qualquer)? | — | `mise` / `uv` / `brew` |
| Tem GUI própria e ciclo de update semanal? | — | Flatpak |
| É preferência pessoal (tema, shell, fonte, dotfile)? | — | dotfiles, ou `/etc/skel` se precisar de default |
| Só um projeto usa? | — | container do projeto (distrobox/devcontainer) |

Corolário: **a imagem encolhe por padrão**. Se algo novo não passa nas três
primeiras linhas, não entra. Isso é o oposto de "adicionar capacidade", e é o que
mantém a camada simples.

## 3. Princípios de plataforma (Silverblue/Bazzite, 2026)

Estas são as regras que o sistema impõe, não escolhas de estilo:

| Princípio | Consequência prática |
| :--- | :--- |
| `/usr` é declarativo e imutável | tudo que é estado de imagem mora em `/usr`; nunca em `/etc` |
| `/etc` é semeado uma vez e o merge local vence para sempre | `/etc` só para o que *precisa* ser editável pelo admin; hoje temos 26 arquivos lá, todos candidatos a revisão |
| `systemctl enable` em build escreve em `/usr/etc` | preferir `preset` ou symlink declarado; o módulo do BlueBuild chama `systemctl` direto e por isso divergiu do preset |
| Units de usuário vivem em `/usr/lib/systemd/user/` | ativar por symlink de target; nunca copiar para `$HOME` (mascara a imagem) |
| `rpm-ostree initramfs` desligado | o initramfs é o do build; `gpu_unlock` depende disso |
| Imagem = OCI; update = rebase | nada de script de "primeiro boot" que instala pacote |

## 4. Padrões que copiamos (não inventamos)

| Padrão | De onde vem | Como aparece aqui |
| :--- | :--- | :--- |
| `Containerfile` + `build_files/NN-*.sh` numerados | `bazzite`, `bazzite-dx`, `bluefin`, `image-template` | build inteiro em 5–6 scripts legíveis, sem DSL própria |
| `system_files/` espelhando `/` | todos os projetos uBlue | overlay idêntico ao do upstream, `cp -a` |
| Variante por build arg (`IMAGE_FLAVOR=dx`) | `bluefin` | não precisamos: imagem única |
| Apps saem da imagem e entram por Portal/Brew | Bazzite removendo Sunshine (2026) | nada de app GUI no build |
| Serviço empacotado inerte + `ujust ...-up` | Bazzite e este repo | sem `systemd: enabled` fora das duas exceções |
| `bootc container lint` + boot em VM (`bcvk`) | `image-template`, bootc 2026 | substitui asserts estáticos frágeis |
| Toolchain fora do host | prática 2026 (distrobox/mise) | `mise`, `uv`, `brew`, containers |

O BlueBuild continua mantido e agora sabe usar módulos dentro de um Containerfile,
mas não é o toolchain que a base testa. Migrar é alinhamento, não moda.

## 5. Layout alvo

```
Containerfile                  # FROM base pinada, RUN build.sh, bootc container lint
image-versions.yaml            # pin + digest (Renovate)
build_files/
  build.sh                     # roda os NN-*.sh em ordem
  00-image-info.sh
  10-packages.sh               # lê packages/*.txt
  20-services.sh               # presets/symlinks; sem enable imperativo
  30-hardware.sh               # g15: kargs (bootc), udev, mask thermald
  40-branding.sh               # os-release, kdm about, bazaar blocklist
  50-verify.sh                 # asserts curtos (ver §7)
  90-cleanup.sh                # repos transitórios, cache, /var/roothome
packages/
  hardware.txt                 # 3 pacotes
  dx-core.txt                  # containers (um só engine), cockpit, bpf, virt
  llm.txt                      # nada por enquanto: NOMAD é container, não rpm
system_files/                  # espelha /
  usr/lib/systemd/user/…       # units inertes
  usr/libexec/…                # helpers
  etc/containers/systemd/users/…  # Quadlets rootless (exceção documentada)
just/
  66-hardware.just  67-remote.just  68-llm.just  69-audit.just
```

Regras do layout:

- **Pacote em `.txt`, um por domínio.** Diff de PR mostra o que entrou/saiu sem
  ler YAML.
- **Nada de schema próprio.** Arquivo de pacote é lista; overlay é árvore; receita
  é `just`. Três formatos que qualquer pessoa já sabe ler.
- **Um `just` por domínio**, não por feature. Se um domínio precisa de mais de
  ~150 linhas, é sinal de que a feature virou produto e deve sair.
- **Adicionar capacidade** = 1 linha no `.txt` (se rpm) ou 1 pasta no overlay +
  1 receita. **Remover** = apagar a pasta. Nada mais.

## 6. O que não vamos construir

1. **Schema de capacidade / gerador de recipe.** Foi proposta minha e é
   overengineering para 6 stacks.
2. **Daemon de arbitragem.** A política é uma constante lida pelos ganchos que já
   existem (ordem Jogos > Dev > LLM).
3. **Matriz de perfis (`dev|play|llm`).** Uma imagem, tudo inerte, ativação por
   `ujust`. Economia de bytes não paga a complexidade de build.
4. **Imagem de persona.** Dotfiles resolvem; CI impede caminho de usuário no overlay.
5. **Fork de `84-bazzite-virt.just` / `95-bazzite-dx.just`.** Adotar upstream e
   complementar em `96-*.just`.

## 7. Verificação proporcional ao risco

| Camada | Verificação | Custo |
| :--- | :--- | :--- |
| Build | `bootc container lint` | grátis |
| Units | `systemd-analyze verify` (grep na saída) | baixo |
| Assets | lista curta por domínio (`file|`, `unit|`) | baixo |
| Comportamento | boot em VM (`bcvk`) no CI, smoke de sessão | médio, 1× por release |
| Frescor | `ujust dx-metrics`: versão base, dias de lag, units ativas, idle RPM/VRAM | baixo |

O que morre: o registro de 196 asserts com 74 commits no ano. Fica o que falha de
verdade e um boot real.

## 8. Migração em três passos, sem mudança de comportamento

1. **Containerfile + build_files** reproduzindo exatamente o recipe atual. Prova:
   mesmo `rpm -qa | sort` e mesmo `find /usr /etc` do build anterior.
2. **Remover dívida**: forks `84`/`95`, declaração redundante de `nvctk-cdi`,
   path `/var/home/cloud` em script de runtime, nomes `amyos`, quatro engines de
   container → uma.
3. **CI proporcional**: `bootc container lint` + `bcvk` + `dx-metrics` como
   baseline versionado.

Cada passo é um PR reversível. Nenhum exige mudar o que o usuário vê.

## 9. Critério de sucesso

A camada é simples se, daqui a um ano:

- adicionar uma capacidade custou **1 pasta** e nenhum arquivo compartilhado;
- nenhum arquivo nosso é fork de arquivo upstream;
- o PR de bump de base tem **diff de 3 linhas** e merge em 1 dia;
- `ujust dx-metrics` responde "quantos dias atrás" e "o que está ligado" sem
  precisar abrir o repositório.
