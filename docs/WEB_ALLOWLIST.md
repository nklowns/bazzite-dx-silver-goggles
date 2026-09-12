# 🌐 Agent Mesh — Web Governance, Allowlist & Safety Fence Policy

> **Target Platform**: Bazzite Atomic (Fedora Silverblue, Dell G15 5520, KDE/NVIDIA)  
> **Ecosystem**: Universal Blue / Project NOMAD  
> **Status**: Declarative, Audited & Enforced  

---

## 1. Princípios Fundamentais de Governança

A infraestrutura da **Agent Mesh** provê aos agentes autônomos (AGY, Claude Code, subagentes e scripts locais) uma capacidade sem precedentes de pesquisa profunda, metapesquisa transversal e extração em Markdown limpo.

Para assegurar **privacidade total**, **integridade do host** e **uso consciente de largura de banda**, todas as requisições passam pela camada de governança do `mesh-search`:

1. **High Signal-to-Noise Ratio (SNR) First**: Prioridade máxima a fontes primárias de engenharia, preprints acadêmicos, bases de código abertas e a Small Web não-comercial. Descarte ativo de clones de IA e fazendas de SEO.
2. **Safety Fence contra Vazamento de Segredos**: Varredura heurística preventiva por regex em toda query de busca e prompt de pesquisa profunda antes de trafegar pela rede.
3. **SSRF Guard & Proteção de Loopback**: Bloqueio de esquemas perigosos (`file://`) e acesso restrito de `mesh_fetch` no loopback (`127.0.0.1` / `localhost`) estritamente às portas autorizadas da malha DX.
4. **Proteção contra Loops Desgovernados**: Limitação deslizante de requisições por minuto (`MESH_RATE_LIMIT=60`) para prevenir sobrecarga de servidores upstream.
5. **Trilha de Auditoria Imutável**: Registro estruturado de todas as ações, latências, categorias e violações de segurança em `~/.local/state/agent-mesh/audit.jsonl` com rotação automática.

---

## 2. Diretório de Esferas e Domínios de Alta Confiança

| Esfera / Categoria | Bangs / Apelidos | Fontes Primárias & Domínios Recomendados | Motores Utilizados |
| :--- | :--- | :--- | :--- |
| **`it`** (Engenharia & TI) | `!it`, `!gh`, `!gl`, `!al`, `!so`, `!pypi`, `!crates`, `!nvd`, `!hf` | `docs.fedoraproject.org`, `docs.bazzite.gg`, `universal-blue.org`, `blue-build.org`, `wiki.archlinux.org`, `kernel.org`, `bugzilla.redhat.com`, `github.com`, `gitlab.com`, `pypi.org`, `crates.io`, `docs.rs`, `pkg.go.dev`, `repology.org`, `nvd.nist.gov`, `huggingface.co`, `developer.mozilla.org` | GitHub, GitLab, ArchWiki, StackOverflow, PyPI, Crates, Repology, NVD, Docker Hub |
| **`science`** (Ciência & Literatura) | `!science`, `!arxiv`, `!sem`, `!zlib`, `!annas` | `arxiv.org`, `semanticscholar.org`, `openalex.org`, `ncbi.nlm.nih.gov`, `annas-archive.org`, `openlibrary.org`, `archive.org` | arXiv, Semantic Scholar, OpenAlex, PubMed, Anna's Archive, Z-Library |
| **`indie`** (Small Web) | `!indie`, `!marginalia`, `!neocities`, `!smallweb`, `!blogs` | `marginalia.nu`, `neocities.org`, `wiby.me`, blogs pessoais de engenharia de sistemas e phlogs em texto puro | Marginalia, Neocities, Mwmbl |
| **`p2p`** (Redes Descentralizadas) | `!p2p`, `!mwmbl`, `!yacy` | `mwmbl.org`, nós YaCy públicos comunitários (ex: `yacy.kit.edu`), DHT YaCy local | Mwmbl, YaCy DHT |
| **`archive`** (Web Histórica) | `!archive`, `!openlib`, `!zlib`, `!locgov`, `!history` | `web.archive.org`, `archive.today`, `archive.is`, `archive.ph`, `loc.gov` | OpenLibrary, Library of Congress, Anna's Archive, Wayback Machine |
| **`local`** (Workspace Pessoal) | `!local`, `!recoll`, `!workspace`, `!files`, `!notes` | Pastas locais montadas em `:ro`: `~/dev`, `~/Documents` | Recoll Xapian WebUI (`:61389`) |
| **`gemini`** (Geminispace) | `!gemini`, `!kennedy`, `!capsule` | Cápsulas de desenvolvedores no protocolo `gemini://` via TLS nativo porta `1965` | Kennedy Gemini Search (`gemini://kennedy.gemi.dev`) |
| **`general`** (Surface Web) | `!general`, `!br`, `!wp`, `!wd` | `w3.org`, `rfc-editor.org`, `ietf.org`, `wikipedia.org`, `wikidata.org` | Brave, Google CSE, Mojeek, Qwant, Wikipedia |
| **`onions`** (Darknet Tor) | `!onions`, `!ahmia`, `!onion` | Espelhos técnicos `.onion` roteados estritamente via SOCKS5 (`127.0.0.1:9050`) | Ahmia (`ahmia.fi`) |
| **`i2p`** (Darknet I2P) | `!i2p`, `!i2psearch`, `!legwork` | Eepsites técnicos `.i2p` roteados estritamente via proxy HTTP (`127.0.0.1:4444`) | I2P Search, Legwork, Idk.i2p |

---

## 3. Anti-Patterns e Restrições Ativas (Safety Fence)

### 3.1 Vazamento de Credenciais (Secret Leak Guard)
Toda query enviada a `mesh_search` ou prompt a `mesh_research` é inspecionada contra padrões conhecidos de credenciais antes de atingir qualquer motor externo:
- **AWS**: `AKIA...` e strings de chave de acesso.
- **GitHub**: Tokens clássicos `ghp_...`, PATs refinados `github_pat_...` e OAuth `gho_...`.
- **Slack**: Tokens `xox[baprs]-...`.
- **OpenAI / Anthropic**: Chaves `sk-...`, `sk-proj-...`, `sk-ant-...`.
- **GitLab**: Tokens pessoais `glpat-...`.
- **Chaves Privadas**: Blocos `-----BEGIN [RSA|EC|DSA|OPENSSH] PRIVATE KEY-----`.

> [!CAUTION]
> Quando um padrão de segredo é detectado, a operação é **bloqueada imediatamente**, a query é substituída por `[REDACTED]` no log de auditoria, e o agente recebe o código de erro `SECRET_DETECTED`.

### 3.2 SSRF e Restrição de Portas no Loopback
Para evitar que agentes autônomos realizem varreduras cegas ou extraiam dados de serviços internos da máquina (bancos de dados, daemons de contêineres, webhooks de desenvolvimento):
- **Esquemas Bloqueados**: `file://`, `ftp://`, `gopher://`, `dict://`. Apenas `http://`, `https://` e `gemini://` são admitidos.
- **Cloud Metadata Bloqueado**: Qualquer requisição para `169.254.169.254`, `metadata.google.internal` ou sub-redes link-local `169.254.0.0/16` é imediatamente abortada.
- **Whitelist Estrita de Portas Loopback**: Requisições de `mesh_fetch` para `127.0.0.1` ou `localhost` são aceitas **apenas** para as portas DX da Agent Mesh:
  - `1965` (Gemini TLS)
  - `4444`, `4447`, `7070` (i2pd Proxy e Console)
  - `8090` (YaCy Web)
  - `8191`, `8192` (Trawl API e Proxy)
  - `9050`, `9080` (Tor SOCKS5 e HTTP Tunnel)
  - `9225` (Lightpanda CDP)
  - `11434`, `61382` (Ollama GPU)
  - `61385` (Vane)
  - `61387` (SearXNG)
  - `61389` (Recoll)
  Qualquer outra porta local (como `22` SSH, `2375` Docker, `3000` Node, `5432` PostgreSQL) é rejeitada com `URL_SAFETY_VIOLATION`.

### 3.3 Fazendas de Conteúdo e Lixo de SEO (Evitar Ativamente)
Os agentes devem preferir as esferas `it`, `science` e `indie` para evitar:
- Fazendas de tradução automática e scrapers de fóruns técnicos (ex: agregadores de cópias de StackOverflow com anúncios pesados).
- Spams gerados por IA sem citação de fontes primárias.
- Portais com paywall agressivo ou captchas maliciosos (quando inevitáveis, o agente deve usar a flag `--archive` ou deixar o Trawl atuar como fallback de Tier 3).

---

## 4. Telemetria e Comandos de Auditoria

O estado de governança pode ser inspecionado a qualquer momento pelos desenvolvedores ou agentes:

```bash
# Exibir os últimos 15 eventos registrados
mesh-search audit

# Exibir os últimos 50 eventos com resumo estatístico
mesh-search audit -n 50 --stats

# Resumo estatístico em formato JSON (ideal para subagentes)
mesh-search audit --stats --json
```

---

## 5. Rotação de Logs e Higiene de Armazenamento

- **Local do Arquivo**: `~/.local/state/agent-mesh/audit.jsonl`
- **Permissões**: Diretório `0700`, arquivo `0600` (visível exclusivamente pelo usuário local `1000:1000`).
- **Teto de Rotação**: Limite de 5 MB por arquivo. Ao atingir 5 MB, o arquivo atual é renomeado para `audit.jsonl.1` e um novo arquivo vazio é iniciado.
- **Zero Impacto no Host**: O log reside no subvolume do usuário e tem teto rígido de ~10 MB total, garantindo conformidade com a política do Fedora Silverblue / Bazzite.
