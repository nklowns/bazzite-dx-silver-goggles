# 📖 Bazzite-DX Silver-Goggles: Virtualization & Workflow Cookbook

Este guia prático descreve os cenários de configuração, otimização e reversão de Máquinas Virtuais (VMs) no seu Dell G15 5520. Ele está dividido em duas opções arquiteturais: a **Opção A (Padrão Geral)** para fluxos paralelos de desenvolvimento e trabalho sem reiniciar a máquina, e a **Opção B (Opcional/Avançado)** para isolamento físico de GPU usando Passthrough e Looking Glass.

---

## 🏛️ Comparativo de Arquitetura

```mermaid
graph TD
    subgraph Opção A [Padrão Geral: Produtividade Sem Reiniciar]
        A1[Bazzite Host - NVIDIA RTX 3060] -->|Renderização Nativa| A2(Steam / Jogos / Dev no Host)
        A1 -->|KVM Hypervisor| A3(VM Windows - Apenas CPU/VirtIO)
        A3 -->|Conexão Sem Fio / RDP / SPICE| A1
        A3 -->|Acessa Docker do Host| A4[Gateway 192.168.122.1]
    end

    subgraph Opção B [Avançado: Passthrough Físico & Looking Glass]
        B1[Bazzite Host - Intel iGPU] -->|Interface KDE Wayland| B2(Looking Glass Client)
        B3[VM Windows - NVIDIA RTX 3060] -->|Renderização Física 3D| B4(Looking Glass Host)
        B4 -->|Frames de Vídeo| B5[/dev/kvmfr0 - SHM VRAM]
        B5 -->|Transmissão Sem Latência| B2
    end
```

---

## 🚀 Opção A: Virtualização Produtiva (Recomendado & Padrão Geral)

Esta configuração mantém a **GPU NVIDIA ativa no seu host Linux (Bazzite)** o tempo todo. Você não precisa reiniciar o computador nem desativar hardware ao alternar entre trabalho e lazer.

### Para quem é recomendado:
*   Desenvolvedores que rodam Docker, compiladores e ferramentas pesadas no Bazzite.
*   Quem joga títulos nativos ou via Proton/Steam diretamente no Linux.
*   Quem precisa da VM do Windows apenas para rodar ferramentas de escritório, VPNs corporativas e programas simples do Windows.

### 🔌 Integração de Rede (Docker & Tailscale)
*   **Docker no Host:** Por padrão, a VM Windows fica na rede NAT `192.168.122.0/24`. O host atua no IP **`192.168.122.1`**. Você pode acessar serviços expostos pelo Docker no host a partir da VM usando `http://192.168.122.1:PORTA`.
*   **Tailscale Coexistente:** O Tailscale pode ser executado no host e no guest simultaneamente. A VM aparecerá na sua Tailnet como uma máquina virtualizada própria com IP dedicado, permitindo comunicação de rede segura entre elas.

### 🛠️ Configuração da VM no Virt-Manager:
1.  **Habilitar Virtualização Segura (Simultaneous Graphics):**
    Execute `ujust setup-virtualization` e escolha **Setup Simultaneous Graphics (NVIDIA on Host + VM)**. Reinicie o computador.
2.  **Configuração de Disco e Rede:**
    *   No Virt-Manager, configure o barramento de disco como **VirtIO SCSI** (I/O de alto desempenho).
    *   Configure o modelo da placa de rede como **virtio**.
    *   Monte a ISO de drivers VirtIO na VM e instale o pacote `virtio-win-guest-tools.exe` para carregar todos os drivers.
3.  **Ajuste de CPU (XML):**
    Defina o modo de CPU como `<cpu mode='host-passthrough' check='none'/>` e aloque entre 8 a 12 vCPUs. O agendador híbrido do Linux fará a distribuição eficiente de threads entre os P-cores e E-cores do seu i7-12700H.
4.  **Acesso de Tela:**
    *   **Opção SPICE (Virt-Manager):** Fornece redimensionamento dinâmico automático da tela e compartilhamento de área de transferência (copiar/colar).
    *   **Opção RDP (Recomendado):** Habilite a "Área de Trabalho Remota" na VM e conecte a partir do host Bazzite via **KRDC** ou **Remmina** para obter a taxa de quadros e áudio mais fluidos possíveis.
    *   **Sunshine & Moonlight (Transmissão do Host):** Como a NVIDIA permanece ativa no Bazzite Host, você pode rodar o **Sunshine** no host Linux para transmitir sua área de trabalho e jogos nativos para dispositivos externos (ex: Steam Deck, smartphones ou TVs) usando o cliente **Moonlight** com codificação por hardware `NVENC` de ultra-baixa latência.

---

## 🎮 Opção B: GPU Passthrough Exclusivo (Opcional & Avançado)

Neste cenário, a **GPU NVIDIA é desvinculada do host Linux e dedicada 100% à VM Windows**. O desktop do Bazzite passa a rodar na iGPU Intel Iris Xe.

### Para quem é recomendado:
*   Quem precisa rodar aplicativos 3D de alta performance ou jogos que exigem aceleração física direta no Windows Virtualizado.
*   *Nota Crítica:* **Valorant (Vanguard) e Destiny 2 (BattlEye) não rodam em VMs sob nenhuma circunstância** devido ao bloqueio ativo de hypervisors pelo anti-cheat. Tentativas de contornar isso podem acarretar em banimento de conta.

### 🛠️ Passo a Passo de Configuração:

1.  **Isolar a GPU no Host:**
    Execute `ujust setup-virtualization` e escolha a opção **Setup Exclusive GPU Passthrough (NVIDIA for VM ONLY)**. Isso adicionará o driver `vfio-pci` às IDs da sua RTX 3060. Reinicie o host.
2.  **Configurar KVMFR (Looking Glass):**
    Execute `ujust setup-virtualization` e selecione **Enable KVMFR / Looking Glass Support**. O script criará o dispositivo `/dev/kvmfr0` com 128 MB e definirá as regras necessárias do SELinux.
3.  **Configurar a VM no Virt-Manager:**
    *   Adicione o hardware PCI correspondente à sua GPU NVIDIA (VGA e Áudio).
    *   Adicione a linha de memória compartilhada KVMFR no XML da VM, logo antes de `</devices>`:
        ```xml
        <shm dev='kvmfr0' size='128'/>
        ```
4.  **Instalação dos Softwares (Windows Guest):**
    *   Instale o driver oficial da NVIDIA GeForce e o aplicativo **Looking Glass Host**.
    *   **Monitor Fantasma Virtual:** Instale o `IddSampleDriver` no Windows caso você não possua uma tela física ou dongle HDMI fisicamente conectado às saídas ligadas diretamente à RTX 3060. Isso é vital para forçar a GPU dedicada a instanciar um framebuffer ativo para a cópia do Looking Glass.
5.  **Instalação e Uso do Cliente (Bazzite Host):**
    *   O cliente do Looking Glass já vem **pré-instalado nativamente** na imagem de fábrica `bazzite-dx-silver-goggles`. Não é necessário adicionar repositórios COPR ou empilhar pacotes no host.
    *   Inicie a VM e execute diretamente no terminal do host: `looking-glass-client`. Use a tecla **Scroll Lock** para capturar/liberar o controle de mouse e teclado.

### 📺 Alternativa de Streaming Sem Looking Glass: Sunshine & Moonlight
Se você preferir uma alternativa ao Looking Glass que forneça transmissão de áudio e vídeo de baixíssima latência (com suporte a HDR) de forma simplificada, você pode usar a combinação Sunshine + Moonlight:
1.  **No Windows Guest (VM):**
    *   Instale o **Sunshine** na VM.
    *   Nas configurações do Sunshine, force a captura e codificação de vídeo pela GPU NVIDIA via **NVENC** (o consumo de CPU será nulo porque o encoder é integrado de hardware na RTX 3060).
    *   *Nota:* O **IddSampleDriver** (monitor fantasma) é obrigatório aqui também para forçar a GPU dedicada a instanciar uma tela ativa na qual o Sunshine possa se acoplar.
2.  **No Bazzite Host:**
    *   O Bazzite traz o cliente **Moonlight** pré-instalado na imagem padrão (ou disponível no Flathub).
    *   Abra o Moonlight no host, insira o IP correspondente da VM (`192.168.122.X` ou o IP do Tailscale) e realize o emparelhamento com o Sunshine.
    *   A partir daí, você poderá transmitir a VM inteira em tela cheia a 60/120 FPS de forma fluida sem precisar gerenciar a memória compartilhada (SHM) do Looking Glass.

---

## ⚙️ Ajustes Finos Comuns de VM (Edição de XML)

Independente da opção escolhida, selecione a sua VM no Virt-Manager, acesse os detalhes, vá em *Preferences -> General* e marque a opção **Enable XML editing**. Aplique estas otimizações para refinar a experiência do Windows Guest:

### 1. Cursor de Baixa Latência (Mouse VirtIO)
Por padrão, o QEMU emula um dispositivo de tablet USB absoluto para gerenciar o cursor, o que introduz lag notável. Para remover o lag do mouse, procure pela linha:
```xml
<input type='tablet' bus='usb'/>
```
Substitua-a (ou adicione) por:
```xml
<input type='mouse' bus='virtio'/>
```

### 2. Aceleração de CPU Nativizada
Substitua a tag `<cpu>` correspondente por:
```xml
<cpu mode='host-passthrough' check='none'/>
```
Isso garante a exposição completa do conjunto de instruções do i7-12700H, eliminando perda de desempenho por tradução de instruções.

---

## 🔌 Recursos Adicionais de Produtividade (DX)

Para tornar o seu fluxo de desenvolvimento o mais completo e flexível possível, você pode incorporar os seguintes recursos à sua VM a partir do Virt-Manager:

### A. Compartilhamento de Pastas Host-Guest (Virtio-FS)
Em vez de configurar servidores Samba/LAN lentos para expor o código-fonte do seu projeto à VM Windows, utilize o **Virtio-FS** para mapear pastas do host Bazzite a taxas de transferência quase nativas:
1. Com a VM desligada no Virt-Manager, clique em *Add Hardware -> Filesystem*.
2. Defina o Driver como `virtiofs`.
3. Em **Source Path**, coloque o caminho do diretório no host Linux (ex: `/var/home/seu-usuario/workspace`).
4. Em **Target Path**, defina uma etiqueta identificadora simples (ex: `dev-workspace`).
5. Inicie a VM do Windows. No Windows, o serviço de montagem do Virtio-FS (instalado através do `virtio-win-guest-tools.exe`) mapeará automaticamente a pasta como uma unidade de rede local fluida.

### B. Redirecionamento de Dispositivos USB (Spice USB Passthrough)
Caso necessite expor pen-drives, dongles de autenticação USB ou controladores de hardware de forma dinâmica à VM:
1. No console do Virt-Manager da VM ativa, acesse a barra de menu superior: **Virtual Machine -> Redirect USB Device**.
2. Uma lista de dispositivos físicos USB conectados ao seu Dell G15 será exibida.
3. Marque o dispositivo desejado. Ele será desvinculado do host Bazzite e plugado de forma lógica na VM do Windows instantaneamente. Desmarque para retornar ao Linux.

### C. Aceleração 3D Virtualizada para VMs Linux (VirGL / Venus)
Se você precisar iniciar uma VM de testes Linux (como uma distribuição Ubuntu ou Fedora de desenvolvimento) no Virt-Manager:
*   Você **não** precisa de Passthrough de GPU física para obter aceleração gráfica de janelas e renderização 3D.
*   Nas propriedades de tela da VM Linux no Virt-Manager, acesse a placa gráfica (**Video**), defina o modelo como `virtio` e marque a opção **3D Acceleration**.
*   Nas configurações de **Display Spice**, marque a caixa **OpenGL** e selecione o adaptador gráfico da sua iGPU/dGPU. A VM rodará de forma extremamente rápida, renderizando as janelas diretamente na GPU física do host Linux em paralelo com o seu desktop principal.

---

## 🔄 Mecanismos de Reversão (Como desfazer as alterações)

> [!WARNING]
> Guarde estes comandos caso ocorra algum travamento, tela preta ou instabilidade ao tentar isolar a GPU.

### A. Desativar VFIO e Voltar para a Opção A (Padrão Geral)
Se o sistema apresentar tela preta após ativar a Opção B, selecione a implantação anterior do OSTree no menu do Grub durante o boot (ou abra o terminal do host Bazzite) e execute:
```bash
ujust setup-virtualization
```
Escolha a opção **Disable All Virtualization Kargs**.

*Ou faça manualmente via terminal:*
```bash
rpm-ostree kargs \
  --delete-if-present="intel_iommu=on" \
  --delete-if-present="amd_iommu=on" \
  --delete-if-present="iommu=pt" \
  --delete-if-present="kvm.ignore_msrs=1" \
  --delete-if-present="kvm.report_ignored_msrs=0" \
  --delete-if-present="kvmfr.static_size_mb=128" \
  --delete-if-present="vfio_pci.ids="
```
E reinicie o host. A GPU voltará a pertencer ao Bazzite.

### B. Limpar Configurações Locais e udev do KVMFR
Para remover regras udev e modprobe adicionadas para o Looking Glass:
```bash
sudo rm -f /etc/udev/rules.d/99-kvmfr.rules
sudo rm -f /etc/modprobe.d/kvmfr.conf
sudo rm -f /etc/libvirt/qemu.conf
sudo semodule -r kvmfr 2>/dev/null || true
```

### C. Desinstalar o Looking Glass Client do Host
```bash
sudo rm -f /etc/yum.repos.d/_copr_pgaskin-looking-glass-client.repo
rpm-ostree uninstall looking-glass-client
```

### D. Reverter Estado da Imagem do Sistema (OSTree Rollback)
Se alguma atualização da imagem gerou instabilidade operacional na sua camada customizada `silver-goggles`, utilize os comandos de rollback nativos do repositório:
*   **Desfazer rebase local recente:**
    ```bash
    just rollback-local
    ```
*   **Voltar para a imagem oficial de upstream (Bazzite-DX limpo):**
    ```bash
    just rebase-official
    ```

---

## 🔍 Diagnóstico e Resolução de Problemas: Erro de Permissão no Daemon QEMU

Se ao tentar rodar o `virt-manager` ou iniciar suas conexões você receber o erro:
`Failed to connect socket to '/var/run/libvirt/virtqemud-sock': No such file or directory`
ou logs do `virtqemud.service` indicando `invalid argument: Failed to parse user 'qemu'`, siga as instruções de diagnóstico abaixo.

### 🏛️ Análise Crítica: Por que esse problema ocorre?
Nos sistemas baseados em Fedora Atomic (ostree-like), a imagem é declarativa e imutável para a árvore `/usr`, mas o diretório `/etc` é um overlay persistente com escrita direta. 
1. Durante atualizações ou rebases, o ostree executa um merge de 3 vias (3-way merge) para mesclar as alterações de configuração no `/etc`.
2. Às vezes, este merge gera inconsistências locais nos bancos de dados de usuários e grupos (especialmente no `/etc/gshadow` e `/etc/group`), por exemplo, adicionando uma referência de grupo sem adicionar o respectivo usuário correspondente.
3. O `systemd-sysusers` (responsável por instanciar dinamicamente usuários e grupos do sistema no boot a partir de `/usr/lib/sysusers.d/*.conf`) falha de forma fatal ao encontrar qualquer inconsistência, como a existência parcial de um grupo/membro no `/etc/gshadow` que não está no `/etc/group`. Isso interrompe a criação do usuário `qemu` (e de outros como `clevis`, `dhcpcd` etc.), travando os daemons de virtualização que dependem deles.
4. **Por que não pode ser 100% declarativo?** O sistema de build (BlueBuild) define a configuração da imagem no repositório de forma declarativa (incluindo pacotes e arquivos sob `/usr/lib/sysusers.d`), mas ele não pode sobrescrever de forma arbitrária o estado persistente do `/etc` do cliente para não violar dados de login locais. Portanto, em caso de inconsistência de arquivos de credenciais locais, uma correção manual ou via scripts de runtime é requerida.

### 🛠️ Resolução da Inconsistência no Host (Passo a Passo)

1. **Corrija as inconsistências de grupos:**
   Execute a ferramenta de checagem no terminal do host:
   ```bash
   sudo grpck
   ```
   *O utilitário detectará as discrepâncias entre `/etc/group` e `/etc/gshadow` (incluindo o grupo órfão `qemu`). Responda **sim (y)** para que ele remova as entradas redundantes ou limpe as inconsistências.*

2. **Force a criação do usuário `qemu`:**
   Execute manualmente o processador do `sysusers` sem passar pelas verificações de estado do `systemd`:
   ```bash
   sudo systemd-sysusers
   ```

3. **Verifique se o usuário foi registrado:**
   ```bash
   getent passwd qemu
   ```
   *Deve retornar os dados do usuário, por exemplo:* `qemu:x:107:107:qemu user:/:/usr/sbin/nologin`

4. **Reinicie os sockets e daemons de virtualização:**
   ```bash
   sudo systemctl restart virtqemud.socket virtqemud.service
   ```
