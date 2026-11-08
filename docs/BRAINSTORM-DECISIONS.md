# Brainstorm de decisões: impacto, manutenção, alinhamento

> Antes de construir, este documento ataca três perguntas: **o que cada escolha
> custa**, **o que apodrece com o tempo** e **o que estamos assumindo sem dizer**.
> Inclui pré-mortem e critérios de reversão, para que nenhuma decisão vire
> identidade.

## 1. Decisões em jogo

> **Decidido em 2026-11-08:** D1 → não criar daemon; consolidar a política nos
> ganchos existentes. D3 → persona fica no base, com check de CI contra vazamento.
> D5 → PR automático e merge manual. Prioridade das cargas → **Jogos > Dev > LLM**.
> D2 (contrato) e D4 (scoreboard) seguem em aberto para validação com uma
> capacidade real.

### D1 — Política de GPU (sem daemon novo)

**O que muda:** nenhuma unidade systemd nova. Uma constante de prioridade
compartilhada (`/etc/silver-goggles/priority.conf`, ordem **Jogos > Dev > LLM**)
lida pelos ganchos que já existem (`gamemode.ini`, `ai-vram-purge`,
`smart-idle-checker`), mais a remoção de sobreposição entre eles.

| Impacto | Detalhe |
| :--- | :--- |
| Positivo | Comportamento deixa de depender da ordem dos hooks; nenhum passivo novo de daemon |
| Negativo | Continua acoplado ao gamemode: jogo fora do Steam/Lutris não dispara |
| Manutenção | Baixa; o risco é a constante divergir do que os hooks fazem |
| Alternativa | Daemon dedicado (rejeitado: mais um serviço para observar e falhar) |

**Sinal de reversão:** se a constante não bastar e os hooks precisarem de lógica
de decisão (não só de valor), o problema é a ausência de um dono da política — e
aí sim se avalia um serviço. Não antes.

**Custo escondido:** detectar jogo é fácil no Steam/gamemode e difícil fora dele
(Lutris, Heroic, Wine solto). O documento promete o que o sinal permite.

### D2 — Contrato de capacidade (`capabilities/<nome>/`)

**O que muda:** cada capacidade passa a ser pasta autocontida com manifesto,
arquivos, receitas, asserts e perfil; `generate-recipe` compõe a partir do manifesto.

| Impacto | Detalhe |
| :--- | :--- |
| Positivo | Adicionar/remover capacidade não toca arquivo compartilhado; `dx-verify` deixa de ser um registro de 196 linhas |
| Negativo | **Risco de over-engineering**: criar um framework para 6 casos |
| Manutenção | O manifesto vira schema — precisa de validação no CI, senão é YAML morto |
| Alternativa | Manter o modelo atual e só mover blocos para arquivos menores |

**Sinal de reversão:** se a **segunda** capacidade migrada precisar de caso especial
no gerador, o contrato está errado. Kill criterion explícito: migrar `casting` e
`aistudio` pelo contrato; se ambos passarem sem exceção, vale migrar o resto.

**Custo escondido:** a composição precisa ser determinística. Se a ordem de
aplicação de arquivos depender de `readdir`, o build fica não reproduzível.

---

### D3 — Separação da persona

**Decidido em 2026-11-08: fica no base por enquanto.** O objetivo agora é não
adicionar pipeline nem camada desnecessária; o risco de vazamento é tratado por
check de CI, não por separação física.

| Opção | Impacto | Manutenção |
| :--- | :--- | :--- |
| **Imagem própria** `FROM silver-goggles` | Isolamento total; base publicável sem preferências | +1 pipeline, +1 pin para atualizar, +1 lugar para quebrar |
| **Dotfiles via chezmoi/mise** | Zero pipeline; troca sem rebuild | Deriva entre máquinas; precisa de repo separado e idempotência |
| **No base (escolhido)** | Nenhum custo novo; persona isolada por diretório | Precisa de CI contra caminho de usuário e dotfile em `files/system` |

**Sinal de reversão:** se a persona começar a mudar mais rápido que a imagem, sai
para dotfiles — não para imagem separada.

---

### D4 — Scoreboard (`ujust dx-metrics`)

**O que muda:** um comando read-only que imprime frescor, peso, unidades, idle
(RPM/temp/RAM/VRAM) e estado do árbitro.

| Impacto | Detalhe |
| :--- | :--- |
| Positivo | Torna C1–C5 falseáveis; dá número para cada PR |
| Negativo | Coleta de VRAM/RPM depende de `nvidia-smi`/`hwmon` — pode falhar em versões futuras |
| Manutenção | Baixa; precisa de baseline salvo para comparar (senão é foto, não série) |
| Alternativa | Medir à mão quando desconfiar (é o que fazemos hoje: nenhuma série) |

**Custo escondido:** métrica sem histórico não decide nada. O comando precisa
gravar uma linha por execução (`/var/log/dx-metrics.jsonl`) para virar tendência.

---

### D5 — Frescor automático

**Decidido em 2026-11-08: PR automático, merge manual.** Renovate já abre o PR do
pin; o merge continua humano até existir teste de boot em VM.

| Política | Impacto | Risco |
| :--- | :--- | :--- |
| Auto-merge em patch (rejeitado por ora) | Base nova sem trabalho | Build ruim entra enquanto você está fora |
| **Auto-PR + merge manual (escolhido)** | Controle total | Atraso depende de disciplina; mitigado por alerta de lag > 14 dias |
| Auto-merge após bcvk | Melhor dos dois | Exige o boot em VM no CI antes |

**Sinal de reversão:** quando `bcvk` rodar no CI, reavaliar auto-merge de patch.

---

### D6 — Fork vs upstream (`84-bazzite-virt.just`, `95-bazzite-dx.just`)

| Opção | Impacto | Manutenção |
| :--- | :--- | :--- |
| Adotar upstream + `96-*.just` só com o nosso | Menos código; herda correções | Perde customizações que o upstream não tem (`dx-group sync`, `dx-workspace-*`) |
| Manter fork | Mantém comportamento exato | 3 versões do mesmo arquivo na família; drift silencioso |

**Sinal de reversão:** se o upstream mudar `setup-virtualization` de forma
incompatível com nosso `bazzite-dx-virt-setup`, o fork deixa de ser dívida e passa a
ser necessidade — mas então o certo é **propor upstream**, não aprofundar o fork.

---

## 2. Pré-mortem: 12 meses depois, o que deu errado

| Cenário | Porque aconteceria | Prevenção |
| :--- | :--- | :--- |
| O gerador de recipe virou o novo gargalo | Cada capacidade nova pediu campo novo no schema | Validar schema no CI; congelar formato após 3 capacidades |
| O árbitro foi desligado "temporariamente" | Falso positivo tirou VRAM no meio de um treino | Estado padrão seguro: só age em evento explícito, com timeout e log |
| `dx-metrics` virou ficção | Campos mudaram de lugar no kernel/driver | Marcar cada métrica com "fonte" e degradar para `n/a`, nunca falhar |
| Voltamos a ter 200 receitas | Capacidade nova entrou em `66-*.just` "só dessa vez" | Regra de CI: `66`/`96` não crescem; receita nova exige pasta de capacidade |
| Persona vazou para a imagem | Alguém colocou `starship.toml` em `files/system` | Check de CI: `files/system` não pode conter `skel/.config` de shell/IDE |
| Base ficou 2 meses atrás | Build quebrou e ninguém viu | Alerta de lag > 14 dias no próprio `dx-metrics` |
| Perdemos o hardware | Troca de máquina | Toda a camada L1 isolada; L2+ não pode depender de Dell |

## 3. Anti-escopo (o que não construir, para proteger manutenção)

1. **Nenhum framework genérico de imagens.** O contrato serve a este repo; se
   outra pessoa quiser usar, ela copia a ideia, não a dependência.
2. **Nenhum daemon novo.** Consolidar política nos ganchos existentes; serviço
   novo só se a constante não bastar.
3. **Nenhuma abstração de desktop/DE.** KDE é premissa, não plugin.
4. **Nenhuma promessa de portabilidade.** O alvo é um G15 5520; o resto é efeito
   colateral bem-vindo, não requisito.
5. **Nenhum empacotamento de toolchain de projeto.** `mise`/`uv`/`brew` cobrem.

## 4. Alinhamento: premissas e o estado de cada uma

| # | Premissa | Estado |
| :-- | :--- | :--- |
| A1 | Prioridade das cargas: **Jogos > Dev > LLM** | **confirmado em 2026-11-08** |
| A2 | O hardware continua sendo o G15 5520 por ≥12 meses | em vigor; sem data de revisão |
| A3 | O LLM local continua rodando no host (6 GB) em vez de remoto | em vigor |
| A4 | O acesso remoto é sempre Tailscale (nunca LAN aberta, nunca relay) | em vigor |
| A5 | A manutenção é feita principalmente por agente, com revisão humana | em vigor |
| A6 | Preferência por menos serviços ativos, mesmo com custo de conveniência | **confirmado em 2026-11-08** (levou à rejeição do daemon) |
| A7 | A persona permanece no base, protegida por CI | **confirmado em 2026-11-08** |

## 5. Pendências

1. **D2 (contrato de capacidade)** — decidir depois de migrar `casting` e
   `aistudio`; o resultado dessas duas define se o formato está certo.
2. **D4 (scoreboard)** — construir antes das próximas mudanças de camada, para
   existir baseline medido.
3. **D6 (forks `84`/`95`)** — sem data; depende de quando o custo do drift doer.
