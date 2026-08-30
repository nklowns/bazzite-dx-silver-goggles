# 🔬 Virtualization Findings Ledger

Registro **grepável** de sintoma → causa → solução declarativa, para o pipeline de VMs
(macOS/Windows/Linux sobre KVM/QEMU no Dell G15 5520 / Bazzite-DX).

> **Como usar**: bateu um erro? `rg -i "<trecho literal do erro>" docs/VIRT-FINDINGS.md`.
> Cada achado tem o texto exato do sintoma para o grep casar.
>
> **Como escrever**: um achado por seção, id `F-NNN` imutável, sempre com os 5 campos
> (Sintoma / Causa / Solução declarativa / Detecção rápida / Estado). Achado que amadurece
> e vira procedimento migra para [`VIRTUALIZATION-COOKBOOK.md`](./VIRTUALIZATION-COOKBOOK.md)
> — mas a entrada aqui **permanece**, com link, para o grep continuar funcionando.

**Convenções de caminho**

| Papel | Caminho |
|---|---|
| SSOT de ferramentas (`vm-rail`, `vm-vision`) | `~/dev/IDEs/global-harness/bin/` → sync via `sync-harness.sh` |
| Domínios libvirt macOS | `qemu:///system` — `macos-ventura`, `macos-sonoma`, `macos-sequoia`, `macos-tahoe` |
| Discos + rails libvirt | `/var/home/cloud/dev/Virtual Machines/macos[/sonoma|/sequoia]/.rails/` |
| Stack acelerada Vulkan | `/var/home/cloud/dev/tools/reims-vgpu` (QEMU in-tree próprio) |
| Matriz de benchmark | [`../virtualization/benchmarks/matrix.yml`](../virtualization/benchmarks/matrix.yml) |

---

## Índice

| ID | Título | Severidade | Estado |
|---|---|---|---|
| [F-001](#f-001) | `qemu-xhci` derruba o input no macOS Sonoma+ (`kernel_task` 700%) | 🔴 Alta | ✅ Resolvido |
| [F-002](#f-002) | Topologia P/E-core assimétrica causa panic do XNU | 🔴 Alta | ✅ Resolvido |
| [F-003](#f-003) | macOS Tahoe 16: `Unable to Recover: Your Mac could not be recovered` | 🟡 Média | 🔬 Aberto |
| [F-004](#f-004) | `vm-vision` não enxerga guests do `reims-vgpu` (sem VNC, sem domínio libvirt) | 🔴 Alta | ✅ Resolvido |
| [F-005](#f-005) | Rail `macos-13` do reims-vgpu semeado do disco **live**, não do golden | 🟡 Média | ✅ Resolvido |
| [F-006](#f-006) | `vm-vision` perde teclas: eventos RFB em lote num único `sendall` | 🔴 Alta | ✅ Resolvido |
| [F-007](#f-007) | Ponteiro não responde a eventos RFB nos guests macOS | 🔴 Alta | ✅ Resolvido |
| [F-008](#f-008) | Chords com modificador não chegam via keysym RFB (`Super_L` ≠ Command) | 🔴 Alta | ✅ Resolvido |

---

<a id="f-001"></a>
## F-001 — `qemu-xhci` derruba o input no macOS Sonoma+

**Severidade** 🔴 Alta · **Afeta** macOS 14 (Sonoma), 15 (Sequoia) · **Estado** ✅ Resolvido

### Sintoma
Guest boota até o desktop, mas mouse e teclado congelam em segundos. No guest,
`kernel_task` sobe para ~700% de CPU. No host, a vCPU correspondente satura sem
carga real de trabalho.

### Causa
Regressão no driver XHCI do XNU 23+ conversando com o controlador emulado
`qemu-xhci`. O guest entra em laço de polling/reset do controlador.

### Solução declarativa
Trocar o controlador USB por topologia **EHCI + companion UHCI** no XML do domínio:

```xml
<controller type='usb' index='0' model='ich9-ehci1'/>
<controller type='usb' index='0' model='ich9-uhci1'>
  <master startport='0'/>
</controller>
<controller type='usb' index='0' model='ich9-uhci2'>
  <master startport='2'/>
</controller>
<controller type='usb' index='0' model='ich9-uhci3'>
  <master startport='4'/>
</controller>
```

Aplicado em `virtualization/templates/macos.xml` — não editar o XML do domínio à mão.

### Detecção rápida
```bash
virsh -c qemu:///system dumpxml macos-sonoma | grep -A2 "controller type='usb'"
# 'qemu-xhci' presente em guest 14+ == bug latente
```

### Notas
`reims-vgpu/vm/boot-x86.sh` ainda monta `-device qemu-xhci` + `-device usb-ehci`
na linha base. Ver **F-004** — o caminho acelerado não herda o fix do XML libvirt.

---

<a id="f-002"></a>
## F-002 — Topologia P/E-core assimétrica causa panic do XNU

**Severidade** 🔴 Alta · **Afeta** todas as versões macOS no i7-12700H · **Estado** ✅ Resolvido

### Sintoma
Kernel panic durante o boot, ou instalador que nunca chega ao Setup Assistant.
O XNU não modela CPUs heterogêneas x86 (P-cores + E-cores do Alder Lake).

### Causa
`host-passthrough` expõe a topologia híbrida real. O XNU assume núcleos homogêneos
com o mesmo conjunto de features e a mesma frequência base.

### Solução declarativa
Modelo de CPU **simétrico** com feature set explícito, em vez de passthrough:

- Modelo: `Cascadelake-Server-noTSX`
- Features exigidas pelo guest: AVX2, FMA, BMI1/2, AES, SSE4.2
- Desabilitar: `hle`, `rtm`
- OpenCore: spoof Comet Lake `0x000906EA`, SMBIOS `iMacPro1,1`, `CryptexFixup`

Fixado em `virtualization/templates/macos.xml` (commit `e2ad251`).
No `reims-vgpu`, equivalente em `boot-x86.sh`:
`-cpu ${CPU_MODEL},-hle,-rtm,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on`.

### Detecção rápida
```bash
virsh -c qemu:///system dumpxml macos-ventura | grep -A3 '<cpu'
# mode='host-passthrough' em guest macOS == panic garantido
```

---

<a id="f-003"></a>
## F-003 — macOS Tahoe 16: `Unable to Recover: Your Mac could not be recovered`

**Severidade** 🟡 Média · **Afeta** macOS 16 (Tahoe), XNU 25 · **Estado** 🔬 Aberto

### Sintoma
Kernel XNU 25 boota limpo com a topologia simétrica de **F-002**, mas o Recovery
Assistant aborta com a mensagem literal:

```
Unable to Recover
Your Mac could not be recovered
```

Evidência: `artifacts/macos-tahoe-after-continue.png` (erro) e
`artifacts/macos-tahoe-boot-log.png` (boot limpo do kernel).

### Causa
O instalador do Tahoe passou a checar hardware Apple Silicon / chip de segurança T2
em runtime. O boot do kernel não é mais suficiente — o instalador valida atestação
de firmware antes de prosseguir.

### Solução declarativa
**Ainda não existe.** Direções candidatas, não validadas:

1. Patch de SMBIOS/firmware no OpenCore para atestar presença de T2.
2. Trocar o SMBIOS de `iMacPro1,1` para um modelo Intel+T2 (`iMac20,x` / `MacPro7,1`).
3. Aguardar patches upstream do OpenCore para XNU 25.

### Detecção rápida
```bash
vm-vision wait-text macos-tahoe "could not be recovered" --timeout 300
```

### Notas
Não é bloqueio de kernel — é bloqueio de instalador. Ventura/Sonoma/Sequoia não são
afetados. Não gastar ciclo aqui antes das Fases 1–2 fecharem.

---

<a id="f-004"></a>
## F-004 — `vm-vision` não enxerga guests do `reims-vgpu`

**Severidade** 🔴 Alta · **Afeta** todo benchmark acelerado · **Estado** ✅ Resolvido
**Descoberto e corrigido em** 2026-08-30

### Sintoma
Qualquer verbo de visão (`scan`, `wait-text`, `click-text`, `record`, `screenshot`)
falha ou retorna vazio contra um guest iniciado por
`reims-vgpu/vm/boot-x86.sh`. Nenhum erro óbvio de conexão — simplesmente não há alvo.

### Causa
Dois pressupostos embutidos no `vm-vision`, ambos violados pelo caminho acelerado:

1. **Descoberta do alvo**: `get_vnc_port()` resolve a porta lendo
   `virsh dumpxml <vm>` → `<graphics type='vnc' port=…>`. O `boot-x86.sh` sobe QEMU
   **raw**, sem domínio libvirt — `dumpxml` retorna erro, a porta vira `None`.
2. **Transporte**: mesmo com a porta conhecida, não há servidor VNC. O `boot-x86.sh`
   apresenta o framebuffer numa janela **winit/Wayland** (`REIMS_VGPU_WINDOW=1`, com
   QEMU em `-display none`) ou via `-display gtk`. Nenhum dos dois fala RFB.

Consequência de projeto: a Fase 1 do benchmark assume automação por OCR nas duas
pernas (Vulkan e `vmware-svga`), mas só a perna libvirt é observável hoje.

### Solução declarativa
O plano inicial era anexar um `-vnc` ao `boot-x86.sh` como canal lateral. **Não é
necessário** — e a correção do desenho importa, porque teria criado drift num repo
upstream limpo (`steelbrain/reims-vgpu`) sem ganho.

O `boot-x86.sh` **já** abre `-qmp unix:$QMP_SOCK,server=on,wait=off`, e QMP é um
plano de controle completo por si só. Confirmado na árvore do QEMU 11.0.50 vendorizado:

| Comando | Origem | Serve para |
|---|---|---|
| `screendump` (com `format`, PNG desde 7.1) | `qapi/ui.json:198` | visão |
| `input-send-event` | `qapi/ui.json:1312` | controle |
| `query-status` | — | estado do guest |
| `query-cpus-fast` | `qapi/machine.json:142` | telemetria de vCPU |

Implementado no `vm-vision` (SSOT) como **transporte QMP de backend duplo**: todo
verbo que dependia de QMP passa por `qmp_run()`, que despacha para

- `virsh qemu-monitor-command <domínio>` — libvirt, caminho default, inalterado;
- socket unix falando QMP — QEMU raw, sem libvirt.

Seleção por `--qmp <socket>` (ou `VM_VISION_QMP`), aceita antes ou depois do
subcomando. `--vnc-port <N>` (ou `VM_VISION_VNC_PORT`) segue disponível para o
caminho RFB de baixa latência quando houver VNC.

**Zero patches no repo upstream.** O caminho libvirt foi testado por regressão
(boot, `status`, `screenshot`) e segue intacto.

### Detecção rápida
```bash
virsh -c qemu:///system dumpxml <vm> >/dev/null 2>&1 || echo "alvo não-libvirt: use --vnc-port"
```

### Notas
Medir FPS **pela janela winit**, não pelo VNC — o VNC tem cadência própria e
contaminaria a métrica de renderização.

---

<a id="f-005"></a>
## F-005 — Rail `macos-13` do reims-vgpu semeado do disco live, não do golden

**Severidade** 🟡 Média · **Afeta** comparabilidade da Fase 1 · **Estado** ✅ Resolvido
**Descoberto e corrigido em** 2026-08-30

### Sintoma
Comparação silenciosamente inválida: `macos-14` e `macos-15` batem md5 com seus
goldens, `macos-13` não. Nenhum erro é emitido — o benchmark rodaria e produziria
números não comparáveis entre versões.

Medido (primeiros 64 MiB, mesmo tamanho de arquivo nos três):

| rail | md5 (64 MiB) vs golden | md5 vs disco live | veredito |
|---|---|---|---|
| `macos-13` | ❌ difere | ✅ bate | drift |
| `macos-14` | ✅ bate | — | ok |
| `macos-15` | ✅ bate | — | ok |

### Causa
Os `base/` dos rails do reims-vgpu foram copiados em 30 ago 01:53–01:54. O golden do
Ventura foi congelado em 29 ago 20:30 — houve boot e escrita no disco live no intervalo,
e a cópia pegou o disco live. Sonoma e Sequoia foram capturados em 30 ago 01:36 e não
foram bootados depois, então live e golden coincidem por acaso, não por garantia.

Causa estrutural: os dois sistemas de rail (`vm-rail` para libvirt, `vm/disks/rails/`
para reims-vgpu) são **independentes**, sem procedência declarada. Nada amarra um
`base/` reims ao snapshot libvirt que o originou.

### Solução declarativa
1. Ressemear `macos-13/snapshots/base/macos.img` a partir do golden imutável:
   ```bash
   cp --reflink=auto -f \
     "/var/home/cloud/dev/Virtual Machines/macos/.rails/default/snapshots/ventura-golden-installed/macos-disk.qcow2" \
     "/var/home/cloud/dev/tools/reims-vgpu/vm/disks/rails/macos-13/snapshots/base/macos.img"
   chmod 444 <destino>
   ```
   Reversível: o golden é imutável (444) e o conteúdo atual do `base` continua existindo
   no disco live do libvirt. Nada é perdido.
2. Declarar procedência em [`../virtualization/benchmarks/matrix.yml`](../virtualization/benchmarks/matrix.yml)
   (campo `source_snapshot` por rail) e verificá-la antes de cada corrida.

### Detecção rápida
```bash
# comparar rail reims vs golden libvirt (barato: primeiros 64 MiB + tamanho)
head -c 64M <rail>/snapshots/base/macos.img | md5sum
head -c 64M <golden>/macos-*.qcow2 | md5sum
```

### Resultado da correção (2026-08-30)
Resseed executado. `macos-13/snapshots/base/macos.img` agora casa com o golden:

```
antes:  ce4155800587321771033068f0c60426   (== disco live do libvirt)
depois: a3d8625ee84e914628a5f80296068c14
golden: a3d8625ee84e914628a5f80296068c14   ✅
```

Os três rails estão em `provenance: verified` no `matrix.yml`.

### Notas
`head -c 64M` cobre header qcow2 + L1 + início da L2 — suficiente para pegar drift de
escrita, **não** é prova criptográfica de identidade total. Para o benchmark basta;
para atestação, hash completo.

**Melhoria estrutural pendente**: a verificação de procedência deve ser um *preflight*
automático do runner (comparar `source_snapshot` × `base/` antes de cada corrida), não
uma inspeção manual. Sem isso, o drift volta na próxima vez que alguém bootar um golden
em modo escrita. Endereçado no harness de benchmark.

---

<a id="f-006"></a>
## F-006 — `vm-vision` perde teclas: eventos RFB em lote num único `sendall`

**Severidade** 🔴 Alta · **Afeta** toda automação de teclado · **Estado** ✅ Resolvido
**Descoberto e corrigido em** 2026-08-30

### Sintoma
Texto digitado chega **truncado**, sem erro em lugar nenhum. Medido no Safari do
macOS Sequoia: `vm-vision type ... "example.com"` produziu `examp` na barra de
endereço. A chamada retorna `{"status": "success", "typed_length": 11}`.

Truncamento silencioso se parece com guest travado, não com input descartado — foi
exatamente essa a leitura errada durante o diagnóstico.

### Causa
`FastVNCClient.type_string()` montava a string inteira num `bytearray` e fazia **um
único `sendall`**, sem intervalo entre teclas. O teclado USB HID emulado não absorve
pares keydown/keyup entregues nessa cadência e o excedente é descartado. Mesmo padrão
em `send_keys()`.

### Solução declarativa
Uma escrita RFB **por tecla**, com pausa entre elas, em
`~/dev/IDEs/global-harness/bin/vm-vision` (SSOT):

- `type_string()`: um `sendall` por caractere + `time.sleep(KEY_DELAY_S)`.
- `send_keys()`: flush paginado de 8 em 8 bytes (um KeyEvent RFB por escrita).
- Knob: `VM_VISION_KEY_DELAY_MS`, default **12 ms**. Aumentar se ainda cair
  caractere; baixar para guests Linux, que toleram muito mais.

Não voltar a agrupar num `sendall` só — foi a regressão original.

### Detecção rápida
Digite uma string conhecida num campo de texto e compare com o que aparece. Se o
final some, é isto.

### Notas
Pacing **não** conserta chords com modificador nestes guests — ver **F-008**. Uma
versão anterior deste achado atribuía a barra de endereço esvaziada e o menu Apple
aberto a um `Cmd` preso por key-up descartado. **A evidência posterior derrubou essa
explicação**: com o pacing aplicado, nenhum chord tem efeito algum, então o `Cmd`
nunca chegou para ficar preso. O truncamento acima é medido; a causa daqueles dois
sintomas segue em aberto.

---

<a id="f-007"></a>
## F-007 — Ponteiro não responde a eventos RFB nos guests macOS

**Severidade** 🔴 Alta · **Afeta** `click`, `click-id`, `click-text`, `bootstrap-macos`
**Estado** ✅ Resolvido · **Descoberto e corrigido em** 2026-08-30

### Sintoma
Nenhum clique chega ao alvo. O cursor fica parado no canto superior esquerdo,
sobre o logo da Apple, e **não se move um pixel** por mais eventos que se envie.
`vm-vision click` retorna `{"status": "success"}` em todos os casos.

Sintomas secundários que enganam o diagnóstico: o menu Apple abre "sozinho", um
Enter posterior ativa o item destacado, e a janela do Safari perde foco. Tudo isso
lê como guest possuído ou travado — mas o guest está **ocioso e saudável** (relógio
avança, tela repinta, teclado responde).

### Causa
Não determinada. O que foi **descartado com medição**:

| Hipótese | Teste | Resultado |
|---|---|---|
| Guest travado / `kernel_task` a 700% (F-001) | `top -H` nas threads do QEMU | Todas as vCPU a **0%**. O `ps %CPU` de 237% era média de vida do processo, não instantâneo — leitura errada minha |
| Fix EHCI ausente | `dumpxml \| grep controller` | `ich9-ehci1` + 3 UHCI **já aplicados** |
| USB não enumerado | HMP `info usb` | Tablet e teclado presentes, 480 Mb/s |
| Ponteiro é relativo, cliques absolutos derivam | `query-mice` | Tablet HID é `current: true, absolute: true` |
| QEMU roteia para o tablet e descarta `rel` | HMP `mouse_set 2` (PS/2) + eventos `rel` | Cursor **continua imóvel** |
| Pilha HID travou pela tempestade de eventos | revert ao golden + boot limpo | Cursor **já nasce imóvel** |

Medição decisiva — dois frames com um `rel +600,+360` entre eles:

```
bbox das diferencas: (573, 710, 575, 726)
```

Uma região de **2×16 px**: o cursor de texto piscando no campo de senha. O ponteiro
não se moveu. O macOS simplesmente não consome nenhum dispositivo apontador aqui.

### Causa raiz (2026-08-30)
Nenhuma das três direções candidatas era o problema. O guest está inteiro:
`ioreg -c IOHIDDevice` dentro do macOS lista **"QEMU USB Tablet"** e
**"QEMU USB Keyboard"** — enumeração e binding de driver corretos.

O problema é **transporte**. O `FastVNCClient` do `vm-vision` entrega PointerEvent
por RFB, e esses eventos não movem o cursor neste guest. Os mesmos movimentos
enviados por **QMP `input-send-event` com eixos `abs`** funcionam perfeitamente.

O mapeamento é linear: `value = coord / dimensão * 0x7FFF` (`INPUT_EVENT_ABS_MAX`).
Verificado no meio e fora do centro:

| enviado | esperado (tela 1280x800) | cursor observado |
|---|---|---|
| `abs=(16383,16383)` = `0x7FFF/2` | (640, 400) | **(640, 405)** ✅ |
| `abs=(23040,24575)` | (900, 600) | **(900, 610)** ✅ |

Detalhe que custa tempo: **o primeiro evento `abs` depois de uma troca de
dispositivo é absorvido pelo guest.** Enviar a posição duas vezes resolve.

### Solução declarativa
`pointer_move_abs()` no `vm-vision` (SSOT) passou a emitir `abs` por QMP, e
`vnc_pointer_action()` faz o clique com eventos `btn` pelo mesmo caminho
(`backend: qmp_abs`). O caminho RFB continua no código mas é opt-in
(`VM_VISION_ABSOLUTE_POINTER`), porque não move nada aqui.

Serve aos dois backends de F-004 — libvirt e QEMU raw — sem código extra.

Validado ponta a ponta: `vm-vision click-text macos-sequoia "Wikipedia"` fez OCR
(confiança 0.97), clicou em (772, 297) e carregou `wikipedia.org` ao vivo.

### Detecção rápida
```bash
# dois frames com um movimento entre eles; se só o caret piscar, o ponteiro está morto
vm-vision screenshot <vm> -o /tmp/a.png
# ... enviar rel move ...
vm-vision screenshot <vm> -o /tmp/b.png
# comparar com PIL: ImageChops.difference(a, b).getbbox()
```

### Notas
`query-mice` reporta o dispositivo **que o QEMU entregaria**, não o que o guest
consome. Foi o que me levou ao diagnóstico errado de "ponteiro relativo" — anotado
aqui porque a distinção não é óbvia e vai enganar de novo.

O código já continha a pista: o caminho `bootstrap-macos` tinha um homing relativo
(`rel -2000,-2000` e passos de `+5`) que só existe se alguém já bateu neste muro.
Esse workaround também não move o cursor hoje.

---

<a id="f-008"></a>
## F-008 — Chords com modificador não chegam via keysym RFB

**Severidade** 🔴 Alta · **Afeta** toda automação que dependa de atalho
**Estado** ✅ Resolvido · **Descoberto e corrigido em** 2026-08-30

### Sintoma
`vm-vision send-key <vm> cmd l` e `cmd t` não produzem **efeito nenhum** no Safari:
a barra de endereço não foca, nenhuma aba abre. Sem erro; a chamada reporta sucesso
e lista as teclas enviadas. Teclas simples e `enter` no mesmo guest funcionam.

Testado em boot limpo do golden, **depois** do pacing de F-006 — portanto não é
overflow de eventos.

### Causa
**Namespace errado.** `send_keys()` emitia keysyms X11 por RFB e mapeava Command
para `Super_L` (`0xffeb`). O macOS não reconhece esse keysym como Command.

O QMP usa outro namespace — **qcodes do QEMU** — e ali a mesma tecla chama-se
`meta_l`. Pelo caminho qcode o chord idêntico funciona.

### Solução declarativa
`qmp_send_chord()` no `vm-vision` (SSOT): chords vão por
`input-send-event` com `{"key": {"type": "qcode", ...}}`, e `send_key()` tenta
esse caminho primeiro (`backend: qmp_qcode`), caindo para RFB só se a tecla não
estiver no `QCODE_MAP`. Modificadores são soltos em ordem inversa à de pressão,
para nada ficar preso.

Validação — `Cmd+T` abriu aba nova e focou a barra de endereço, comprovado por
diff de framebuffer (`bbox 151,77 -> 1092,105`, a barra de abas surgindo). Depois,
`Cmd+L` → digitar → Enter navegou para `example.com` ao vivo.

### Detecção rápida
```bash
vm-vision send-key <vm> cmd t   # nova aba no Safari: inócuo e visível
# nenhuma aba nova == chords não chegam
```

### Notas
Isto e **F-007** têm a mesma moral: nos guests macOS o **transporte RFB do
`vm-vision` não entrega input** — nem ponteiro, nem modificador — enquanto o QMP
entrega os dois. Teclas simples por RFB funcionam, o que mascara o problema e faz
parecer bug de guest.

Regra prática: **input por QMP, visão por screendump.** O RFB fica só como
caminho opcional de baixa latência para guests que comprovadamente o aceitem.
