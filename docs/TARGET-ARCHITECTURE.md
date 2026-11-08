# Arquitetura-alvo: o que "melhor" significa aqui

> Este documento existe para impedir que a discussão vire "mais uma atualização".
> Atualizar a base é **pré-requisito**, não objetivo. O objetivo é uma camada DX
> pessoal que o upstream não pode entregar porque não conhece o hardware nem as
> três cargas que rodam nele.

## 1. Premissa

`bazzite-dx-silver-goggles` **não é** um fork do Bazzite nem um clone do
`bazzite-dx`. É uma camada de experiência em cima de uma base que já resolve
desktop, drivers e jogos.

O que só esta camada pode fazer:

1. **Saber que a máquina é um G15 5520** — 6 GB de VRAM, 64 GB de DDR5, fans
   controlados por `alienware-wmi-wmax`, GPU desbloqueada por kmod assinado.
2. **Arbitrar três cargas concorrentes no mesmo hardware**: desenvolvimento,
   jogos e LLM local. Nenhuma imagem upstream tenta isso, porque nenhuma sabe
   onde vai rodar.
3. **Frescor**: seguir a base em dias, não em trimestres.
4. **Extensão sem fork**: qualquer capacidade nova entra como camada, não como
   edição de arquivo compartilhado.

## 2. O que "melhor" significa, medido

"Melhor" sem número é opinião. Cinco critérios, com baseline atual:

| # | Critério | Como medir | Hoje | Alvo |
| :-- | :--- | :--- | :--- | :--- |
| C1 | **Frescor** | dias entre release upstream e rebase nosso | 3 dias (F45 saiu 2026-11-05, PR aberto 2026-11-08); F44 ficou 13 dias parado | ≤ 2 dias, automático |
| C2 | **Aderência ao hardware** | unidades ativas em idle + RPM/temp em idle | 16 system units + 1 user; fans 0 RPM a ~48 °C em `balanced` | não crescer sem justificativa; manter 0 RPM |
| C3 | **Arbitragem de GPU** | VRAM livre ao iniciar jogo com LLM carregado | resolvido por hooks dispersos (`gamemode.ini`, `ai-vram-purge`) | uma política única, auditável |
| C4 | **Extensibilidade** | arquivos tocados para adicionar capacidade | fork de arquivo upstream (`84`, `95`) | 0 arquivos compartilhados |
| C5 | **Peso** | arquivos próprios + linhas de `ujust` | 223 arquivos, 3.972 linhas, 177 receitas | ≤ 120 arquivos ativos, receitas por capacidade |

O C3 é o diferencial competitivo real. Os outros quatro são disciplina.

## 3. Os três pilares

### 3.1 Desenvolvimento

Precisa de: containers (podman), VMs quando necessário, IDE remoto, agentes com
worktree isolada, e **não ser interrompido** por um jogo ou por um modelo carregado.

O que a imagem entrega: `podman`/`docker`, libvirt/incus (opt-in), code-server e
ide-tunnel, KRunner workspaces, worktrees (Paseo/OpenCode), toolchains via
`mise`/`uv`/`brew` — **fora** da imagem.

Regra: toolchain de projeto nunca entra na imagem. Entra motor.

### 3.2 Jogos

Precisa de: gamescope/Steam intactos, perfil de energia por jogo, captura/stream,
e não manter `performance` ligado depois que o jogo fecha.

O que a imagem entrega: `g15-boost` (perfil por jogo com restore), `gamemode-nested`,
Sunshine + mediamtx, câmera virtual.

Medição que já justifica o desenho: `performance` custa ~1000 RPM e devolve ~0 MHz
em carga de CPU; em carga de GPU devolve ~+105 MHz. Ou seja: **ligar por jogo, não
no boot** — que é exatamente o que `g15-boost` faz.

### 3.3 LLM local

Precisa de: modelos servidos localmente (llama-swap/NOMAD), offload para DDR5,
e **liberar VRAM quando outra carga precisa**.

O que a imagem entrega: NOMAD (Command Center, mysql/redis, llama-swap CUDA),
Vane, agent-mesh.

O problema real num 3060 de 6 GB: um modelo residente e um jogo não cabem juntos.
Hoje isso é resolvido por três ganchos separados (`ai-vram-purge`, `gamemode.ini`,
`ujust llama-unload`). Isso é frágil: depende de o jogo passar pelo gamemode.

## 4. A camada que falta: arbitragem

Proposta: um único ponto de decisão — `dx-arbiter` — que responde "quem é o dono
da GPU agora" e aplica a política:

| Evento | Ação |
| :--- | :--- |
| jogo Steam inicia (`gamemoded` ou processo em `~/Games`) | descarrega modelos do llama, aplica `performance` via `g15-boost`, mantém ventoinha sob controle do `tuned-ppd` |
| jogo termina | restaura perfil anterior, libera VRAM, não religa modelo sozinho |
| agente/dev pede LLM | carrega modelo sob demanda, com teto explícito de VRAM |
| sessão remota (Sunshine) conecta | garante que o perfil de energia não caiu para `power-saver` |
| nada acontecendo | `balanced`, fans 0 RPM, nenhum modelo residente |

Por que isso é arquitetura e não script: hoje a política está espalhada em
`gamemode.ini`, `ai-vram-purge`, `llm-vram-purge`, `smart-idle-checker`. Cada novo
pilar adiciona mais um gancho e o comportamento passa a depender da ordem. Um
árbitro único é **testável** (evento → estado) e é o que permite dizer "melhor"
com número.

## 5. Extensão infinita: contrato de capacidade

Toda capacidade nova (um serviço, um stack de IA, um receptor de mídia) vira uma
pasta autocontida:

```
capabilities/<nome>/
  capability.yml      # nome, descrição, pacotes, portas (61300-61399), serviços opt-in
  files/system/...    # o que vai para a imagem
  just/<nome>.just    # receitas ujust
  verify/<nome>.txt   # asserts (file|, bin|, unit|, content|)
  profile.yml         # qual pilar: dev | play | llm | mesh
```

Regras do contrato:

1. Capacidade **nunca** edita arquivo de outra capacidade nem arquivo upstream.
2. Serviço de capacidade é **opt-in** (nada habilitado no boot), exceto as duas
   exceções já estabelecidas (`tailscale`, `sunshine`).
3. Portas sempre na faixa `61300-61399`, bind em loopback, publicação via
   `tailscale serve`.
4. Nenhum caminho de usuário (`/var/home/<user>`) em script que vai para a imagem.
   Isso é verificável no CI e é o que impede vazar persona.
5. Remover a pasta remove a capacidade por completo — sem resíduo em `dx-verify`.

Isso é o "infinito" na prática: o custo de adicionar é proporcional à capacidade,
não ao tamanho da imagem.

## 6. Camadas alvo

```
L0  base          bazzite-nvidia (pin + digest, F45)                    upstream
L1  hardware      G15: kargs, g15-*, gpu-unlock, udisks guard, sensors   ~30 arquivos
L2  plataformas   dev | play | llm  (motores, não toolchains)            ~60 arquivos
L3  arbitragem    dx-arbiter: quem é dono da GPU/RAM agora               1 serviço
L4  capacidades   casting | mesh | aistudio  (opt-in, por manifest)      móvel
L5  persona       shell, Brewfiles, IDEs, wallpaper                      imagem separada
```

`L5` sai do base de vez: é a única camada que pode ser pessoal sem contaminar o
resto, e é o que permite publicar a imagem sem vazar preferências.

## 7. Scoreboard

Para C1–C5 deixarem de ser retórica, um comando tem que imprimir os números:

`ujust dx-metrics` deve reportar:

- versão da base, data da build e dias desde o release upstream;
- arquivos próprios, linhas e receitas `ujust`;
- unidades habilitadas (system + user) e quais vieram do base;
- idle: RPM, temp CPU/GPU, RAM usada, VRAM usada;
- última execução do árbitro e estado atual (`balanced`, dono da GPU).

Sem isso, qualquer mudança é "parece melhor". Com isso, cada PR pode dizer o que
melhorou e o que piorou.

## 8. Não-objetivos

- Ser um fork do Bazzite ou replicar o `bazzite-dx`.
- Empacotar toolchains de projeto (Node, Python, Rust) na imagem.
- Substituir o desktop, o instalador ou o sistema de update do Bazzite.
- "Paridade de features" com outras imagens. A comparação é contra o **alvo
  medido**, não contra o catálogo do vizinho.

## 9. Ordem de execução

1. **F45** (PR #181) — pré-requisito de C1, não objetivo.
2. **Contrato de capacidade** — sem ele, o resto continua virando fork.
3. **`dx-arbiter`** — o diferencial de C3, e o que justifica o nome "DX".
4. **Separação da persona** (L5) — o que permite a imagem ser agnóstica.
5. **Scoreboard** — mede tudo acima.
