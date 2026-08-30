# 📖 Bazzite-DX Silver-Goggles: Virtualization & Workflow Cookbook

Este guia prático descreve os cenários de configuração, otimização, alternativas de gerenciamento e reversão de Máquinas Virtuais (VMs) no seu Dell G15 5520. Ele está estruturado para fornecer uma visão abrangente de Developer Experience (DX) em sistemas operacionais atômicos imutáveis baseados em Fedora Silverblue/Bazzite.

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
    > [!IMPORTANT]
    > **Ajustes de Bind e Firewall:**
    > 1. Para que o serviço no Docker seja alcançável pela VM, ele deve estar escutando na interface de rede correta (ex: bind em `0.0.0.0` ou explicitamente no gateway, e não apenas em `127.0.0.1`).
    > 2. O `firewalld` ativo no Bazzite bloqueia conexões vindas da rede de virtualização (`virbr0`) por padrão. Para liberar o tráfego de rede da VM para serviços no host, adicione a interface da rede virtual à zona confiável do firewall:
    >    ```bash
    >    sudo firewall-cmd --zone=trusted --add-interface=virbr0 --permanent
    >    sudo firewall-cmd --reload
    >    ```
*   **Tailscale no Host e no Guest:** O Tailscale pode ser executado no host e no guest simultaneamente para expor a VM diretamente.
    > [!WARNING]
    > **Conflitos com VPNs Corporativas:** Se a VM Guest ativar uma VPN estrita (como Netskope), o adaptador virtual do Tailscale dentro do guest perderá a conexão e as rotas. Nesse cenário, o Tailscale deve rodar **apenas no Host**. Para acessar a VM remotamente, use a técnica de **RDP Relay no Host** e conexões pela rede Host-Only, conforme detalhado no [Cenário Avançado (Desenvolvimento Híbrido Remoto)](#-cenario-avancado-desenvolvimento-hibrido-com-codigo-e-vpn-isolados-no-guest-ex-netskope-e-idedocker-no-host).

### 🛠️ Configuração Básica da VM
1.  **Verificar Infraestrutura de Virtualização (IOMMU):**
    Na imagem `bazzite-dx-silver-goggles`, os kargs `intel_iommu=on`, `iommu=pt` e `kvm.ignore_msrs=1` já vêm **baked no build da imagem** via `silver-goggles.yml`. Nenhum passo manual de habilitação é necessário. Para desabilitá-los, `ujust setup-virtualization virt-off` usa `rpm-ostree kargs --delete-if-present`, que funciona mesmo em kargs baked — o OSTree mantém a remoção através de updates.

    Para confirmar que IOMMU está ativo no sistema atual:
    ```bash
    ujust setup-virtualization  # escolha "Check Virtualization Readiness (Status)"
    # ou diretamente:
    sudo dmesg | grep -i -e IOMMU -e DMAR | grep -i enabled
    ```
    > [!NOTE]
    > O comando `ujust setup-virtualization` → **Setup Simultaneous Graphics** ainda existe para compatibilidade (ex: rebases sobre outras imagens sem os kargs baked). Nesta imagem, ele retornará "already present" e não fará nada.
2.  **Configuração de Disco e Rede:**
    *   Configure o barramento de disco como **VirtIO SCSI** (I/O de alto desempenho).
    *   Configure o modelo da placa de rede como **virtio**.
    *   Monte a ISO de drivers VirtIO na VM e instale o pacote `virtio-win-guest-tools.exe` para carregar todos os drivers.

    > [!CAUTION]
    > **Atenção aos Discos Existentes (Perigo de Corrupção):**
    > Se você deseja reutilizar a instalação do Windows de uma VM antiga (ex: `Niara-windows.25H2.26200.6584`) nesta nova VM (`win11`), **nunca aponte duas definições de VMs ativas para o mesmo arquivo de imagem física `.qcow2`**. Isso causará corrupção de dados catastrófica se ambas forem iniciadas.
    > 
    > Para resolver o erro `Cannot access storage file '/var/lib/libvirt/images/windows-clone.qcow2' (No such file or directory)`, siga uma das estratégias abaixo:
    >
    > *   **Estratégia A: Substituição Completa (Recomendado, sem consumo extra de disco)**
    >     Se você não precisa mais da definição da VM antiga:
    >     1. Mova o disco para o novo caminho esperado pelo template:
    >        ```bash
    >        sudo mv "/var/lib/libvirt/images/Niara-windows.25H2.26200.6584.qcow2" /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >     2. Corrija o proprietário do arquivo para o usuário `qemu` do hypervisor:
    >        ```bash
    >        sudo chown qemu:qemu /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >     3. Delete a definição antiga do libvirt para evitar conflitos (o disco já foi movido e está seguro):
    >        ```bash
    >        virsh -c qemu:///system undefine Niara-windows.25H2.26200.6584
    >        ```
    >
    > *   **Estratégia B: Clone Copy-on-Write (CoW) Instantâneo (Preserva o original como backup)**
    >     Se você deseja manter a VM antiga intocada, mas criar a nova a partir dela de forma imediata:
    >     1. Crie uma imagem de clone fina vinculada à original:
    >        ```bash
    >        sudo qemu-img create -f qcow2 -F qcow2 -b "/var/lib/libvirt/images/Niara-windows.25H2.26200.6584.qcow2" /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >     2. Corrija a propriedade do clone:
    >        ```bash
    >        sudo chown qemu:qemu /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >        *(Importante: A VM original nunca mais deve ser iniciada ou modificada, caso contrário o clone CoW perderá integridade e será corrompido).*
    >
    > *   **Estratégia C: Cópia Completa Independente (Mais segura, consome espaço duplo)**
    >     1. Copie o arquivo de disco fisicamente:
    >        ```bash
    >        sudo cp "/var/lib/libvirt/images/Niara-windows.25H2.26200.6584.qcow2" /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >     2. Corrija a propriedade do clone:
    >        ```bash
    >        sudo chown qemu:qemu /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >
    > *   **Estratégia D: Criar do Zero (Instalação Limpa / Fresh Install)**
    >     Se você prefere criar um disco totalmente limpo do zero e instalar o Windows usando a ISO:
    >     1. Crie um novo arquivo de disco virtual `.qcow2` vazio (ex: de 100 GB):
    >        ```bash
    >        sudo qemu-img create -f qcow2 /var/lib/libvirt/images/windows-clone.qcow2 100G
    >        ```
    >     2. Mude o proprietário para o usuário do hypervisor (`qemu:qemu`):
    >        ```bash
    >        sudo chown qemu:qemu /var/lib/libvirt/images/windows-clone.qcow2
    >        ```
    >     3. Inicie a VM. Ela dará boot pela ISO do instalador do Windows. Quando a instalação pedir pelo disco e não listar nenhum, selecione "Carregar Driver" e aponte para a unidade correspondente do CD-ROM do VirtIO (geralmente sob `vioscsi\w11\amd64`) para carregar o driver `vioscsi` (VirtIO SCSI).
    >     4. **Contornando a tela "Vamos conectar você a uma rede" (OOBE):**
    >        Como o Windows 11 não possui o driver de rede VirtIO (`NetKVM`) nativo e bloqueia o avanço da instalação sem internet, pressione **Shift + F10** (ou **Fn + Shift + F10** em laptops como o Dell G15) na tela de rede para abrir o Prompt de Comando (CMD) e escolha um dos caminhos:
    >        *   **Caminho A: Carregar o Driver de Rede Dinamicamente (Recomendado se deseja usar conta Microsoft)**
    >            Como o Windows pode mapear os volumes de forma diferente, identifique a letra da unidade de CD-ROM do VirtIO executando no Prompt de Comando (CMD):
    >            ```cmd
    >            echo list volume | diskpart
    >            ```
    >            Localize a letra do volume rotulado como `virtio-win` (por exemplo, `E:`). Em seguida, instale o driver de rede apontando diretamente para o arquivo `.inf` específico:
    >            ```cmd
    >            pnputil /add-driver E:\NetKVM\w11\amd64\netkvm.inf /install
    >            ```
    >            *(Substitua `E:` pela letra real identificada pelo diskpart. Caso o comando relate arquivo ausente, execute `dir E:\NetKVM` para confirmar que a unidade de drivers foi acessada corretamente).*
    >        *   **Caminho B: Burlar a exigência de Internet (BypassNRO - Criar conta local)**
    >            No Prompt de Comando, digite o comando abaixo e aperte Enter:
    >            ```cmd
    >            OOBE\BYPASSNRO
    >            ```
    >            A máquina virtual será reiniciada e a tela de rede exibirá um novo botão: **"Eu não tenho internet"** (I don't have internet), permitindo concluir a configuração inicial com uma conta local offline. Depois de entrar na Área de Trabalho, execute o instalador `virtio-win-guest-tools.exe` contido no CD-ROM para instalar todos os drivers restantes.
    >
    > 💡 **Nota de Especialista sobre Btrfs, Performance (No CoW) e TRIM:**
    > Como o Bazzite utiliza o sistema de arquivos **Btrfs** por padrão no `/var`, o diretório de imagens do libvirt (`/var/lib/libvirt/images`) vem pré-configurado de fábrica com o atributo de sistema **`nodatacow`** (No Copy-on-Write, identificado pela flag `C` em comandos `lsattr`).
    > * **Por que isso é crítico?** Arquivos de VM (como `.qcow2`) sofrem gravações aleatórias constantes. O comportamento padrão CoW do Btrfs fragmentaria o arquivo rapidamente, degradando a performance de E/S. O atributo `+C` garante que as gravações ocorram in-place no arquivo existente.
    > * **Como novos arquivos herdam isso?** Novos arquivos criados dentro do diretório `/var/lib/libvirt/images` herdam o atributo `+C` automaticamente na criação, contanto que o diretório pai já o possua.
    > * **Sincronia com o TRIM:** A combinação do atributo `nodatacow` no host com o barramento `virtio-scsi` e a tag `discard="unmap"` no XML permite que o Windows execute comandos de TRIM livremente. Você pode disparar a limpeza de blocos órfãos no Windows via PowerShell com:
    >   ```powershell
    >   Optimize-Volume -DriveLetter C -ReTrim -Verbose
    >   ```
    >   Isso transformará os blocos liberados em "holes" (arquivo esparso) no host, reduzindo o consumo de espaço físico no seu SSD físico imediatamente.
3.  **Ajuste de CPU (XML):**
    Defina o modo de CPU como `<cpu mode='host-passthrough' check='none'/>` e aloque entre 8 a 12 vCPUs. O agendador híbrido do Linux fará a distribuição eficiente de threads entre os P-cores e E-cores do seu i7-12700H.

---

## 🎮 Opção B: GPU Passthrough Exclusivo (Opcional & Avançado)

Neste cenário, a **GPU NVIDIA é desvinculada do host Linux e dedicada 100% à VM Windows**. O desktop do Bazzite passa a rodar na iGPU Intel Iris Xe.

### Para quem é recomendado:
*   Quem precisa rodar aplicativos 3D de alta performance ou jogos que exigem aceleração física direta no Windows Virtualizado.
    > [!CAUTION]
    > **Nota Crítica de Anti-Cheat:**
    > Valorant (Vanguard) e Destiny 2 (BattlEye) não rodam em VMs sob nenhuma circunstância devido ao bloqueio ativo de hypervisors pelo anti-cheat. Tentativas de contornar isso podem acarretar em banimento de conta.

### 🛠️ Passo a Passo de Configuração
1.  **Isolar a GPU no Host:**
    Execute `ujust setup-virtualization` e escolha a opção **Setup Exclusive GPU Passthrough (NVIDIA for VM ONLY)**. Isso adicionará o driver `vfio-pci` às IDs da sua RTX 3060. Reinicie o host.
    > [!WARNING]
    > **A BIOS do seu laptop deve estar configurada no modo Híbrido/Optimus** (onde o vídeo principal roda na iGPU Intel). Se você desativar a iGPU e forçar o modo "Somente GPU Dedicada" (MUX Switch direto) na BIOS do Dell G15 e depois isolar a NVIDIA, o sistema não terá nenhuma GPU ativa no host para carregar a interface gráfica, gerando uma tela preta persistente após o boot.
2.  **Configurar KVMFR (Looking Glass):**
    Execute `ujust setup-virtualization` e selecione **Enable KVMFR / Looking Glass Support**. O script remove as masks de opt-out, adiciona o karg `kvmfr.static_size_mb=128` e carrega o módulo ao vivo (sem reboot necessário na primeira ativação).

    > [!NOTE]
    > **KVMFR é totalmente opt-in e reversível.** Por padrão a imagem não carrega o módulo kvmfr nem cria `/dev/kvmfr0`. `kvmfr-off` restaura o estado desabilitado via masking declarativo de systemd (`/etc/modules-load.d/kvmfr.conf` vazio e `/etc/udev/rules.d/99-kvmfr.rules → /dev/null`) e remove o karg. Persiste através de atualizações da imagem graças ao merge de 3 vias do OSTree.
    >
    > **Nota de migração (upgrade de imagem anterior):** Se você fez rebase de uma versão do silver-goggles onde o kvmfr estava baked por padrão, o OSTree irá adicionar os novos mask files ao seu `/etc/` durante o upgrade, desabilitando o KVMFR. Re-execute `ujust setup-virtualization kvmfr-on` após o primeiro boot da nova imagem.

3.  **Configurar a VM no seu Gerenciador:**
    *   Adicione o hardware PCI correspondente à sua GPU NVIDIA (VGA e Áudio).
    *   Adicione o dispositivo de memória compartilhada KVMFR no XML da VM, logo antes de `</devices>`:
        ```xml
        <shmem name='looking-glass'>
          <model type='ivshmem-plain'/>
          <size unit='M'>128</size>
        </shmem>
        ```
4.  **Instalação dos Softwares (Windows Guest):**
    *   Instale o driver oficial da NVIDIA GeForce e o aplicativo **Looking Glass Host**.
    *   **Monitor Fantasma Virtual:** Instale o `IddSampleDriver` no Windows caso você não possua uma tela física ou dongle HDMI fisicamente conectado às saídas ligadas diretamente à RTX 3060. Isso é vital para forçar a GPU dedicada a instanciar um framebuffer ativo para a cópia do Looking Glass.
5.  **Instalação e Uso do Cliente (Bazzite Host):**
    *   O cliente do Looking Glass já vem **pré-instalado nativamente** na imagem de fábrica `bazzite-dx-silver-goggles`. Não é necessário adicionar repositórios COPR ou empilhar pacotes no host.
    *   Inicie a VM e execute diretamente no terminal do host: `looking-glass-client`. Use a tecla **Scroll Lock** para capturar/liberar o controle de mouse e teclado.

### 📺 Alternativa de Streaming Sem Looking Glass: Sunshine & Moonlight
Se você preferir uma alternativa ao Looking Glass que forneça transmissão de áudio e vídeo de baixíssima latência (com suporte a HDR) de forma simplificada:
1.  **No Windows Guest (VM):**
    *   Instale o **Sunshine** na VM.
    *   Nas configurações do Sunshine, force a captura e codificação de vídeo pela GPU NVIDIA via **NVENC** (o consumo de CPU será nulo porque o encoder é integrado de hardware na RTX 3060).
    *   O **IddSampleDriver** (monitor fantasma) é obrigatório aqui também para forçar a GPU dedicada a instanciar uma tela ativa na qual o Sunshine possa se acoplar.
2.  **No Bazzite Host:**
    *   O Bazzite traz o cliente **Moonlight** pré-instalado na imagem padrão (ou disponível no Flathub).
    *   Abra o Moonlight no host, insira o IP correspondente da VM (`192.168.122.X` ou o IP do Tailscale) e realize o emparelhamento com o Sunshine.
    *   A partir daí, você poderá transmitir a VM inteira em tela cheia a 60/120 FPS de forma fluida sem precisar gerenciar a memória compartilhada (SHM) do Looking Glass.

---

## 🖥️ Clientes de Console e Controle de Tela (Interfaces de DX)

O ecossistema Fedora Silverblue/Bazzite fornece diferentes ferramentas para interagir com a tela e controlar o ciclo de vida das suas VMs. Escolha a que melhor se adapta ao seu fluxo de trabalho:

### 1. Virt-Manager (Desktop Clássico)
*   **Descrição:** Interface tradicional baseada em GTK3 empacotada nativamente na sua imagem `bazzite-dx`.
*   **Melhor Uso:** Configurações iniciais de hardware, gerenciamento de mídias e edição direta de XML.
*   **Limitações Conhecidas:** A interface gráfica não gerencia diretamente backends modernos como o PipeWire (exige XML manual). Se você editar outras propriedades de áudio via GUI do Virt-Manager após fazer modificações no XML, a interface poderá sobrescrever suas tags customizadas com opções padrões do sistema.

### 2. Cockpit-Machines (Console Web Leve)
*   **Descrição:** Gerenciador web integrado nativamente nos serviços da imagem. Fica escutando por padrão em `https://localhost:9090` (acesse com suas credenciais do host Linux).
*   **Benefícios Reais:**
    *   **Consumo de Recursos Zero:** Não necessita manter uma janela de aplicativo de desktop pesada aberta.
    *   **Modularidade Atômica:** Permite ligar, desligar, pausar, gerenciar conexões de rede NAT e monitorar o uso de CPU/RAM da VM direto no navegador.
    *   **Consoles Integrados:** Fornece consoles gráficos VNC e seriais leves direto na aba da web.
        > [!IMPORTANT]
        > **Resolução de "SPICE graphical console that can not be shown here":**
        > O Cockpit-Machines não suporta nativamente a renderização direta do protocolo SPICE no navegador. Para permitir o acesso gráfico no navegador (via Cockpit) e manter o suporte a recursos avançados (clipboard dinâmico, redimensionamento automático) no Virt-Manager (via SPICE), configure **ambos os dispositivos gráficos simultaneamente no XML da VM**:
        > ```xml
        > <graphics type="spice" port="-1" tlsPort="-1" autoport="yes">
        >   <image compression="off"/>
        > </graphics>
        > <graphics type="vnc" port="-1" autoport="yes" listen="127.0.0.1">
        >   <listen type="address" address="127.0.0.1"/>
        > </graphics>
        > ```
        > Ao escutar em `127.0.0.1`, o VNC permanece restrito e seguro contra acessos diretos da rede, mas o Cockpit (que roda no Host) consegue se conectar localmente a ele e renderizar a tela como HTML5/WebSockets remotamente.
*   **Como Garantir que Está Ativo:**
    O `cockpit.socket` já vem habilitado por padrão nesta imagem (declarado em `dx.yml`). Para verificar:
    ```bash
    systemctl is-active cockpit.socket   # deve retornar "active"
    systemctl is-enabled cockpit.socket  # deve retornar "enabled"
    ```
    Se por algum motivo estiver desativado: `sudo systemctl enable --now cockpit.socket`

### 3. Remote-Viewer / Virt-Viewer (Focado em SPICE)
*   **Descrição:** Aplicativo leve voltado exclusivamente para renderizar a janela de vídeo SPICE/VNC da VM, sem as opções pesadas de gerenciamento de disco e rede do Virt-Manager.
*   **Benefícios Reais:**
    *   Ideal para criar atalhos rápidos de terminal ou lançadores no seu menu de aplicativos (ex: `remote-viewer spice://127.0.0.1:5900`).
    *   **O Truque do `--wait`:** Ao rodar `virt-viewer -c qemu:///system --direct --wait "nome-da-vm"`, o visualizador ficará aguardando em segundo plano e abrirá a janela de vídeo automaticamente no milissegundo em que a VM for iniciada (ótimo para parear com scripts de automação de boot).

### 4. RDP (KRDC / Remmina)
*   **Descrição:** Cliente de Área de Trabalho Remota nativo da Microsoft rodando sobre rede virtualizada.
*   **Benefícios Reais:** Excelente redimensionamento dinâmico de áudio e vídeo em conexões NAT comuns.
*   **Limitação Crítica:** **Falha imediatamente** ao ativar VPNs estritas como Netskope na VM Guest, pois o tráfego da LAN TCP/IP local com o Host é bloqueado pelo túnel corporativo. Nesse estado, você deve retornar para o SPICE (Virt-Manager/Remote-Viewer) ou Looking Glass.

### 5. Virsh CLI (A Alternativa Definitiva de Terminal)
*   **Descrição:** Utilitário de linha de comando nativo do libvirt (`virsh`) para gerenciar todo o ciclo de vida do hypervisor.
*   **Benefícios Reais:**
    *   **Controle Total via Teclado:** Excelente para automações locais, SSH sem interface gráfica e diagnóstico.
    *   **Comandos Essenciais de DX:**
        *   *Listar VMs:* `virsh list --all`
        *   *Iniciar VM:* `virsh start <nome-da-vm>`
        *   *Desligar graciosamente:* `virsh shutdown <nome-da-vm>`
        *   *Forçar desligamento (Puxar da tomada):* `virsh destroy <nome-da-vm>`
        *   *Editar XML no editor padrão (Vim/Nano):* `virsh edit <nome-da-vm>`
        *   *Configurar Boot Automático:* `virsh autostart <nome-da-vm>` (ou `--disable` para reverter)
        *   *Definir/Importar VM a partir de XML:* `virsh define <caminho-do-arquivo.xml>`
        *   *Remover definição da VM (deletando NVRAM UEFI de boot):* `virsh undefine <nome-da-vm> --nvram`
            > [!NOTE]
            > O parâmetro `--nvram` é obrigatório para remover VMs UEFI que possuam chaves de Secure Boot e TPM associadas, prevenindo arquivos órfãos em `/var/lib/libvirt/qemu/nvram/` e permitindo que o libvirt gere um novo arquivo de NVRAM limpo quando a VM for redefinida.

---

## 🌐 Acesso Remoto Unificado via Tailscale (Cockpit, QEMU, RDP, SSH)

Para desenvolvedores trabalhando remotamente ou administrando recursos em trânsito, a malha de rede segura do **Tailscale** permite expor e acessar de forma centralizada todas as interfaces gráficas e CLI das suas VMs, contêineres e sistemas de gerenciamento sem abrir portas públicas.

### 1. Cockpit-Machines (Interface Web)
O Cockpit roda como um serviço web local e escuta em todas as interfaces de rede por padrão ao ser ativado:
*   **Acesso Remoto:** Abra o navegador em qualquer máquina na sua Tailnet e acesse `https://<IP-Tailscale-do-Host>:9090`.
*   **DX do Desenvolvedor:**
    *   Faça login usando suas credenciais do usuário local do host (ex: seu usuário local).
    *   Permite ligar, pausar ou desligar VMs graficamente e acessar o terminal serial/VNC emulado das VMs diretamente na aba do navegador, sem requerer clientes de desktop adicionais.

### 2. QEMU/Libvirt GUI Remoto (SPICE/VNC)
Se você precisa da interface de tela nativa da VM, mas não quer configurar serviços de RDP ou Sunshine:
*   **Acesso Remoto:** Abra o terminal no seu laptop remoto conectado à Tailnet e execute:
    ```bash
    virt-viewer -c qemu+ssh://seu-usuario@<IP-Tailscale-do-Host>/system --direct "nome-da-vm"
    ```
*   **DX do Desenvolvedor:** O Libvirt criará um túnel SSH criptografado seguro sobre a rede do Tailscale de forma transparente, roteando os pacotes gráficos SPICE do Host para a janela do seu cliente local com latência mínima.

### 3. Acesso CLI às VMs Guest (SSH ProxyJump & Resolução de Nomes libvirt-nss)
O seu sistema `bazzite-dx-silver-goggles` configura automaticamente no boot a resolução de nomes via **`libvirt-nss`** (através da automação do [bazzite-dx-groups.service](files/system/usr/lib/systemd/system/bazzite-dx-groups.service)). Isso significa que o Host Bazzite consegue resolver o IP de qualquer VM na rede NAT local usando apenas o hostname da VM (ex: `ssh developer@nome-da-vm`).

Para acessar o SSH de qualquer VM remotamente via Tailscale utilizando essa facilidade, sem precisar descobrir o IP interno da VM:

*   **Acesso Direto via ProxyJump:**
    ```bash
    ssh -J seu-usuario@<IP-Tailscale-do-Host> usuario-da-vm@<nome-da-vm>
    ```
    *Exemplo:* `ssh -J <username>@<host-tailnet-ip> developer@windows-vm`
*   **Superpoder de DX: Automatizando no SSH Config do seu Laptop Remoto:**
    Você pode adicionar a seguinte configuração no seu arquivo `~/.ssh/config` local no seu laptop de viagem:
    ```text
    # Proxy para acessar qualquer VM QEMU do Host principal por nome
    Host host-vm-*
      ProxyJump seu-usuario-host@<IP-Tailscale-do-Host>
    
    # Mapeamento da VM do Windows de Desenvolvimento
    Host host-vm-windows
      User developer
      HostName windows-vm  # Nome resolvido pelo nss_libvirt no Host Bazzite
    ```
    Agora, de qualquer lugar do mundo conectado ao Tailscale, basta executar diretamente:
    ```bash
    ssh host-vm-windows
    ```
    O SSH do seu laptop pulará automaticamente para o Host Bazzite, que por sua vez utilizará o `libvirt-nss` para obter o IP dinâmico da VM e abrirá o terminal seguro de forma transparente.

### 4. Área de Trabalho Remota (RDP) para Windows Guest sob VPN
Se o RDP do Windows Guest for bloqueado por conta de políticas de roteamento da VPN interna da VM, você possui duas alternativas de DX:

*   **Opção A: RDP Relay via Firewall no Host (Persistente - Requer Sudo):**
    Configure o firewall do Host Bazzite para repassar conexões da porta `3389` vindas da Tailnet para a interface Host-Only (**NIC 2**, ex: IP da VM `192.168.100.2`), que contorna a VPN:
    ```bash
    sudo firewall-cmd --zone=external --add-forward-port=port=3389:proto=tcp:toport=3389:toaddr=192.168.100.2 --permanent
    sudo firewall-cmd --reload
    ```
    Em seu cliente RDP local no laptop de viagem, conecte-se direto no IP do Host Bazzite da Tailnet: `<IP-Tailscale-do-Host>:3389`.
*   **Opção B: Túnel SSH local (Temporário - Rootless):**
    Se você não quer alterar as regras do firewall do host de forma fixa, pode mapear uma porta local do seu laptop diretamente para a VM através da conexão SSH sobre a Tailscale:
    ```bash
    ssh -L 33890:192.168.100.2:3389 seu-usuario@<IP-Tailscale-do-Host>
    ```
    Agora, basta conectar o seu cliente RDP local em `localhost:33890`. O tráfego RDP será encapsulado de forma criptografada pelo SSH, contornando a VPN da VM. Para desfazer, basta fechar o terminal do SSH.

---

## 🦄 Incus: A Alternativa de DX Moderna (Orquestração sem XML)

Embora o Virt-Manager e o `virsh` (libvirt) sejam os padrões clássicos de virtualização no Linux, eles carregam a complexidade de gerenciar permissões manuais de SELinux, ACLs de soquete e blocos verbosos de XML. 

O seu sistema `bazzite-dx-silver-goggles` traz o **Incus** pré-instalado de fábrica. O Incus é um gerenciador de containers e máquinas virtuais moderno e leve, focado na experiência do desenvolvedor (DX).

### 🚀 Por que o Incus é superior para a DX de desenvolvedores?

1.  **Mapeamento de Usuário Transparente (Sem Conflito de Permissões):**
    *   No Virt-Manager, o compartilhamento de arquivos via Virtio-FS exige alterar permissões do SELinux (`svirt_image_t`) e lidar com propriedade de arquivos no host.
    *   No Incus, o compartilhamento de arquivos via Virtio-FS é feito com **uma única linha de comando**, e o mapeamento de UID/GID do usuário local (`1000`) é realizado automaticamente em background via namespaces do kernel:
        ```bash
        incus config device add <sua-vm> workspace disk source=/var/home/seu-usuario/workspace path=/workspace
        ```
2.  **Configuração de Áudio/Vídeo e Microfone Simplificada:**
    *   Em vez de hackear XMLs complexos para conectar o áudio ao PipeWire do host, o Incus gerencia a ponte de som do hypervisor de forma nativa e segura:
        ```bash
        incus config device add <sua-vm> audio sound
        ```
3.  **Rede e Pontes Automáticas (Sem Conflitos de Firewall):**
    *   O Incus gerencia sua própria ponte de rede virtual de alto desempenho com NAT, DHCP e resolução DNS local automáticos, sem exigir a configuração de helpers externos de rede ou manipulação do `firewalld` no host.
4.  **Imunidade a Sandbox e Flatpak:**
    *   Como o Incus funciona baseado em um daemon REST API local e uma CLI super leve (`incus`), você não sofre com as restrições de sandbox de USB/arquivos que assolam o Flatpak do Virt-Manager.

### 🛠️ Guia Rápido de Uso do Incus para VMs

1.  **Inicializar o serviço do Incus no Host:**
    ```bash
    sudo systemctl enable --now incus.socket incus.service
    # Configure a rede padrão e armazenamento (pressione Enter para aceitar os padrões recomendados)
    sudo incus admin init
    ```
2.  **Adicionar o seu usuário ao grupo do Incus (DX sem sudo):**
    ```bash
    sudo usermod -aG incus-admin $USER
    # Faça logoff e logon para aplicar o grupo
    ```
3.  **Criar e Iniciar uma VM Linux ou Windows:**
    *   *VM Linux (Ubuntu 24.04):*
        ```bash
        incus launch images:ubuntu/24.04 dev-vm --vm
        ```
    *   *Acessar o console de tela da VM:*
        ```bash
        incus console dev-vm --type=vga
        ```
4.  **Mapear pasta do Host na VM (Virtio-FS Automático):**
    ```bash
    incus config device add dev-vm dev-folder disk source=/var/home/seu-usuario/workspace path=/workspace
    ```

### 🔌 Acesso Remoto a VMs Incus via Tailscale (O Superpoder de DX)

O Incus fornece uma API REST nativa que, acoplada à Tailnet, possibilita acessar e orquestrar suas máquinas e contêineres remotamente com extrema elegância e segurança.

#### Método 1: Roteamento de Subrede (Acesso Direto por IP)
O Incus cria uma ponte de rede padrão (ex: `incusbr0` na subrede `10.0.25.0/24`). Você pode expô-la diretamente a todos os dispositivos da sua Tailnet a partir do Host Bazzite:

1.  **No Host Bazzite:**
    Habilite o encaminhamento de rotas do Tailscale para a ponte do Incus:
    ```bash
    tailscale up --advertise-routes=10.0.25.0/24 --accept-routes
    ```
2.  **No Painel de Administração do Tailscale (Web):**
    Localize a sua máquina Host Bazzite nas configurações de máquinas, vá nas opções de rotas e **aprove** a subrede `10.0.25.0/24`.
3.  **DX Resultante:**
    Qualquer outro computador ou tablet na sua Tailnet poderá realizar conexões diretas via IP nas VMs/Containers do Incus:
    *   **Acesso Terminal:** `ssh usuario@10.0.25.15`
    *   **Acesso Gráfico:** Aponte seu cliente RDP/VNC diretamente para `10.0.25.15:3389` (sem necessidade de portas redirecionadas ou proxies no Host).

#### Método 2: Orquestração Remota via API (Sem Portas Abertas ou SSH no Guest)
Se você estiver viajando e quiser gerenciar ou entrar no console das suas VMs do Incus a partir de um laptop secundário:

1.  **No Host Bazzite (Desktop Principal):**
    Configure o Incus para escutar e autenticar conexões seguras na porta `8443` da interface do Tailscale:
    ```bash
    incus config set core.https_address <IP-Tailscale-do-Host>:8443
    ```
    Gere um token de pareamento confiável de uso único:
    ```bash
    incus admin token create laptop-remoto
    ```
2.  **No Laptop Remoto (Cliente):**
    Registre o seu desktop principal como um servidor remoto no CLI local do Incus:
    ```bash
    incus remote add desktop-principal <IP-Tailscale-do-Host>:8443 --token <TOKEN-GERADO>
    ```
3.  **Ações Remotas Prontas (Exemplos executados do seu laptop de viagem):**
    *   **Entrar no Bash de qualquer VM/Container Remoto:**
        ```bash
        incus exec desktop-principal:dev-vm -- bash
        ```
        *(Você ganha acesso root imediato ao terminal da VM remota sem precisar de chaves SSH, servidores SSH ou de portas abertas na VM guest).*
    *   **Abrir o Console Gráfico VGA (SPICE) Remotamente:**
        ```bash
        incus console desktop-principal:dev-vm --type=vga
        ```
        *(O Incus encapsulará o stream gráfico SPICE por TLS da API diretamente para a janela local do seu laptop de viagem).*

---

### ⚡ Alternativas de Motores VMM (kcli & cloud-hypervisor)

Embora o Libvirt/QEMU e o Incus sejam os gerenciadores de virtualização recomendados para o dia a dia, o seu sistema `bazzite-dx-silver-goggles` traz instalados por padrão outros motores alternativos focados em cenários de orquestração ágil (DX) e computação em nuvem leve:


#### 1. kcli (Kvm Client - Orquestração Ágil de VMs)
O **`kcli`** é uma ferramenta CLI em Python pré-instalada que permite provisionar, clonar e destruir VMs usando imagens oficiais de nuvem (cloud-init) com comandos simples de uma única linha, eliminando toda a configuração manual de XMLs.
*   **Como usar (Criar e iniciar uma VM Fedora Cloud em segundos):**
    ```bash
    # Baixar a imagem cloud-init do Fedora
    kcli download image fedora41
    # Criar e iniciar a VM com recursos específicos
    kcli create vm -i fedora41 -c 2 -m 2048 dev-fedora-vm
    # Acessar via SSH imediatamente (o kcli gerencia as chaves SSH locais do host)
    kcli ssh dev-fedora-vm
    ```
*   **Como Reverter (Remover a VM e seus recursos):**
    ```bash
    kcli delete vm dev-fedora-vm -y
    ```

#### 2. cloud-hypervisor (Rust-native VMM para Nuvem com Latência Zero)
O **`cloud-hypervisor`** é um monitor de máquina virtual baseado em Rust projetado especificamente para nuvens híbridas e workloads modernos. Ele remove a emulação de hardware antigo do QEMU (IDE, disquetes, etc.) para inicializar kernels Linux compilados diretamente em milissegundos.
*   **Como usar (Iniciar uma VM leve de terminal):**
    ```bash
    # Inicia a VM a partir de um kernel compilado e disco virtual do host
    cloud-hypervisor \
        --kernel ./hypervisor-vmlinux \
        --disk path=./rootfs.raw \
        --cpus boot=2 \
        --memory size=1024M \
        --net "tap=tap0"
    ```
*   **Como Reverter:** Encerre o processo executando Ctrl+C no terminal da VM ou finalize o PID do processo correspondente.

---

## ⚙️ Ajustes Finos Comuns de VM (Edição de XML)

Selecione a sua VM no Virt-Manager, acesse os detalhes, vá em *Preferences -> General* e marque a opção **Enable XML editing**. Aplique estas otimizações para refinar a experiência do Windows Guest:

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

### 3. CPU Pinning para Arquitetura Híbrida (Intel Core i7-12700H)
O i7-12700H possui 6 P-cores (threads 0-11) e 8 E-cores (threads 12-19). Por padrão, o agendador do Linux não distingue quais threads da VM executam tarefas de alto desempenho daquelas que são auxiliares de I/O, distribuindo-as de forma aleatória. Se um vCPU da VM for agendado em um E-core sob estresse, a performance sofrerá quedas brutcas de desempenho (micro-stuttering).
Para obter desempenho estável, defina a contagem estática de vCPUs e configure o bloco `<cputune>` (inserido logo abaixo de `</vcpu>`) para fixar vCPUs em P-cores e as tarefas do emulador/I/O em E-cores:
```xml
<vcpu placement='static'>8</vcpu>
<cputune>
  <!-- Fixa os vCPUs 0 a 7 nos threads de P-cores (Cores 1 a 4) do host -->
  <vcpupin vcpu='0' cpuset='2-3'/>
  <vcpupin vcpu='1' cpuset='2-3'/>
  <vcpupin vcpu='2' cpuset='4-5'/>
  <vcpupin vcpu='3' cpuset='4-5'/>
  <vcpupin vcpu='4' cpuset='6-7'/>
  <vcpupin vcpu='5' cpuset='6-7'/>
  <vcpupin vcpu='6' cpuset='8-9'/>
  <vcpupin vcpu='7' cpuset='8-9'/>
  <!-- Isola as tarefas de emulação e I/O do QEMU nos E-cores do host -->
  <emulatorpin cpuset='12-15'/>
</cputune>
```

### 4. Features Block para Windows (Hyper-V Enlightenments + Ocultação de Hypervisor)

Este bloco cobre dois objetivos: (a) ativar enlightenments do Hyper-V para melhor performance e menor uso de CPU no Windows; (b) ocultar a assinatura do KVM/QEMU para aplicativos que bloqueiam VMs detectadas.

> [!IMPORTANT]
> **`<smm state='on'/>` é obrigatório para Windows 11.** Sem SMM habilitado, o Secure Boot não funciona mesmo que o firmware `<feature enabled="yes" name="secure-boot"/>` esteja declarado no bloco `<os>`. O Windows 11 requer Secure Boot para instalar — omitir SMM quebra a instalação silenciosamente.

```xml
<features>
  <acpi/>
  <apic/>
  <hyperv mode='custom'>
    <relaxed state='on'/>
    <vapic state='on'/>
    <spinlocks state='on' retries='8191'/>
    <vpindex state='on'/>
    <runtime state='on'/>
    <synic state='on'/>
    <stimer state='on'/>
    <!-- Mascara a ID do Hyper-V para uma assinatura genérica de desktop -->
    <vendor_id state='on' value='1234567890ab'/>
    <frequencies state='on'/>
    <tlbflush state='on'/>
    <ipi state='on'/>
    <!-- evmcs: Intel-only (Enlightened VMX Entry/Exit para nested Hyper-V) -->
    <evmcs state='on'/>
  </hyperv>
  <kvm>
    <!-- Oculta a assinatura do KVM para o Windows Guest -->
    <hidden state='on'/>
  </kvm>
  <!-- SMM obrigatório para Secure Boot + TPM 2.0 no Windows 11 -->
  <smm state='on'/>
  <!-- Desativa a porta de console do VMPort para impedir detecção por software -->
  <vmport state='off'/>
</features>
```

**Clock otimizado para Windows (reduz micro-stutter em jogos):**
```xml
<clock offset='localtime'>
  <timer name='rtc' tickpolicy='catchup'/>
  <timer name='pit' tickpolicy='delay'/>
  <timer name='hpet' present='no'/>
  <timer name='hypervclock' present='yes'/>
  <timer name='tsc' present='yes' mode='native'/>
</clock>
```

---

## 🔌 Recursos Avançados e Integrações de Produtividade (DX)

Para tornar o seu fluxo de desenvolvimento o mais completo e flexível possível, incorpore estes recursos de integração avançados entre o Bazzite Host e a sua VM Guest:

### A. Compartilhamento de Pastas Host-Guest (Virtio-FS)

Em vez de configurar servidores Samba/LAN lentos para expor o código-fonte do seu projeto à VM Windows, utilize o **Virtio-FS** para mapear pastas do host Bazzite a taxas de transferência quase nativas (memória mapeada direta, ultrapassando 3 GB/s de E/S de disco):

#### 🛠️ Guia de Implementação Passo a Passo

##### Passo 1: Preparar o diretório no Host (Bazzite)
1. Crie o diretório do seu workspace no Host (ex: `mkdir -p ~/workspace`).
2. Aplique a permissão do SELinux usando a nossa ferramenta rápida:
   ```bash
   ujust setup-virtualization vfs-workspace-on
   ```
   *(Ou digite o caminho `/var/home/seu-usuario/workspace` quando solicitado).*
   
   > [!NOTE]
   > **Como isso funciona no SELinux?**
   > O script atribui a política de segurança `svirt_image_t` para o diretório. Caso queira reverter manualmente ou limpar o contexto do SELinux no diretório futuramente, basta rodar o atalho `ujust setup-virtualization vfs-workspace-off`.

##### Passo 2: Habilitar Memória Compartilhada e Adicionar o Filesystem
1. Com a VM Windows desligada, acesse as propriedades de hardware dela no Virt-Manager.
2. **Habilitar Memória Compartilhada (Obrigatório para o Virtio-FS funcionar):**
   *   Vá em **Memory** nos detalhes de hardware da VM.
   *   Marque a caixa **"Enable shared memory"** (ou "Habilitar memória compartilhada").
   *   *Alternativa via XML:* Caso prefira editar o XML diretamente, ative a edição de XML nas preferências do Virt-Manager, acesse a aba **XML**, e adicione o bloco abaixo logo no início (como filho direto da tag `<domain>`):
       ```xml
       <memoryBacking>
         <source type='memfd'/>
         <access mode='shared'/>
       </memoryBacking>
       ```
3. Clique em **Add Hardware** -> **Filesystem**.
4. Configure os campos:
   *   **Type:** `mount`
   *   **Driver:** `virtiofs`
   *   **Source Path:** `/var/home/seu-usuario/workspace`
   *   **Target Path:** `dev-workspace` (esta é a tag de identificação que o Windows lerá)
5. Clique em Apply e ligue a VM. *(Se você esquecer de ativar a memória compartilhada no passo 2, a VM falhará ao iniciar).*

##### Passo 3: Configurar os Drivers no Windows Guest
O Windows precisa do proxy de sistemas de arquivos em espaço de usuário (WinFsp) e do driver do VirtIO-FS para ler o dispositivo PCI.
1.  **Instalar o WinFsp:**
    *   No Windows Guest, baixe e instale a versão estável mais recente do **WinFsp** (Windows File System Proxy): [github.com/winfsp/winfsp](https://github.com/winfsp/winfsp).
2.  **Instalar o Driver do VirtIO-FS:**
    *   Abra o **Gerenciador de Dispositivos** (`devmgmt.msc`).
    *   Em "Outros Dispositivos", você verá um dispositivo com aviso (ex: "Mass Storage Controller" ou similar, correspondente ao barramento do Virtio-FS).
    *   Clique com o botão direito -> **Atualizar Driver** -> **Procurar drivers no meu computador** e aponte para a unidade de CD/DVD onde está montada a ISO `virtio-win` (geralmente sob a pasta `viofs\w11\amd64` ou similar).
3.  **Habilitar o Serviço do VirtIO-FS:**
    *   Se você utilizou o instalador `virtio-win-guest-tools.exe` da ISO, o serviço `VirtioFsSvc` já estará registrado.
    *   Se precisar registrar manualmente, abra o Prompt de Comando (CMD) como **Administrador** e execute:
        ```cmd
        sc.exe create VirtioFsSvc binpath= "C:\Program Files\Virtio-Win\VioFS\virtiofs.exe" start= auto depend= "WinFsp.Launcher/VirtioFsDrv" DisplayName= "Virtio FS Service"
        ```
    *   Abra o gerenciador de serviços (`services.msc`), localize **VirtIO-FS Service**, mude a inicialização para **Automático** e clique em **Iniciar (Start)**.
    *   *Dica de Escrita:* Se o disco relatar erro de escrita ("Write Protection" ou "Permission Denied") sob usuários comuns do Windows, abra o `services.msc`, acesse as **Propriedades** do **VirtIO-FS Service** -> aba **Log On** (Logon) -> selecione **This account** (Esta conta) e insira as credenciais do seu usuário do Windows local em vez de rodar como `LocalSystem`. Reinicie o serviço.
4.  O diretório compartilhado aparecerá no seu Windows Explorer como uma unidade de disco mapeada (geralmente sob a letra **`Z:`** correspondente à tag `dev-workspace`).

---

#### 💡 Cenário Avançado: Desenvolvimento Híbrido com Código e VPN Isolados no Guest (ex: Netskope) e IDE/Docker no Host

Muitos ambientes corporativos exigem o uso de VPNs estritas (como o **Netskope**) rodando diretamente em um ambiente Windows (Guest) para compliance e acesso a repositórios Git internos e redes privadas. Essas VPNs costumam forçar políticas que **bloqueiam qualquer tráfego de rede local (LAN/Subnet local)**, impedindo o uso de compartilhamentos de rede baseados em TCP/IP (como Samba/SMB, SSHFS, RDP local).

##### A Solução Arquitetural: Virtio-FS
Como o **Virtio-FS funciona via canal de hardware virtual direto (barramento PCI e filas de memória compartilhada do QEMU)**, ele ignora completamente a pilha de rede TCP/IP do Windows Guest. Portanto, **mesmo com o Netskope VPN ativo e bloqueando toda a LAN, o compartilhamento de arquivos via Virtio-FS continua funcionando com 100% de performance e estabilidade!**

Isso viabiliza o melhor dos dois mundos:
1.  **Host Linux (Bazzite):** Onde reside o código fisicamente (ex: `/var/home/seu-usuario/workspace/seu-projeto`). Você roda suas IDEs (VS Code, JetBrains), containers Docker e ferramentas de compilação locais diretamente no Linux Host com **desempenho de E/S nativo de 100%** (zero overhead de virtualização para desenvolvimento ativo).
2.  **Guest Windows (VM):** Onde roda o cliente **Netskope VPN** conectado à rede corporativa. Você usa o Windows Guest apenas para executar os comandos do **Git** (pull, push, clone), que acessam os servidores de código corporativos através do túnel da VPN e gravam as alterações diretamente no disco compartilhado `Z:\` (mapeado ao seu diretório local do Host).

##### Configurar o Git no Windows Guest (Resolução de "Dubious Ownership")
Como os arquivos pertencem fisicamente ao seu usuário do Linux (UID `1000`) e estão sendo acessados pelo Git rodando no Windows Guest, o Git do Windows disparará um bloqueio de segurança contra "propriedade duvidosa" (`fatal: detected dubious ownership in repository`).
Para resolver isso de forma simples e segura:
1.  Abra o Git Bash (ou terminal de sua preferência) no Windows Guest.
2.  Desative a verificação de propriedade para a unidade compartilhada (ou globalmente na VM, já que esta VM é isolada e dedicada apenas ao seu trabalho):
    ```bash
    git config --global --add safe.directory '*'
    ```
3.  Agora, no terminal do Windows, navegue até `Z:\` (sua pasta compartilhada) e clone o repositório através do Netskope VPN:
    ```cmd
    cd /z
    git clone git@github.com:seu-org/seu-projeto.git
    ```
4.  Pronto! Os arquivos serão clonados na rede do trabalho usando o Git no Windows Guest, mas serão salvos fisicamente na sua pasta local do Host Linux.

##### Fluxo de Trabalho Diário & Desenvolvimento Remoto via Tailscale

Este setup viabiliza um fluxo de desenvolvimento em trânsito excepcional (ex: trabalhando de um laptop leve ou tablet fora de casa) utilizando a malha de rede segura do **Tailscale**:

1.  **Conexão SSH via Tailscale (Laptop -> Host Bazzite):**
    *   No seu laptop remoto na Tailnet, abra o VS Code e conecte-se via extensão **Remote - SSH** ao IP da Tailscale do seu Host Bazzite (`100.x.y.z`).
    *   Toda a computação pesada, o VS Code Server, os containers do Docker locais e compiladores rodam diretamente no hardware potente do host Bazzite no seu escritório, com latência de escrita imperceptível.
2.  **Edição Híbrida de Código (Host -> Guest):**
    *   Você edita seus arquivos diretamente no diretório do host (`~/workspace/seu-projeto`).
    *   Como a VM Windows (Guest) mapeia esse mesmo diretório via **Virtio-FS** no drive `Z:\`, a VM enxerga todas as modificações instantaneamente, permitindo compilações e testes locais imediatos no Windows.
3.  **Bypass de VPN com RDP Relay no Host (Laptop -> Host -> Guest):**
    *   Para interagir com o Git corporativo ou ferramentas de compliance, você precisará da interface gráfica da VM Windows (Guest) rodando sob a VPN Netskope.
    *   Como a VPN corporativa bloqueia conexões locais de rede normais, você utiliza a placa Host-Only isolada (**NIC 2**, ex: IP da VM `192.168.100.2`), que por não ter um gateway padrão, é ignorada pela VPN Netskope.
    *   No Host Bazzite, crie uma regra de encaminhamento de porta RDP vinculando sua interface da Tailscale ao IP da NIC 2 da VM:
        ```bash
        sudo firewall-cmd --zone=external --add-forward-port=port=3389:proto=tcp:toport=3389:toaddr=192.168.100.2 --permanent
        sudo firewall-cmd --reload
        ```
    *   Agora, no seu laptop remoto, basta abrir o cliente RDP e conectar-se no IP do Host Bazzite da Tailnet (`100.x.y.z:3389`). A conexão contorna a VPN perfeitamente, dando-lhe acesso gráfico total à VM do Windows de qualquer lugar.
4.  **Operações de Versionamento (Guest):**
    *   Dentro da VM Windows (Guest) conectada à VPN corporativa, execute seus comandos do **Git** (pull, push, clone) apontando para a unidade `Z:\`. Os commits chegam de forma segura aos servidores internos da empresa através do túnel da VPN, mantendo a conformidade, enquanto o código físico permanece salvo em segurança no seu host Linux.

---

### B. Gerenciamento de Roteamento de Áudio e Microfone (PipeWire Nativo)

Para usar o microfone no Linux (Host) e no Windows (Guest) ao mesmo tempo, **não utilize o passthrough físico de USB** (pois ele remove o dispositivo do host). Em vez disso, utilize o backend nativo do PipeWire integrado no QEMU/libvirt. Isso permite que a VM atue como um cliente de áudio comum no grafo do PipeWire.

#### 1. Configurando o XML da VM
Edite o XML da VM (habilite a edição de XML nas preferências do Virt-Manager) e substitua ou adicione os elementos abaixo dentro da tag `<devices>`:
```xml
<sound model='ich9'>
  <audio id='1'/>
</sound>
<audio id='1' type='pipewire' runtimeDir='/run/user/1000'>
  <input name='guest-in' streamName='Guest Mic' latency='15000'/>
  <output name='guest-out' streamName='Guest Output' latency='15000'/>
</audio>
```
> [!NOTE]
> *   **`runtimeDir`**: Ajuste o `1000` se o UID do seu usuário no host for diferente (verifique executando `id -u` no terminal do host).
> *   **`latency`**: O valor de `15000` microsegundos (15ms) previne estalos no áudio. Se houver desync ou engasgos, aumente levemente para `20000` ou `30000`.

#### 2. Automação de Permissões e Segurança (DX Integrado no Silver-Goggles)
Por padrão, o QEMU executa sob o usuário do sistema `qemu`, e o SELinux bloqueia o acesso à pasta temporária do seu usuário local (`/run/user/1000/pipewire-0`). 

A boa notícia é que **você não precisa fazer nenhuma configuração de ganchos ou compilação manual de SELinux**. O seu sistema `bazzite-dx-silver-goggles` traz essa automação como um recurso **opcional e totalmente reversível**:
*   **Ativação Simplificada (ujust):** Para ativar o recurso, execute `ujust setup-virtualization` no terminal do host e escolha **`Enable PipeWire VM Audio Support (Microphone)`** (ou use o atalho rápido `ujust setup-virtualization pwaudio-on`).
*   **Reversão Completa:** Se desejar desativar e reverter todas as alterações de segurança e ganchos, execute `ujust setup-virtualization` e escolha **`Disable PipeWire VM Audio Support (Microphone)`** (ou use o atalho rápido `ujust setup-virtualization pwaudio-off`). Isso limpará o arquivo de controle e descarregará a política do SELinux imediatamente.
*   **Como Funciona por Baixo dos Panos:**
    *   **Gancho Automático (Libvirt Hook):** Se ativado, o script de gancho global da imagem `/etc/libvirt/hooks/qemu` analisa o XML de qualquer VM que você iniciar. Se ele detectar a tag `<audio type='pipewire'>`, ele automaticamente concede permissão temporária de leitura/escrita (`setfacl`) no socket do PipeWire do usuário ativo ao iniciar a VM, e remove a permissão quando ela é desligada.
    *   **Política SELinux Declarativa:** O atalho instala/ativa a política de segurança `/usr/share/selinux/packages/pipewire.cil` (que é mantida no boot pelo serviço `bazzite-dx-groups.service` se ativada) autorizando o domínio da VM (`svirt_t`) a se comunicar com o socket de tempo de execução temporário do usuário host (`user_tmp_t`) e o daemon do PipeWire.

> [!TIP]
> Se você preferir rodar a VM de forma totalmente isolada sob o contexto do seu próprio usuário local (eliminando barreiras de permissão a nível de arquitetura de sistema), você pode optar por se conectar a `qemu:///session` (Sessão do Usuário) em vez de `qemu:///system` no Virt-Manager, embora isso mude a forma de gerenciar redes de ponte (bridges) e propriedade de discos virtuais.

#### 3. Gerenciamento de Roteamento de Áudio
Instale o **qpwgraph** ou **Helvum** (via Flatpak/Software Center no Bazzite). Quando a VM estiver ligada, você verá as portas de áudio virtuais `Guest Mic` (entrada) e `Guest Output` (saída) da sua VM. Você pode arrastar conexões visuais para ligar o microfone físico à entrada da VM, mantendo-o conectado em paralelo com seus aplicativos do host (Discord, OBS, etc.).

---

### C. Compartilhamento de Câmera/Webcam Simultâneo e Contorno de VPN

Passar a webcam por USB físico desvincula o hardware do Linux. Para usar a mesma webcam simultaneamente no Bazzite e no Windows Guest, você deve manter o dispositivo no Host e transmitir a captura de imagem por rede virtual de baixa latência para a VM.

#### 💡 O Pulo do Gato: Contornando o Bloqueio do Netskope com Duas Placas de Rede (NICs)
VPNs corporativas estritas normalmente sequestram o gateway de rede padrão e bloqueiam tráfego local da sub-rede para evitar exfiltração de dados, o que impossibilita a transmissão de rede de vídeo (NDI/RTSP) ou conexões locais.
Para contornar isso no Virt-Manager:
1.  Com a VM desligada, adicione duas interfaces de rede:
    *   **NIC 1 (NAT - padrão `virbr0`):** Usada para tráfego corporativo e internet geral da VM. É nela que a VPN Netskope atuará.
    *   **NIC 2 (Host-Only / Rede Local Isolada):** Crie uma rede privada virtual estática apenas entre Host (ex: `192.168.100.1`) e Guest (ex: `192.168.100.2`), sem definir um gateway padrão para esta interface no Windows.
2.  Direcione o tráfego do RDP e da webcam virtualizada (NDI/RTSP) exclusivamente pela **NIC 2**. A VPN Netskope ignorará essa placa por ela ser de escopo puramente local e não possuir rota de saída de internet, mantendo a transmissão ativa!

---

#### Método 1: NDI (Interface de Vídeo Profissional e Baixa Latência)
Este é o método mais recomendado, pois o Windows reconhece o fluxo de rede diretamente como uma webcam real sem requerer softwares adicionais complexos na VM.
1.  **No Bazzite (Host):**
    *   Abra o **OBS Studio** (pré-instalado ou instale via Flatpak).
    *   Instale o plugin DistroAV (antigo obs-ndi) do OBS para Flatpak:
        ```bash
        flatpak install flathub com.obsproject.Studio.Plugin.DistroAV
        ```
    *   No OBS, adicione sua webcam física como uma fonte na cena (**Dispositivo de captura de vídeo (V4L2)**).
    *   Acesse **Ferramentas > DistroAV Output Settings** (ou NDI Output Settings) no OBS, ative o **Main Output** e dê o nome de `Host-Webcam`.
    *   *Nota:* Com isso, você pode capturar a imagem no OBS do host, usar o OBS Virtual Camera para aplicativos do host Linux, e transmitir a webcam via rede simultaneamente.
2.  **No Windows (Guest):**
    *   Baixe e instale a suíte gratuita **NDI Tools** no Windows.
    *   Abra o utilitário **NDI Webcam Input** (ele iniciará minimizado na bandeja do sistema).
    *   Clique com o botão direito no ícone do NDI Webcam na bandeja, localize o seu host Linux na lista (direcionado pelo IP da NIC 2, se sob VPN) e selecione a fonte `Host-Webcam`.
    *   Em qualquer aplicativo da VM (Zoom, Teams, Discord), selecione **NDI Webcam** como dispositivo de vídeo.

#### Método 2: FFmpeg + MediaMTX + RTSP (Leve via Terminal/CLI)
Se você não quer ter a interface gráfica do OBS aberta no host o tempo todo:
1.  **No Bazzite (Host):**
    *   Inicie o servidor de vídeo MediaMTX usando Podman:
        ```bash
        podman run --name mediamtx --rm -d --network=host aler9/rtsp-simple-server
        ```
    *   Inicie a transmissão da sua webcam `/dev/video0` para o servidor local sem fazer re-encode de vídeo (consumo nulo de CPU):
        ```bash
        ffmpeg -f v4l2 -input_format mjpeg -video_size 1280x720 -framerate 30 -i /dev/video0 -c:v copy -f rtsp rtsp://127.0.0.1:8554/webcam
        ```
2.  **No Windows (Guest):**
    *   Instale o **OBS Studio** na VM Windows.
    *   Adicione uma **Fonte de Mídia (Media Source)**, desmarque "Arquivo Local" e coloque a URL de entrada (apontando para a NIC 2 do Host): `rtsp://192.168.100.1:8554/webcam`.
    *   Clique em **Iniciar Câmera Virtual** (Start Virtual Camera) no painel do OBS do Windows.
    *   Selecione a **OBS Virtual Camera** nos seus programas do Windows.

---

### D. Redirecionamento de Dispositivos USB (Spice USB Passthrough)
Caso necessite expor pen-drives, dongles de autenticação USB ou controladores de hardware de forma dinâmica à VM:
1. No console do Virt-Manager da VM ativa, acesse a barra de menu superior: **Virtual Machine -> Redirect USB Device**.
2. Uma lista de dispositivos físicos USB conectados ao seu Dell G15 será exibida.
3. Marque o dispositivo desejado. Ele será desvinculado do host Bazzite e plugado de forma lógica na VM do Windows instantaneamente. Desmarque para retornar ao Linux.
   > [!WARNING]
   > **Limitação no Flatpak:**
   > Se o seu Virt-Manager for executado em container isolado Flatpak, o redirecionamento dinâmico por SPICE falhará por bloqueio do sandbox sobre os daemons PolicyKit/udev do host. Nesse caso, realize o **Static USB Passthrough** clicando em *Add Hardware -> USB Host Device* no Virt-Manager com a VM desligada, vinculando a porta física do notebook diretamente à VM.

---

### E. Aceleração 3D Virtualizada para VMs Linux (VirGL / Venus)
Se você precisar iniciar uma VM de testes Linux (como uma distribuição Ubuntu ou Fedora de desenvolvimento) no Virt-Manager:
*   Você **não** precisa de Passthrough de GPU física para obter aceleração gráfica de janelas e renderização 3D.
*   Nas propriedades de tela da VM Linux no Virt-Manager, acesse a placa gráfica (**Video**), defina o modelo como `virtio` e marque a opção **3D Acceleration**.
*   Nas configurações de **Display Spice**, marque a caixa **OpenGL** e selecione o adaptador gráfico da sua iGPU/dGPU. A VM rodará de forma extremamente rápida, renderizando as janelas diretamente na GPU física do host Linux em paralelo com o seu desktop principal.

---

## ⚙️ Tabela de Recursos Opcionais (Ativação & Reversão de DX)

O seu sistema operacional `bazzite-dx-silver-goggles` foi projetado sob o princípio da **reversibilidade**. Toda e qualquer alteração realizada no sistema para fins de virtualização pode ser ativada e desativada através de comandos rápidos e sem risco de corrupção do host.

Abaixo, veja a tabela de referência rápida de atalhos e comandos para ligar e desligar cada recurso opcional:

| Recurso Opcional | Comando de Ativação / Instalação | Comando de Reversão / Desinstalação |
| **Virtualização Core (IOMMU)** | `ujust setup-virtualization virt-on` | `ujust setup-virtualization virt-off` |
| **Áudio PipeWire (Microfone)** | `ujust setup-virtualization pwaudio-on` | `ujust setup-virtualization pwaudio-off` |
| **Pasta Virtio-FS (SELinux)** | `ujust setup-virtualization vfs-workspace-on` | `ujust setup-virtualization vfs-workspace-off` |
| **Isolar GPU NVIDIA (VFIO)** | `ujust setup-virtualization vfio-on` | `ujust setup-virtualization vfio-off` |
| **KVMFR / Looking Glass** | `ujust setup-virtualization kvmfr-on` | `ujust setup-virtualization kvmfr-off` — totalmente reversível via masking |
| **Console Web Cockpit** | Já habilitado por padrão (`cockpit.socket` em `dx.yml`) — verificar: `systemctl is-active cockpit.socket` | `sudo systemctl disable --now cockpit.socket` |
| **Grupo de Usuário Libvirt** | `ujust setup-virtualization group` | `sudo gpasswd -d $USER libvirt` |
| **RDP Relay no Host (VPN Bypass)** | `sudo firewall-cmd --zone=external --add-forward-port=port=3389:proto=tcp:toport=3389:toaddr=192.168.100.2 --permanent && sudo firewall-cmd --reload` | `sudo firewall-cmd --zone=external --remove-forward-port=port=3389:proto=tcp:toport=3389:toaddr=192.168.100.2 --permanent && sudo firewall-cmd --reload` |
| **Túnel SSH para RDP (Rootless)** | `ssh -L 33890:192.168.100.2:3389 seu-usuario@<IP-Tailscale-do-Host>` | Encerrar a sessão SSH no terminal do cliente local |
| **Incus Subnet Routing (Tailscale)** | `tailscale up --advertise-routes=10.0.25.0/24 --accept-routes` *(Aprovar no admin web)* | `tailscale up --advertise-routes="" --accept-routes` |
| **Incus API REST (Acesso Remoto)** | `incus config set core.https_address <IP-Tailscale-do-Host>:8443` | `incus config unset core.https_address` |
| **VM via kcli (Orquestração)** | `kcli create vm -i fedora41 -c 2 -m 2048 dev-fedora-vm` | `kcli delete vm dev-fedora-vm -y` |
| **VM via cloud-hypervisor** | `cloud-hypervisor --kernel ./vmlinux --disk path=./rootfs.raw ...` | Encerrar o processo (Ctrl+C ou `killall cloud-hypervisor`) |
| **Desativar Todos os Kargs** | — | `ujust setup-virtualization virt-off` |

---

## 🔄 Mecanismos de Reversão (Como desfazer as alterações)

> [!WARNING]
> Guarde estes comandos caso ocorra algum travamento, tela preta ou instabilidade ao tentar isolar a GPU.

### A. Desativar VFIO e Voltar para a Opção A (Padrão Geral)
Se o sistema apresentar tela preta após ativar a Opção B, selecione a implantação anterior do OSTree no menu do Grub durante o boot (ou abra o terminal do host Bazzite) e execute:
```bash
ujust setup-virtualization
```
Escolha a opção **Disable All Virtualization Kargs** (caso queira desativar toda a infraestrutura de IOMMU) ou gerencie o VFIO para desvincular a GPU.

*Para liberar a GPU e retornar à Opção A manualmente via terminal (preservando IOMMU e virtualização):*
1. Descubra o argumento de ID exato atualmente configurado:
```bash
rpm-ostree kargs | grep -o 'vfio_pci.ids=[^ ]*'
```
2. Remova o argumento retornado (ex: `vfio_pci.ids=10de:2504,10de:2204`):
```bash
rpm-ostree kargs --delete-if-present="vfio_pci.ids=SUAS_IDS_AQUI"
```
E reinicie o host. A GPU voltará a pertencer ao Bazzite (Opção A).

### B. Limpar Configurações Locais e udev do KVMFR
Para remover sobreposições locais do Looking Glass:
```bash
sudo rm -f /etc/udev/rules.d/99-kvmfr.rules
sudo rm -f /etc/modprobe.d/kvmfr.conf
# Remova a política customizada do SELinux
sudo semodule -r kvmfr 2>/dev/null || true
```

> [!NOTE]
> O procedimento preferido é `ujust setup-virtualization kvmfr-off`, que faz tudo automaticamente: restaura os masks de opt-out (`/etc/modules-load.d/kvmfr.conf` e `/etc/udev/rules.d/99-kvmfr.rules → /dev/null`), remove o karg, descarrega o módulo ao vivo e remove a política SELinux. Os comandos manuais acima são úteis apenas para diagnóstico ou recovery.

> [!WARNING]
> **Evite deletar todo o arquivo /etc/libvirt/qemu.conf!**
> Em vez de apagar o arquivo completamente (o que excluiria todas as opções padrão e outras customizações importantes), edite `/etc/libvirt/qemu.conf` e remova a entrada `"/dev/kvmfr0"` da lista `cgroup_device_acl`. Delete o arquivo com `sudo rm` apenas se tiver certeza de que ele foi criado do zero pelo script e não contém nenhuma outra configuração.

### C. Desinstalar o Looking Glass Client do Host
Como o `looking-glass-client` já vem pré-instalado como um pacote base embutido na imagem `bazzite-dx-silver-goggles` (declarado em [recipes/silver-goggles.yml](recipes/silver-goggles.yml#L29)), você não pode desinstalá-lo no host via `rpm-ostree uninstall`.

Para removê-lo de forma declarativa e definitiva da imagem:
1. Remova a linha `- looking-glass-client` sob a seção de pacotes em [recipes/silver-goggles.yml](recipes/silver-goggles.yml#L29).
2. Recompile a imagem localmente e aplique no seu host:
   ```bash
   just build
   just rebase-local
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

---

## 🍏 macOS Virtualization: OSX-KVM & OpenCore no Dell G15 5520

Esta seção documenta a arquitetura, provisionamento e otimização de máquinas virtuais **macOS (Ventura 13, Sonoma 14 e Sequoia 15)** executadas sobre o KVM no Bazzite-DX Silver-Goggles.

```mermaid
graph TD
    A[Bazzite Host - Dell G15 5520] -->|KVM + OVMF UEFI 4M| B[OpenCore Bootloader]
    B -->|Haswell/Penryn AVX2+AES| C[Kernel Darwin / XNU]
    C -->|Apple Online Recovery / Offline ISO| D[macOS Guest]
    A -->|Pool Único 100GB NVMe + TRIM| D
    D -->|ICH9 EHCI + UHCI Companion| E[Teclado & Mouse USB Virtuais]
    A -->|Cockpit Web Console :61390| F[Interface Remota Celular / Web]
```

### 🏛️ Arquitetura & Diretrizes de Projeto

1. **Storage: RAW Image via I/O Nativo (Estabilidade Btrfs)**
   * Para evitar corrupção severa de metadados devido à interação do APFS TRIM com o Copy-on-Write (CoW) do Btrfs, abandonamos o uso de `.qcow2`.
   * O formato oficial agora é **RAW** alocado em `/var/lib/libvirt/images/macos/macos-disk.img`.
   * A tag `<driver name='qemu' type='raw' cache='none' io='native' discard='unmap'/>` maximiza a estabilidade combinada com o TRIM nativo.

2. **Topologia de CPU e Modelo Golden para Intel 12ª Geração (Alder Lake):**
   * O Dell G15 5520 possui arquitetura híbrida (P-Cores e E-Cores).
   * **Por que `host-passthrough` e `Penryn` falham:**
     * `host-passthrough` expõe a assimetria dos P/E-cores e topologia variável de cache L2/L3, provocando *kernel panics* no `securityd_service` e *double faults* no `launchd` do macOS Ventura/Sonoma.
     * `Penryn` é obsoleto e não possui suporte a SSE4.2, AVX2 e BMI2 exigidos pelo sistema de Cryptex e compilador dyld moderno do macOS 13+.
   * **Modelo Golden Oficial:** Utilize **`Cascadelake-Server-noTSX`** (definido em [templates/macos.xml](virtualization/templates/macos.xml)) com conjunto simétrico de instruções:
     ```xml
     <cpu mode='custom' match='exact' check='none'>
       <model fallback='forbid'>Cascadelake-Server-noTSX</model>
       <vendor>GenuineIntel</vendor>
       <topology sockets='1' dies='1' clusters='1' cores='4' threads='2'/>
       <feature policy='require' name='vme'/>
       <feature policy='require' name='vmx'/>
       <feature policy='require' name='fma'/>
       <feature policy='require' name='avx'/>
       <feature policy='require' name='avx2'/>
       <feature policy='require' name='aes'/>
       <feature policy='require' name='xsave'/>
       <feature policy='require' name='xsaveopt'/>
       <feature policy='require' name='bmi1'/>
       <feature policy='require' name='bmi2'/>
       <feature policy='require' name='invtsc'/>
       <feature policy='require' name='ssse3'/>
       <feature policy='require' name='sse4.1'/>
       <feature policy='require' name='sse4.2'/>
       <feature policy='require' name='popcnt'/>
     </cpu>
     ```
   * O isolamento de CPU é garantido fixando os 8 vCPUs nos P-Cores (`cpuset 2-9`) e o emulador nos E-Cores (`cpuset 12-15`):
     ```xml
     <cputune>
       <vcpupin vcpu='0' cpuset='2-3'/>
       <vcpupin vcpu='1' cpuset='2-3'/>
       <vcpupin vcpu='2' cpuset='4-5'/>
       <vcpupin vcpu='3' cpuset='4-5'/>
       <vcpupin vcpu='4' cpuset='6-7'/>
       <vcpupin vcpu='5' cpuset='6-7'/>
       <vcpupin vcpu='6' cpuset='8-9'/>
       <vcpupin vcpu='7' cpuset='8-9'/>
       <emulatorpin cpuset='12-15'/>
     </cputune>
     ```

3. **Correções Críticas no OpenCore EFI (`config.plist`):**
   * **`Cpuid1Mask` (16 bytes obrigatórios):** O valor Base64 deve ter exatamente 16 bytes: `/////wAAAAAAAAAAAAAAAA==`. Valores de 15 bytes com padding incorreto (como `/////wAAAAAAAAAAAAAAAAA=`) quebram o parser do OpenCore e desativam o spoofing de CPUID silenciosamente.
   * **`MCEReporterDisabler.kext`:** A kext desativadora de Machine Check Exceptions deve ser referenciada exatamente como `MCEReporterDisabler.kext` no `BundlePath` (o nome `AppleMCEReporterDisabler.kext` causa Kernel Panic no driver MCE da Apple).
   * **Cryptex & Sealed System Volume (SSV):** No `boot-args` da NVRAM, inclua `-cryptx` e `ipc_control_port_options=0` para que o `CryptexFixup.kext` monte adequadamente os volumes `/System/Volumes/Preboot/Cryptexes/OS/` do macOS Ventura/Sonoma.
   * **Script de Build EFI (`opencore-image-ng.sh`):** Todas as variáveis de diretório devem estar entre aspas duplas (`"$img"`, `"$format"`) e alocação de tamanho deve ser inteira (`402653184`) para suportar diretórios com espaços como `/Virtual Machines/`.

4. **Topologia USB e Contorno do Bluetooth Setup Assistant:**
   * Historicamente, as implementações usavam `ich9` para mapear portas antigas. Contudo, o **macOS Ventura e superiores** falham intermitentemente no reconhecimento inicial de teclados (apresentando a tela de emparelhamento Bluetooth) se usarmos controladores obsoletos.
   * A solução implementada utiliza exclusivamente o **`qemu-xhci`**.
   * **Requisito do OpenCore:** Para que isso funcione sem Kernel Panics ou perda de portas, o EFI do OpenCore deve estar munido das Kexts `USBToolBox.kext` e `UTBMap.kext` pré-geradas mapeando o xHCI virtual.
     ```xml
     <controller type='usb' index='0' model='qemu-xhci'>
       <address type='pci' domain='0x0000' bus='0x00' slot='0x1d' function='0x0'/>
     </controller>
     ```

4. **Workflow Passo a Passo para Usuários e InfraTech:**
   * **Passo 1: Obtenção Automática da Mídia da Apple via `quickget`:**
     O utilitário comunitário `quickget` baixa a mídia oficial da Apple e converte automaticamente:
     ```bash
     quickget macos ventura   # ou sonoma / sequoia
     # Ou via menu interativo:
     ujust macos-utils        # escolha "Download macOS Recovery Media"
     ```
   * **Passo 2: Staging de Firmware OVMF e Correção de SELinux:**
     Copie os arquivos de firmware especializados (`OVMF_CODE_4M.fd`, `OVMF_VARS-1024x768.fd`) e `OpenCore.qcow2` para o pool de virtualização e sincronize as permissões:
     ```bash
     ujust macos-utils        # escolha "Prepare Storage Pool, Firmware & Permissions"
     ```
   * **Passo 3: Registro da VM no Libvirt:**
     No utilitário `ujust macos-utils`, selecione **Register / Define Libvirt Domain** e escolha `macos-ventura`, `macos-sonoma` ou `macos-sequoia` (template em `/usr/share/ublue-os/virtualization/templates/macos.xml`).
   * **Passo 4: Gestão de Snapshots Imutáveis em Btrfs (Rails via `vm-rail`):**
     Para permitir testes destrutivos com reversão em milissegundos sem gastar espaço em disco (custo 0 bytes via Btrfs CoW / `reflink`):
     ```bash
     # 1. Inicializar Rail com Snapshot Base
     vm-rail init macos-ventura default

     # 2. Reverter instantaneamente para o estado limpo
     vm-rail revert macos-ventura

     # 3. Capturar novo snapshot após configurar algo no macOS
     vm-rail capture macos-ventura "pos-setup-assistant"

     # 4. Listar todas as rails e gerações de snapshots
     vm-rail list macos-ventura
     ```
   * **Passo 5: Instalação Automatizada Zero-Touch (Bootstrap Headless via `vm-vision`):**
     O agente de IA executa o provisionamento de ponta a ponta:
     ```bash
     vm-vision bootstrap-macos macos-ventura
     ```
     O orquestrador automatiza:
     1. Reversão do disco para uma geração limpa (`vm-rail revert`).
     2. Seleção do OpenCore Base System no menu de boot.
     3. Bypass da tela de seleção de idioma.
     4. Abertura do Terminal via navegação nativa de teclado na barra de menus.
     5. Formatação do disco em APFS (`Macintosh HD`) e execução do `startosinstall --agreetolicense --nointeraction`.
   * **Passo 6: Acesso, Monitoramento e Agentes (MCP / `vm-vision`):**
     Para monitorar logs do console serial em tempo real ou inspecionar a interface:
     ```bash
     vm-vision logs macos-ventura -n 50
     vm-vision scan macos-ventura
     ```
     Para visualização local em paralelo sem travas de sessão:
     ```bash
     remote-viewer vnc://127.0.0.1:5900
     ```
   * **Passo 7: Desligamento Seguro (Prevenção de Falhas no Host):**
     Para desligar a VM com segurança sem causar resets no subsistema gráfico do host:
     ```bash
     ujust macos-utils        # escolha "Safe Stop / Poweroff (QMP quit)"
     # ou via terminal:
     virsh -c qemu:///system qemu-monitor-command macos-ventura '{"execute": "quit"}'
     ```

5. **Matriz de Validação e Compatibilidade E2E:**

| Versão macOS | Kernel / XNU | Topologia CPU Validada | USB Controller | Rede (SLIRP) | Status E2E | Prova Web (`bazzite.gg`) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **macOS Ventura (13.x)** | XNU 22.x | `Cascadelake-Server-noTSX` (Symmetric) | `qemu-xhci` / `ich9-ehci1` | `vmxnet3` | ✅ 100% OK | Sim (Safari Desktop) |
| **macOS Sonoma (14.x)** | XNU 23.x | `Cascadelake-Server-noTSX` (Symmetric) | `ich9-ehci1` + `ich9-uhci1..3` | `vmxnet3` | ✅ 100% OK | Sim (Safari Desktop) |
| **macOS Sequoia (15.x)** | XNU 24.x | `Cascadelake-Server-noTSX` (Symmetric) | `ich9-ehci1` + `ich9-uhci1..3` | `vmxnet3` | ✅ 100% OK | Sim (Safari Desktop) |
| **macOS Tahoe (16.x)** | XNU 25.x | `Cascadelake-Server-noTSX` (Symmetric) | `ich9-ehci1` + `ich9-uhci1..3` | `vmxnet3` | 🔬 Experimental | Boot OK / Requer SMBIOS Apple Silicon/T2 Bypass |

6. **Gerenciamento de Snapshots Golden Rails (`vm-rail`):**
Cada imagem validada possui um rail imutável em Btrfs CoW (0 bytes extras de disco consumidos para duplicatas). Para restaurar qualquer imagem ao estado limpo pós-instalação:
```bash
# Restaurar macOS Ventura
vm-rail revert macos-ventura ventura-golden-installed

# Restaurar macOS Sonoma
vm-rail revert macos-sonoma sonoma-golden-installed

# Restaurar macOS Sequoia
vm-rail revert macos-sequoia sequoia-golden-installed
```
