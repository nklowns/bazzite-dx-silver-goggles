# Brainstorm de decisões: impacto, manutenção, alinhamento

> Antes de construir, este documento ataca três perguntas: **o que cada escolha
> custa**, **o que apodrece com o tempo** e **o que estamos assumindo sem dizer**.
> Inclui pré-mortem e critérios de reversão, para que nenhuma decisão vire
> identidade.

## 1. Decisões em jogo

### D1 — `dx-arbiter` (dono único da GPU/RAM)

**O que muda:** um serviço pequeno que escuta eventos (gamemoded, processo de jogo,
pedido de LLM, sessão remota) e aplica uma tabela de estado única.

| Impacto | Detalhe |
| :--- | :--- |
| Positivo | Elimina a dependência de ordem entre `gamemode.ini`, `ai-vram-purge` e `llm-vram-purge`; torna C3 mensurável |
| Negativo | **Mais um daemon** para observar; se travar com `performance` aplicado, a ventoinha fica no máximo até alguém notar |
| Manutenção | Baixa em código, alta em **teste**: sem teste de evento vira "funciona na minha máquina" |
| Alternativa | Não ter árbitro e deixar os hooks atuais (menos código, comportamento indefinido) |

**Sinal de reversão:** se em duas semanas o árbitro precisar de exceção por jogo
(porque o sinal de "jogo rodando" não é confiável), o problema é o sinal, não a
política — e a solução correta é reduzir o escopo para "LLM cede VRAM quando
qualquer processo com `/dev/nvidia*` aberto aparece".

**Custo escondido:** detectar jogo é fácil no Steam/gamemode e difícil fora dele
(Lutris, Heroic, Wine solto). Se o árbitro prometer demais, vira fonte de bug.

---

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
`dx-arbiter` pelo contrato; se ambos passarem sem exceção, vale migrar o resto.

**Custo escondido:** a composição precisa ser determinística. Se a ordem de
aplicação de arquivos depender de `readdir`, o build fica não reproduzível.

---

### D3 — Separação da persona (L5)

Duas implementações possíveis, com custos bem diferentes:

| Opção | Impacto | Manutenção |
| :--- | :--- | :--- |
| **Imagem própria** `FROM silver-goggles` | Isolamento total; base publicável sem preferências | +1 pipeline, +1 pin para atualizar, +1 lugar para quebrar |
| **Dotfiles via chezmoi/mise** no primeiro login | Zero pipeline; troca sem rebuild | Deriva entre máquinas; precisa de repo separado e idempotência |

**Sinal de reversão:** se a persona mudar mais que a imagem (provável: gosto muda
mais que hardware), imagem própria é a opção errada — rebuild a cada ajuste de
`starship.toml` é fricção pura.

**Recomendação:** dotfiles primeiro; imagem própria só se houver necessidade de
*garantir* estado em máquina nova sem passo manual.

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

**O que muda:** Renovate já atualiza o pin; hoje o atraso é revisão humana.

| Política | Impacto | Risco |
| :--- | :--- | :--- |
| Auto-merge em patch | Base nova em ≤2 dias sem trabalho | Um build ruim entra enquanto você está fora |
| Auto-PR + merge manual | Controle total | Volta ao atraso atual |
| Auto-merge só se `dx-metrics` do CI passar | Melhor dos dois | Exige o scoreboard no CI, não só local |

**Sinal de reversão:** se um auto-merge quebrar boot uma vez, a política volta para
manual até existir teste de boot em VM (bcvk) no CI.

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
2. **Nenhum daemon a mais além do árbitro.** Cada serviço novo é um passivo.
3. **Nenhuma abstração de desktop/DE.** KDE é premissa, não plugin.
4. **Nenhuma promessa de portabilidade.** O alvo é um G15 5520; o resto é efeito
   colateral bem-vindo, não requisito.
5. **Nenhum empacotamento de toolchain de projeto.** `mise`/`uv`/`brew` cobrem.

## 4. Alinhamento: premissas que precisam de confirmação

| # | Premissa | Se estiver errada |
| :-- | :--- | :--- |
| A1 | Os três pilares são dev, jogos e LLM local — nessa ordem de prioridade | A arbitragem prioriza o pilar errado |
| A2 | O hardware continua sendo o G15 5520 por ≥12 meses | L1 vira peso morto e o desenho deveria ser mais genérico |
| A3 | O LLM local continua fazendo sentido rodar no host (6 GB) em vez de remoto | NOMAD/llama perde prioridade e a arbitragem fica só para jogos |
| A4 | O acesso remoto é sempre Tailscale (nunca LAN aberta, nunca relay) | Muda o desenho de `remote-*` |
| A5 | A manutenção é feita principalmente por agente, com revisão humana | Docs precisam ser mais executáveis e asserts mais fortes |
| A6 | Preferência por menos serviços ativos, mesmo com custo de conveniência | O critério C2 (idle) deixa de ser alvo |
| A7 | A persona deve viver fora da imagem (dotfiles ou imagem separada) | L5 volta para dentro e a imagem deixa de ser publicável |

## 5. Perguntas abertas (para decidir junto)

1. **D3**: persona como dotfiles (menos pipeline, mais disciplina) ou imagem
   separada (mais garantia, mais CI)?
2. **D5**: qual política de frescor — auto-merge de patch, ou sempre PR manual?
3. **D1**: o árbitro deve agir também sobre energia/ventoinha, ou só sobre VRAM/RAM?
4. **A1**: a ordem dev > jogos > LLM está certa? Isso muda o que é "ceder" na
   arbitragem.
