# 🔬 Virtualization Findings — Guest & Firmware Domain

Registro **grepável** de sintoma → causa → solução declarativa para virtualização
nesta imagem. Escopo: fatos do **domínio** — comportamento de guest, firmware e
topologia de hardware — que valem para qualquer usuário e que a imagem pode
codificar de forma declarativa.

> **Como usar**: bateu um erro? `rg -i "<trecho literal do erro>" docs/VIRT-FINDINGS.md`.
> Cada achado guarda o texto exato do sintoma para o grep casar.
>
> **Como escrever**: um achado por seção, id `F-NNN` **imutável**, sempre com
> Sintoma / Causa / Solução declarativa / Detecção rápida / Estado. Achado que
> amadurece e vira procedimento migra para
> [`VIRTUALIZATION-COOKBOOK.md`](./VIRTUALIZATION-COOKBOOK.md) — a entrada aqui
> permanece, com link, para o grep continuar funcionando.

**O que NÃO entra aqui.** Achado que depende de um usuário, de um caminho em
`$HOME`, ou de ferramenta pessoal de automação não é domínio da imagem. Esses
vivem no ledger do harness, em `~/dev/IDEs/global-harness/vm/FINDINGS.md`. Os ids
são globais e não são reaproveitados, então as lacunas na numeração abaixo são
intencionais — aquele id existe, do outro lado.

**Verificação automática.** F-001 e F-002 não dependem de alguém lembrar: o
`dx-verify` afirma no build que `templates/macos.xml` carrega a topologia
correta e **não** carrega a que quebra. Ver `modules/dx-verify/dx-verify.sh`.

---

## Índice

| ID | Título | Severidade | Estado |
|---|---|---|---|
| [F-001](#f-001) | `qemu-xhci` derruba o input no macOS Sonoma+ (`kernel_task` 700%) | 🔴 Alta | ✅ Resolvido |
| [F-002](#f-002) | Topologia P/E-core assimétrica causa panic do XNU | 🔴 Alta | ✅ Resolvido |
| [F-003](#f-003) | macOS Tahoe 16: `Unable to Recover: Your Mac could not be recovered` | 🟡 Média | 🔬 Aberto |
| [F-009](#f-009) | Seletor do OpenCore espera seleção; NVRAM com caminho de dispositivo obsoleto | 🟡 Média | ✅ Explicado |
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

<a id="f-009"></a>
## F-009 — Boot pelo `boot-x86.sh` cai no seletor do OpenCore

**Severidade** 🟡 Média · **Afeta** corridas de benchmark pelo caminho reims-vgpu
**Estado** 🔬 Parcial — reproduzido e explicado, não reproduz em todos os rails
**Descoberto em** 2026-08-30

### Sintoma
O guest sobe, apresenta framebuffer, mas para no seletor gráfico do OpenCore
(OpenCanopy: dois ícones de disco, `EFI` e `Macintosh HD`, marca d'água
`REL-106-2025-11-03`) e **fica lá indefinidamente**. Nenhum input o move: nem
teclado nem ponteiro por QMP, nem `sendkey` por HMP.

Enganoso porque o guest está **saudável** — `query-status` diz `running`,
`info registers` mostra CPU executando o laço do OpenCanopy, e o framebuffer só
não muda porque nada acontece. Parece VM travada; é VM esperando.

### Causa
O serial nomeia o problema:

```
BdsDxe: failed to load Boot0080 "Mac OS X" from
  PciRoot(0x0)/Pci(0x1F,0x2)/Sata(0x1,0x0,0x0)/HD(2,GPT,...)/...boot.efi: Not Fo[und]
BdsDxe: loading Boot0000 "UEFI QEMU HARDDISK QM00017 " from
  PciRoot(0x0)/Pci(0x3,0x0)/Sata(0x2,0xFFFF,0x0)
```

A entrada NVRAM `Boot0080` grava o **caminho de dispositivo** do controlador
AHCI: `Pci(0x1F,0x2)`, que é onde o libvirt o coloca. O `boot-x86.sh` monta o
`ich9-ahci` em `Pci(0x3,0x0)`. Caminho diferente ⇒ entrada inválida ⇒ o firmware
cai no `Boot0000` (disco do OpenCore) ⇒ OpenCanopy abre e aguarda seleção.

No libvirt isso nunca aparece porque lá o `Boot0080` resolve e o firmware entra
direto no `boot.efi` do macOS — o seletor do OpenCore sequer é exibido.

### Escopo real — CORRIGIDO
Uma versão anterior deste achado dizia que o rail `macos-13` atravessava o boot
normalmente. **Errado**, e a origem do erro importa: veio de uma corrida do
`vm-bench` que reportava aprovação sem verificar nada (ver F-006/notas do runner).
Medido depois: `macos-13` para no mesmo seletor.

O seletor também aparece **sob libvirt** — o `macos-ventura` exibe três entradas
(EFI, macOS Base System, Macintosh HD) e fica esperando. Portanto não é
característica do caminho reims. O que varia por alvo é apenas se o OpenCore
**auto-seleciona**: sonoma e sequoia atravessam sozinhos, ventura não.

A causa do `Boot0080` inválido segue válida e explica por que o firmware cai no
OpenCore em vez de ir direto ao macOS. O que **não** era do NVRAM é a falta de
input — isso é **F-010**.

### O que foi descartado por medição
| Hipótese | Teste | Resultado |
|---|---|---|
| NVRAM do rail está velho | trocar `OVMF_VARS.fd` pelo do libvirt | seletor continua |
| OpenCore do rail difere do golden | md5 | `macos-14`/`macos-15` **idênticos** ao golden |
| Input não chega no firmware por rota de teclado | remover `usb-kbd` para o PS/2 assumir | sem efeito |
| OVMF sem driver XHCI (teclado nasce no XHCI) | `device_add usb-kbd,bus=ehci.0` | **inconclusivo**: hot-add depois da varredura do firmware não é reenumerado |

### Solução declarativa
**Ainda não existe** para o rail afetado. Direções candidatas, em ordem de custo:

1. Ressemear `OVMF_VARS.fd` do rail a partir de um boot que tenha gravado
   `Boot0080` **com o caminho de dispositivo do `boot-x86.sh`** — isto é, deixar
   o próprio caminho reims escrever seu NVRAM uma vez, em `--capture`, e
   congelar o resultado no snapshot.
2. Ajustar `Misc/Boot/Timeout` no `config.plist` dentro do `OpenCore.qcow2` do
   rail, para o seletor auto-selecionar em vez de esperar. Resolve o sintoma
   sem depender do NVRAM.
3. Nascer o teclado no EHCI em vez do XHCI, para dar input ao firmware — exige
   mexer na linha de comando do `boot-x86.sh` (repo upstream) e só vale se a
   direção 1 ou 2 falhar.

### Detecção rápida
```bash
rg -n "failed to load Boot0080" <RUN_DIR>/serial-*.log
```

### Notas
O `vm-bench` não trava nisso: o passo `login-screen` expira pelo `timeout_s` e
a corrida é marcada `failed` com o último frame salvo, em vez de consumir o
`hard_timeout_s` inteiro. Uma corrida que não alcança o SO **falha rápido** e
deixa evidência — a matriz inteira não é perdida por causa de um rail.

