# 🌐 Agent Mesh — Developer & Agent Cheat-Sheet

> **Ambiente**: Bazzite Atomic (Dell G15 5520, KDE/NVIDIA, Fedora Atomic)  
> **Filosofia de Design**: **KISS & Delegação Lean**. Delegamos busca, agregação, extração e IA diretamente aos projetos open source upstream especializados (SearXNG, Vane, Tor, Trawl, Lightpanda, `ia` CLI). A camada de script/MCP atua estritamente como uma casca fina (thin client).  
> **Boot Impact Policy**: Zero cold-boot overhead. Serviços pesados operam em standby e sobem sob demanda.

---

## 1. Mapeamento de Portas e Serviços (Faixa Reservada DX `61300-61399`)

Para evitar conflitos com servidores locais de desenvolvimento (3000, 5173, 8080, etc.), todos os serviços DX da malha utilizam a faixa reservada:

| Serviço | Contêiner / Binário | Porta Loopback | Exposição Tailscale (TLS) | Consumo Médio | Política de Boot |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **SearXNG** | `nomad-searxng` | `127.0.0.1:61387` | `https://bazzite.<tailnet>:61387` | ~120 MB RAM | On-demand / Auto-wake |
| **Redis / Valkey** | `nomad-redis` | `127.0.0.1:6379` | *Apenas rede OCI interna* | ~30 MB RAM | Dependência do SearXNG |
| **Tor Proxy** | `nomad-tor` | `127.0.0.1:9050` (SOCKS5)<br>`127.0.0.1:9080` (HTTP) | *Loopback estrito* | ~25 MB RAM | Dependência do SearXNG / Tor |
| **I2P Router (i2pd)** | `nomad-i2pd` | `127.0.0.1:4444` (HTTP Proxy)<br>`127.0.0.1:4447` (SOCKS5)<br>`127.0.0.1:7070` (Web Console) | *Loopback estrito* | ~10-15 MB RAM (Teto 512M) | Standby (`ujust i2p-up`) |
| **Vane (Perplexica)** | `nomad-vane` | `127.0.0.1:61385` | `https://bazzite.<tailnet>:61385` | ~200 MB RAM (Teto 1.5G) | On-demand (`ujust vane-up`) |
| **Ollama (GPU)** | `nomad-ollama` | `127.0.0.1:61382` | *Loopback estrito* | ~200 MB RAM + 2-4 GB VRAM | On-demand (`ujust ollama-up`) |
| **Trawl (Anti-Bot)** | `nomad-trawl` | `127.0.0.1:8191` (API)<br>`127.0.0.1:8192` (Proxy) | *Loopback estrito* | ~250-400 MB RAM (Teto 1.5G) | Standby (`ujust trawl-up`) |
| **Recoll (Workspace)** | `nomad-recoll` | `127.0.0.1:61389` (WebUI / JSON) | `https://bazzite.<tailnet>:61389` | ~25 MB RAM (Teto 1G) | Standby / Auto-wake |
| **Lightpanda** | `/usr/bin/lightpanda` | `127.0.0.1:9225` (CDP) | *Loopback estrito* | 0 MB boot (efêmero CLI) | On-demand (executável Zig) |
| **YaCy (P2P DHT)** | `nomad-yacy` | `127.0.0.1:8090` | *Loopback estrito* | ~1.5 - 2 GB RAM | Standby estrito (`ujust yacy-up`) |

---

## 2. Comandos de Ciclo de Vida (`ujust`)

Gerenciamento declarativo via `systemd --user` integrado com receitas do Justfile:

```bash
# 📊 Diagnóstico Geral
ujust agent-mesh-status      # Exibe status consolidado de todos os serviços e portas CDP
ujust mesh-status            # Apelido rápido para o status geral

# 🔍 SearXNG (Metapesquisa Soberana)
ujust searxng-up             # Inicia Redis + Tor + SearXNG
ujust searxng-down           # Desativa o SearXNG
ujust searxng-status         # Status e telemetria da unidade
ujust searxng-logs           # Acompanha logs do contêiner em tempo real
ujust remote-searxng-setup   # Expõe SearXNG via Tailscale Serve com TLS válido
ujust remote-searxng-teardown# Remove SearXNG do Tailscale Serve

# 🧠 Vane / Perplexica (Deep Research & IA)
ujust vane-up                # Inicia Vane + SearXNG + Ollama GPU automaticamente
ujust vane-down              # Desativa o Vane (avisa se a GPU ainda estiver com VRAM alocada)
ujust vane-status            # Status do serviço Vane
ujust vane-logs              # Logs do Vane
ujust remote-vane-setup      # Expõe o Vane no Tailscale com TLS

# 🤖 Ollama GPU (Inferência Local)
ujust ollama-up              # Inicia o Ollama com passthrough NVIDIA
ujust ollama-down            # Encerra o Ollama liberando VRAM da GPU
ujust ollama-models          # Lista modelos baixados (qwen2.5:3b, qwen2.5-coder:7b, nomic-embed-text)

# 🛡️ Trawl (Bypass de Cloudflare Turnstile, DDoS-Guard & WAFs)
ujust trawl-up               # Inicia o serviço Trawl (solver Firefox Camoufox + Whisper STT)
ujust trawl-down             # Desativa o Trawl
ujust trawl-status           # Status do Trawl
ujust trawl-logs             # Acompanha resolução de desafios anti-bot

# 🧅 Tor, I2P & YaCy (Darknet & P2P)
ujust tor-up / tor-down      # Controle do proxy Tor SOCKS5/HTTP
ujust i2p-up / i2p-down      # Controle do roteador I2P i2pd (HTTP :4444, SOCKS5 :4447, Web :7070)
ujust i2p-status / i2p-logs  # Telemetria e logs do roteador I2P
ujust yacy-up / yacy-down    # Controle do nó YaCy P2P

# 📁 Recoll (Indexação e Busca Local em ~/dev e ~/Documents)
ujust recoll-up / recoll-down# Controle do Recoll WebUI (:61389)
ujust recoll-index           # Executa indexação incremental sob demanda
ujust recoll-status          # Status da WebUI, porta 61389 e tamanho do índice Xapian
ujust recoll-logs            # Acompanha logs do container
ujust remote-recoll-setup    # Expor Recoll WebUI via Tailscale Serve com TLS
```

---

## 3. Esferas de Busca e Atalhos ("Bangs") do SearXNG

O SearXNG está configurado com 9 esferas temáticas livres de anúncios e rastreadores:

| Esfera / Categoria | Motores Nativos Integrados | Atalhos de Busca ("Bangs") |
| :--- | :--- | :--- |
| **`general`** | Brave, Google CSE, Mojeek, Qwant, Wikipedia, Wikidata | `!general`, `!br`, `!wp`, `!wd` |
| **`it`** (Engenharia & TI) | GitHub, GitLab, StackOverflow, Arch Linux Wiki, PyPI, NPM, Crates.io, Docker Hub, Repology, NVD (CVEs), HuggingFace | `!it`, `!gh`, `!gl`, `!so`, `!al`, `!pypi`, `!npm`, `!crates`, `!nvd`, `!hf` |
| **`science`** (Ciência) | arXiv, Semantic Scholar, OpenAlex, PubMed, Anna's Archive, Z-Library | `!science`, `!arxiv`, `!sem`, `!zlib`, `!annas` |
| **`indie`** (Small Web) | Marginalia (anti-SEO / phlogs), Neocities, Mwmbl | `!indie`, `!marginalia`, `!neocities`, `!mwmbl` |
| **`p2p`** (Descentralizada) | Mwmbl (0 RAM, API pública), YaCy (pool público ex: KIT + local) | `!p2p`, `!mwmbl`, `!yacy` |
| **`onions`** (Darknet Tor) | Ahmia (roteamento exclusivo via SOCKS5 `socks5h://tor:9050`) | `!onions`, `!ahmia`, `!onion` |
| **`i2p`** (Darknet I2P) | I2P Search, Legwork, Idk.i2p (roteamento exclusivo via HTTP proxy `http://i2pd:4444`) | `!i2p`, `!i2psearch`, `!legwork` |
| **`archive`** (Histórica) | OpenLibrary (Internet Archive), Z-Library, Library of Congress (`locgov`), Anna's Archive | `!archive`, `!openlib`, `!zlib`, `!locgov` |
| **`local`** (Workspace Local) | Recoll (Xapian index de `~/dev` e `~/Documents` via API :8080) | `!local`, `!recoll`, `!workspace` |
| **`gemini`** (Geminispace) | Kennedy Search (`gemini://kennedy.gemi.dev/search` via TLS nativo :1965) | `!gemini`, `!kennedy`, `!capsule` |

> [!TIP]
> **Preservação Nativa**: Na interface web do SearXNG, todo resultado possui um link "cached" apontando diretamente para `https://web.archive.org/web/<url>`.

---

## 4. Ferramenta CLI `mesh-search` & Interface MCP

O script `/home/cloud/dev/IDEs/global-harness/bin/mesh-search` é registrado como servidor MCP (`agent-mesh`) para Claude, Gemini e Antigravity:

### Exemplos via Terminal:
```bash
# Busca geral
mesh-search search "linux kernel btrfs"

# Busca em categoria ou apelido temático
mesh-search search --category it "rust tokio async"
mesh-search search --category science "transformer attention mechanisms"
mesh-search search --category archive "operating systems silberschatz"
mesh-search search --category onions "threat intelligence"
mesh-search search --category i2p "privacy software"
mesh-search search --category local "CHEATSHEET"
mesh-search search --category gemini "fedora atomic ostree"
mesh-search search "!gemini bazzite"

# Deep Research com síntese e citações (via Vane + Ollama)
mesh-search research "Quais as novidades do kernel Linux 6.13 para drivers de rede?" --mode fast
mesh-search research "Análise comparativa entre Btrfs subvolumes e ZFS datasets" --mode deep

# Extração limpa de página da web em Markdown
mesh-search fetch "https://github.com/torvalds/linux"
mesh-search fetch "https://site-com-cloudflare.com" --trawl     # Forçar bypass anti-bot
mesh-search fetch "http://site-morto-404.com/artigo"           # Fallback automático no Wayback Machine
mesh-search fetch "https://exemplo.com" --archive              # Forçar snapshot histórico do passado
mesh-search fetch "http://exemplo.onion" --tor                 # Acesso a sites onion via Tor
mesh-search fetch "http://identiguy.i2p" --i2p                 # Acesso a eepsites I2P via i2pd
mesh-search fetch "gemini://geminiprotocol.net/docs/faq.gmi"   # Extração nativa de cápsula Gemini


# Diagnóstico e telemetria de saúde
mesh-search health              # Exibe estado dos contêineres e alertas de motores
mesh-search health --probe      # Dispara sonda ativa em tempo real nas esferas
mesh-search health --json       # Saída legível por máquina para automações
```

### Ferramentas Expostas ao Agente MCP:
1. `mesh_search(query, category?, engines?, limit?)`: Metapesquisa rápida e anonimizada.
2. `mesh_research(query, mode?)`: Investigação recursiva com síntese de texto e citações (`fast` ou `deep`).
3. `mesh_fetch(url, use_tor?, use_i2p?, trawl?, archive?)`: Leitura limpa de páginas com suporte a SPAs JS, contorno de WAFs, resgate no Wayback Machine e darknets (.onion / .i2p).
4. `mesh_status(probe?)`: Auditoria de resiliência e saúde dos nós OCI da malha.

---

## 5. Cascata de Extração Web em 3 Tiers (`mesh_fetch`)

Ao extrair o conteúdo de uma página web, a malha utiliza uma cascata de resiliência sem intervenção manual:

```mermaid
graph TD
    A["URL Solicitada"] --> T1["Tier 1: Lightpanda CLI (Headless Zig)"]
    T1 -->|HTTP 200 / Sucesso| Ret["Retorna Markdown Limpo"]
    
    T1 -->|HTTP 404, 403, 410, Timeout| T2["Tier 2: Wayback Machine & Archive.today"]
    T2 -->|Snapshot Encontrado| Ret
    
    T1 -->|Desafio Cloudflare Turnstile / DDoS-Guard| T3["Tier 3: Trawl Engine (Camoufox + Whisper STT)"]
    T3 -->|Clearance Resolvido| Ret
    
    T2 -->|Sem snapshot histórico| Err["Retorna erro detalhado com telemetria"]
```

---

## 6. Internet Archive Standalone CLI (`ia`)

Instalado de forma isolada via `uv tool` em `~/.local/bin/ia` (v5.11.1). Ferramenta oficial mantida pelo time do Internet Archive.

```bash
# 🔍 Busca de Metadados no Acervo
ia search 'title:"operating systems"' -f identifier -f title
ia search 'collection:softwarelibrary_msdos' -f identifier -f title

# 📄 Full-Text Search (FTS) dentro do conteúdo de livros e documentos
ia search -F 'eBPF networking kernel'

# 📋 Exibir Metadados Completos de um Item em JSON
ia metadata <identifier>

# 💾 Download Direto de Arquivos de um Item
ia download <identifier> --glob="*.pdf"
ia download <identifier> --destdir=~/Downloads
```

---

## 7. Governança, Safety Fence e Auditoria

A camada de pesquisa e extração opera sob as diretrizes estritas do [WEB_ALLOWLIST.md](file:///var/home/cloud/dev/linux/uBlueOs/bazzite-dx-silver-goggles/docs/WEB_ALLOWLIST.md):

* **Detecção Automática de Vazamento de Segredos**: Toda query ou prompt que contenha padrões de tokens (AWS, GitHub, Slack, OpenAI, GitLab ou chaves privadas RSA/SSH) é **bloqueada antes da transmissão** com erro `SECRET_DETECTED` e query redigida.
* **SSRF Guard no Loopback**: `mesh_fetch` bloqueia requisições a portas locais fora da faixa de serviços da malha (impedindo varreduras em portas de desenvolvimento ou daemons).
* **Proteção contra Loops**: Limite automático de 60 requisições por minuto (`MESH_RATE_LIMIT=60`).
* **Trilha de Auditoria**: Registro em tempo real em `~/.local/state/agent-mesh/audit.jsonl` com teto de rotação de 5 MB.

```bash
# 📋 Inspecionar histórico recente de auditoria
mesh-search audit

# 📊 Exibir resumo estatístico de latências, bloqueios de segurança e esferas
mesh-search audit --stats

# 🔬 Formato estruturado para consumo por subagentes
mesh-search audit --stats --json
```

---

## 8. Solução de Problemas Comuns (Troubleshooting)

* **SearXNG retornando 502 no primeiro comando após o boot**:
  * O `mesh-search` já gerencia o auto-start com tolerância de 25s. Caso ocorra timeout manual: `ujust searxng-up`.
* **Vane com erro *"Failed to connect to the server"***:
  * O Vane precisa do Ollama para listar provedores de modelo. Rode `ujust vane-up` (que inicializa o Ollama GPU automaticamente).
* **Liberar VRAM da NVIDIA após usar Deep Research**:
  * Rode `ujust ollama-down`.
* **Erro de certificado SSL no Trawl proxy**:
  * O certificado CA é gerado automaticamente em `/var/srv/trawl/ca/proxy-ca.crt`. O `mesh-search` o consome de forma transparente.
* **Query bloqueada por Safety Fence (`SECRET_DETECTED`)**:
  * Verifique se o comando ou script não está acidentalmente concatenando variáveis de ambiente ou arquivos contendo tokens/chaves privadas no texto da busca. Consulte `mesh-search audit` para detalhes.
