# O que o histórico de commits ensina

> 620 commits entre 2026-03-03 e 2026-11-07. Este documento não é retrospectiva:
> é a base empírica para decidir o que a camada deve ser. Números medidos no
> próprio repositório.

## 1. Perfil de atividade

| Mês | Commits | Linhas | Leitura |
| :--- | ---: | :--- | :--- |
| 2026-03 | 52 | +3358 / −1455 | fundação (BlueBuild, AWCC, G15) |
| 2026-04 | 67 | +7909 / −3650 | explosão de infraestrutura |
| 2026-05 | 53 | +2648 / −988 | estabilização |
| 2026-06 | **20** | +598 / −231 | pausa |
| 2026-07 | 63 | +5197 / −1038 | retomada |
| 2026-08 | 133 | +6795 / −3336 | pico de features |
| 2026-09 | 139 | +7180 / −2783 | pico de features |
| 2026-10 | 80 | +1796 / −559 | consolidação |
| 2026-11 | 6 | +89 / −10 | manutenção |

Tipos: **179 `feat`**, 175 `chore`, **124 `fix`**, 46 `docs`, 41 `refactor`.
Desde setembro, **87 commits são de dependências** (~39 % do período) — o maior
bloco único de trabalho automatizado.

## 2. Onde o esforço realmente foi

| Arquivo | Commits | Trajetória |
| :--- | ---: | :--- |
| `modules/dx-verify/dx-verify.sh` | **74** | 86 → **370 linhas** (4,3×) |
| `AGENTS.md` | 68 | documento cresceu junto com o conhecimento |
| `.github/renovate.json5` | 39 | automação sendo consertada repetidamente |
| `files/system/usr/libexec/bazzite-dx-groups` | 39 | 1,6 KB → **27,9 KB** (17×) |
| `files/justfiles/66-silver-goggles.just` | 38 | monólito de remote access |
| `image-versions.yaml` | 34 | 34 bumps de base em 8 meses |
| `.github/workflows/build.yml` | 34 | pipeline em ajuste contínuo |

`files/system` concentra o churn: 1.084 menções de arquivo em commits, contra 154
em `files/justfiles`, 107 em `modules/` e 66 em `recipes/`.

**Diagnóstico:** o custo não está no que a imagem *faz*, está em **manter o
registro do que ela faz** (`dx-verify`) e em **scripts que viraram fork do
upstream** (`bazzite-dx-groups`). Nenhum dos dois entrega capacidade ao usuário.

## 3. Ciclo de vida das features

| Feature | Entrou | Saiu | Vida | Como entrou |
| :--- | :--- | :--- | :--- | :--- |
| AWCC | 2026-03-08 | 2026-09-06 | 6 meses | pacote + daemon no host |
| YaCy (P2P search) | 2026-09-06 | 2026-09-19 | **13 dias** | serviço |
| Ollama backend | 2026-07-29 | 2026-09-27 | 2 meses | container + integração |
| Shairport-sync | 2026-07-27 | 2026-07-27 | **horas** | pacote + unit |
| FCast receiver | 2026-07-26 | 2026-07-28 | 2 dias | unit systemd |
| `g15-thermal` | 2026-07-27 | 2026-07-27 | **horas** | unit + udev |

Padrão claro: **o que entrou como pacote/serviço no host morreu rápido**; o que
virou container sobreviveu (NOMAD, Vane, VoiceStudio, ComfyUI). A própria base já
segue essa direção — o Bazzite está removendo o Sunshine da imagem para instalar
sob demanda.

Consequência para o desenho: **servidor é container; host só tem motor.** E
capacidade nova entra inerte e opt-in, porque a chance de ser descartada em dias
não é hipótese — é o histórico.

## 4. Cadência da base

34 atualizações de pin em 8 meses (~4,3/mês), mas com **um vão de 47 dias**
(2026-09-21 → 2026-11-07) em que os containers continuaram atualizando e a base
não. Não foi falta de automação: foi fila de merge.

Isso valida três decisões e reprova uma:

- ✅ PR automático de base com **diff de 3 linhas** (hoje um bump mexe em
  `image-versions.yaml`, `generate-recipe.sh`, workflow e labels).
- ✅ Alerta de lag > 14 dias — o vão de 47 dias passou silencioso.
- ✅ Merge manual (decisão de 2026-11-08): um build ruim de base entra em tudo.
- ❌ Auto-merge de patch sem teste de boot em VM.

## 5. Fluxo de trabalho real

- 81 merges por squash (maioria `chore(deps)`), 11 merges diretos
  `Merge branch 'main'` — ou seja, a maior parte do desenvolvimento acontece
  **direto na main**, com PR principalmente para dependências.
- **15 imagens distintas** pinadas inline em 17 Quadlets, com 87 commits de
  dependências desde setembro. Esse é o passivo de manutenção mais previsível:
  não cresce com features, cresce com o tempo.

## 6. O que muda no desenho (evidência → decisão)

| Evidência | Decisão |
| :--- | :--- |
| `dx-verify` 4,3× em 5 meses, 74 commits | Não crescer registro central. Check curto por domínio + boot real (bcvk). |
| `bazzite-dx-groups` 17× | Não forkar script upstream. Adotar upstream + `96-*.just` para o que é nosso. |
| 3 features mortas em < 48 h, 2 em < 3 meses | Inerte + opt-in por padrão; nada de enable no boot. |
| Servidores em container sobreviveram | NOMAD/mesh/aistudio permanecem containers; host só recebe motor. |
| Vão de 47 dias no pin | `dx-metrics` com lag + alerta; bump de 3 linhas. |
| 15 imagens / 87 deps commits | Agrupar updates semanais; nenhuma stack é removida por desuso. |
| Trabalho direto na main | Mudança de arquitetura em branch/worktree (Paseo), não em main. |

## 7. O que o histórico valida do alvo proposto

1. **Containerfile + `build_files/NN-*.sh`** — é a direção que o ecossistema já
   tomou e a que sobreviveu aqui (containers > pacotes no host).
2. **Sem schema/framework próprio** — o repo já criou e removeu um módulo inteiro
   (`dx-virt`); a lição é não criar estrutura que precise de manutenção própria.
3. **Persona fora do caminho crítico** — 68 commits em `AGENTS.md` e 22 em
   `bling.sh` mostram que documentação e preferência mudam mais que hardware; elas
   não devem arrastar rebuild da imagem.
4. **Uma imagem, tudo inerte** — a taxa de descarte de feature torna matriz de
   perfis um custo sem retorno.
