# Adicionando uma capacidade

Uma capacidade é um poder que o usuário exerce — "rodar VMs", "castar do iPhone", "subir um LLM
local". Não é um pacote, nem uma receita, nem um container. O pacote é o *como*; a capacidade é o
*quê*. Este documento é o contrato mínimo para acrescentar uma sem transformar a imagem num
amontoado.

## A régua

**Jogos (Bazzite) > Dev > LLM (esta camada).** Antes de escrever a primeira linha:

- o tier de jogos é do Bazzite; esta camada não troca defaults, kargs, sessão, compositor ou a
  superfície `ujust` de gaming para servir dev/LLM;
- dev segue a doutrina de software do Bazzite (`ujust` → Flatpak → Homebrew → containers → imagem).
  Se Flatpak, Brew ou container resolvem, não entra em `packages/*.txt`;
- LLM/agentes são sempre opt-in: zero custo em idle até `ujust ...-up`.

## Anatomia

Toda capacidade declara as mesmas peças, no mesmo lugar:

| Peça | Onde | Regra |
| :--- | :--- | :--- |
| Motivo | uma frase no README ou no AGENTS | se não cabe em uma frase, são duas capacidades |
| Pacotes | `packages/<dominio>.txt` | só o que o user space não resolve; comentário com o porquê; weak deps **off** |
| Units | `files/system/usr/lib/systemd/…` | nasce inerte; `enable` no boot é exceção com custo medido |
| Portas | `61300–61399`, bind em `127.0.0.1` | `tailscale serve` só via `ujust remote-*-setup`; nunca 80/443 |
| Segredos | environment do GitHub ou `EnvironmentFile` | nunca no repo, nunca no layer |
| Assert | `scripts/verify-image.sh` ou `dx-verify` | nomeia a ferramenta que o usuário invoca, não o pacote |
| Remoção | um commit | apagar as linhas acima não pode deixar daemon, karg ou symlink |
| Doc | README/AGENTS | o que é, como sobe, como desce, o que custa |

## Checklist

- [ ] Cabe em user space? Se sim, é Flatpak/Brew/container — não é imagem.
- [ ] Qual o custo em idle/boot? Medido, não estimado. Se não mediu, não habilite no boot.
- [ ] Porta na faixa reservada, bind em loopback, e o `ujust remote-*-setup` publica com TLS via tailnet.
- [ ] O assert falha quando a ferramenta some? (teste injetando a remoção)
- [ ] A remoção é um commit, sem resíduo em `/etc`, `/var` ou kargs?
- [ ] `just check` e o CI passam; offline, `SKIP_NETWORK=1 just check`.

## Exemplos

**Serviço web** — Quadlet em `files/system/etc/containers/systemd/users/`, `ujust <nome>-up/down/status`,
`ujust remote-<nome>-setup` (tailscale serve), porta `613xx` em loopback, assert do endpoint local.
No upgrade do host, o container aparece no `Removed:` esperado.

**Ferramenta CLI** — vai para `*.Brewfile`, não para `packages/*.txt`. A exceção é o que precisa
existir antes do primeiro login ou fora do user space: kmod, udev, PAM, chave, serviço de sistema.

**Driver/kmod** — `build_files/` + módulo + kargs + `initramfs-etc`; assinatura e MOK são opt-in.
O `gpu_unlock` é o exemplo vivo: EAC Linux v2 e unlock são mutuamente exclusivos (AGENTS.md).

## Anti-padrões

- Pré-instalar o que o Bazaar já entrega ao usuário.
- Habilitar daemon no boot "porque é conveniente" (mysql, redis, PCP archival).
- Publicar em `0.0.0.0`: `tailscale0` está na zona `trusted`, então tudo vaza para a tailnet.
- Parser próprio quando existe formato nativo (`brew bundle` com stanza `flatpak`, `flatpak
  preinstall` com `.preinstall`, `kargs.d`, `tmpfiles.d`).
- Guard que compara a imagem nova com o release anterior: o histórico não é o contrato.
- Copiar unit para `$HOME`: sombreia o `/usr` e congela a versão.
