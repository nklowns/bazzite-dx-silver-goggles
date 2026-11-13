# 🔬 GPU Findings — NVIDIA dGPU (GA106M) & Saída HDMI

Registro **grepável** de sintoma → causa → solução para a dGPU nesta imagem.
Escopo: fatos do **domínio** (comportamento do driver, topologia da placa, política
de energia) que a imagem pode codificar de forma declarativa.

> **Como usar**: bateu um erro? `rg -i "<trecho literal do erro>" docs/GPU-FINDINGS.md`.
> Cada achado guarda o texto exato do sintoma para o grep casar.
>
> **Como escrever**: um achado por seção, id `G-NNN` **imutável**, sempre com
> Sintoma / Causa / Solução declarativa / Detecção rápida / Estado.
>
> **O que NÃO entra aqui.** Achado que depende de um usuário, de um caminho em
> `$HOME` ou de ferramenta pessoal (ex.: sessão Waydroid instalada como override
> local) vive no ledger do harness do usuário. Aqui fica só o que a imagem pode
> afirmar sobre hardware e driver.

**Topologia medida neste host (Dell G15 5520, RTX 3060 Mobile, `10DE:2560`).**
O painel interno é da **iGPU**: `card1-eDP-1` (`i915`, `8086:46a6`). A saída
**HDMI é da dGPU**: `card0-HDMI-A-1` (`nvidia`, `01:00.0`). Consequência prática:
qualquer coisa que derrube a dGPU leva o HDMI junto, sem tocar no painel interno.

| Saída | Card / driver | Dono |
|---|---|---|
| `eDP-1` (painel interno) | `card1` / `i915` | Intel Iris Xe |
| `HDMI-A-1` | `card0` / `nvidia` | RTX 3060 Mobile |
| `DP-1`, `DP-2` | `card1` / `i915` | USB-C / DP alt mode |

---

## Índice

| ID | Título | Severidade | Estado |
|---|---|---|---|
| [G-001](#g-001) | `nvUpdateFlipEvoHwState` NULL deref no shutdown → tela preta e host travado | 🔴 Alta | 🔬 Aberto (mitigação conhecida) |
| [G-002](#g-002) | `NV_ERR_RESET_REQUIRED` derruba o HDMI e só sai com ciclo completo de energia | 🔴 Alta | 🔬 Aberto (gatilho em investigação) |

---

<a id="g-001"></a>
## G-001 — `nvUpdateFlipEvoHwState` NULL deref no shutdown → tela preta e host travado

**Sintoma.** Ao reiniciar com o driver `615.78.08` (open), o KWin é morto
(`SIGKILL` depois de `plasma-plasmashell.service: State 'stop-sigterm' timed out`)
e o kernel toma page fault; a tela fica preta e a máquina não responde ao reboot:

```
BUG: unable to handle page fault for address: 0000000000005320
Oops: 0000 [#1] SMP NOPTI
RIP: 0010:nvUpdateFlipEvoHwState+0x69f/0xb50 [nvidia_modeset]
Call Trace: nvSetDispModeEvo → nvKmsIoctl → ApplyModeSetConfig →
            nv_drm_atomic_apply_modeset_config → drm_atomic_commit →
            drm_client_modeset_commit → __drm_fb_helper_restore_fbdev_mode_unlocked →
            drm_fbdev_client_restore → drm_client_dev_restore → drm_release
note: kwin_w:traceq0[4281] exited with irqs disabled
Fixing recursive fault but reboot is needed!
```

**Causa.** `nvidia-drm.fbdev=Y` (default do driver, não é karg desta imagem) cria
um cliente fbdev, mas a dGPU **não tem CRTC/saída conectada no boot** — o log
mostra `nvidia 0000:01:00.0: [drm] Cannot find any crtc or sizes` e **nenhum
`/dev/fb*` existe**. No `drm_release` do último fd (compositor encerrando), o
restore do fbdev é chamado com config vazia e o driver dereferencia NULL
(`CR2=0x5320`). Sem cliente fbdev, esse caminho de código não existe.

**Solução declarativa (não aplicada ainda — decisão do dono).**
`files/system/usr/lib/modprobe.d/zz-nvidia-drm.conf` com
`options nvidia_drm modeset=1 fbdev=0`. Preferir modprobe.d a karg: nesta imagem
kargs declarados em `/usr/lib/bootc/kargs.d` só convergem via `ujust dx-kargs`
no host rpm-ostree. Não se perde nada aqui: o painel interno é `i915`, e o fbdev
da dGPU nem chega a inicializar.

**Detecção rápida.**

```bash
cat /sys/module/nvidia_drm/parameters/fbdev      # Y = caminho do bug armado
ls /dev/fb* 2>/dev/null                          # vazio + fbdev=Y = config sem CRTC
journalctl -k -b -1 | rg -i 'nvUpdateFlipEvoHwState|Fixing recursive fault'
```

**Estado.** Aberto. Bug do driver (não do kernel: ocorre em `nvidia_modeset`,
com `[nvidia_modeset]` no RIP). Re-testar após update do driver.

---

<a id="g-002"></a>
## G-002 — `NV_ERR_RESET_REQUIRED` derruba o HDMI e só sai com ciclo completo de energia

**Sintoma.** A segunda tela (HDMI) para de funcionar sem erro de desktop e não
volta com reboot. No kernel, repetidamente:

```
NVRM: GPU0 vaspaceapiConstruct_IMPL: Could not construct VA space. Status 62
NVRM: GPU0 nvAssertFailedNoLog: Assertion failed: NV_OK == status @ gpu_vaspace.c:4921
```

**Causa.** `Status 62` = `NV_ERR_RESET_REQUIRED`: a GPU tomou uma exceção fatal e
o driver passa a recusar qualquer novo contexto/VA space. Com o HDMI na dGPU
(G-001), a saída morre junto. **Reboot a quente não reseta a dGPU** — só o corte
de energia (power cycle real, incluindo o `EC`) devolve a placa ao estado normal.

No caso medido em 2026-11-13, o reset-required apareceu 20 ms depois de um
crash-loop do guest Waydroid (`com.android.settings`, `RenderThread sig=6`), com
o binder de 1 MB esgotado (`binder_alloc_buf size 32 failed, no address space`) e
34.725 falhas de VA space no mesmo boot. O guest só usa a dGPU
(`waydroid.cfg: drm_device = /dev/dri/renderD129`), e o tombstone da sessão mostra
a assinatura do estado quebrado: `surfaceflinger` abortando em
`SkiaGLRenderEngine::chooseEglConfig` com `no suitable EGLConfig found, giving up`.
**A ordem exata (app primeiro vs. GPU primeiro) ficou indeterminada** porque os
tombstones do incidente foram rotacionados; o que está provado é que, com a GPU
em 62, o guest entra em loop e amplifica o dano.

**Solução declarativa.** Nenhuma confirmada. O que é fato e reversível:
(1) não contar com warm reboot — power cycle é o único reset; (2) não rodar
sessão Waydroid concorrente com trabalho de GPU (llama/Comfy) até o gatilho
primário ser identificado.

**Detecção rápida.**

```bash
cat /sys/class/drm/card0-HDMI-A-1/status        # disconnected com cabo plugado = suspeita
wc -c < /sys/class/drm/card0-HDMI-A-1/edid      # 0 B = sem EDID
rg -c 'monitor_present\s+1' /proc/asound/card0/eld#*   # ELD prova que o sink respondeu
journalctl -k -b -1 | rg -c 'Status 62'         # >0 = GPU precisou de reset
```

Um monitor conectado e saudável responde nas **duas** vias: EDID de 256 B no
conector e `monitor_present 1` / `eld_valid 1` no ELD do codec HDMI da NVIDIA.
Se o ELD responde e o conector diz `disconnected`, o problema é do lado da dGPU,
não do cabo.

**Estado.** Aberto. Gatilho primário em investigação com o agente
`waydroid@bazzite-dx-silver-goggles` (Paseo), registrado no ledger do harness.
