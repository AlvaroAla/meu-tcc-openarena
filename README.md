# Análise de Escalabilidade e Gargalos em Servidores de Jogos Legados (OpenArena)

Este repositório contém a **Infraestrutura como Código (IaC)**, as configurações de telemetria e os scripts de automação desenvolvidos para o Trabalho de Conclusão de Curso (TCC) em **Sistemas de Informação na Universidade Federal de Uberlândia (UFU)**.

O projeto tem como objetivo analisar o comportamento arquitetural, o consumo de recursos (CPU, RAM, Rede, I/O) e evidenciar os limites de processamento *Single-Thread* do motor **id Tech 3** sob estresse contínuo de Inteligência Artificial.

---

## 🏗️ Topologia e Configuração das Máquinas Virtuais (VMs)

O laboratório foi segmentado em três Máquinas Virtuais (Ubuntu Server 24.04) interligadas através de uma rede *Host-Only* (Rede Exclusiva de Hospedeiro - `192.168.56.0/24`), garantindo isolamento de rede e impedindo que o tráfego externo mascare os resultados da coleta.

| Máquina Virtual | IP Fixo | Hardware | Função no Experimento |
| :--- | :--- | :--- | :--- |
| **VM1 - Servidor** | `192.168.56.10` | 1 vCPU / 2GB RAM | Hospedar o servidor OpenArena. A limitação a **1 vCPU** é mandatória para evidenciar o gargalo *Single-Thread* da engine. |
| **VM2 - Telemetria**| `192.168.56.20` | 2 vCPUs / 2GB RAM | Executar Prometheus e Grafana, realizando a raspagem de métricas (scrape) a cada 1 segundo. |
| **VM3 - Injetora** | `192.168.56.30` | 2 vCPUs / 2GB RAM | Executar o script Bash que gera a onda senoidal de conexões UDP (bots via RCON). |

---

## 📁 Estrutura do Repositório

```text
meu-tcc-openarena/
├── vm1-servidor/
│   ├── docker-compose.yml       # Orquestração do servidor de jogo
│   └── configs/
│       └── server.cfg           # Configurações in-game (Tickrate, Mapa, I.A.)
├── vm2-telemetria/
│   ├── prometheus.yml           # Arquivo de configuração de alvos de coleta (1s)
│   ├── docker-compose.yml       # Arquivo docker
│   └── grafana/
│       └── dashboard.json       # Layout do painel com as queries PromQL tratadas
├── vm3-injetora/
│   └── scripts/
│       └── bots_senoidal.sh     # Algoritmo matemático para injeção de carga senoidal
├── dados-coletados/             # Diretório para armazenamento das exportações brutas (.csv)
└── docs/                        # Relatórios, prints de arquitetura e PDF explicativo
```

---

## 🛠️ Passo a Passo de Implementação

### Pré-requisitos (Todas as VMs)
Certifique-se de que o **Docker**, o **Docker Compose** e as ferramentas de rede estão instalados em todas as máquinas.

```bash
sudo apt update
sudo apt install docker.io docker-compose unzip curl bc -y
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

---

### Passo 1: Configurar e Subir o Servidor de Jogo (VM1)

Na VM1, também é necessário instalar o serviço do `node_exporter` direto no host para exportar as métricas da máquina virtual para o Prometheus.

**1.1. Instalação do Node Exporter:**
```bash
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.0/node_exporter-1.8.0.linux-amd64.tar.gz
tar -xvzf node_exporter-1.8.0.linux-amd64.tar.gz
sudo cp node_exporter-1.8.0.linux-amd64/node_exporter /usr/local/bin/
sudo useradd -rs /bin/false node_exporter

# Crie o serviço Systemd
sudo bash -c 'cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF'

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

**1.2. Inicialização do Servidor OpenArena:**
Navegue até a pasta do projeto `vm1-servidor` e inicie o servidor com as configurações de estresse (`com_hunkMegs 512`, mapa `oa_dm1` e `sv_fps 500`).
```bash
cd meu-tcc-openarena/vm1-servidor
docker-compose up -d
```

---

### Passo 2: Configurar a Telemetria (VM2)

O ambiente de monitoramento utiliza janelas estreitas (`scrape_interval: 1s`) para captar com precisão as oscilações curtas da CPU e da rede.

**2.1. Iniciar o Monitoramento:**
Navegue até a pasta `vm2-telemetria` e suba os contêineres:
```bash
cd meu-tcc-openarena/vm2-telemetria
docker-compose up -d
```

**2.2. Importar o Painel:**
1. Acesse `http://192.168.56.20:3000` (Usuário: `admin` / Senha: `admin`).
2. Acesse a seção *Dashboards* > *Import*.
3. Faça o upload do arquivo `dashboard.json` presente em `vm2-telemetria/grafana/`.

---

### Passo 3: Executar a Metodologia de Testes (VM3)

Ao contrário de abordagens antigas que rodavam clientes pesados via interface gráfica, nosso injetor utiliza comandos UDP diretos (RCON) para alocar bots nativos do motor, otimizando o envio e permitindo alta densidade. Os bots são configurados com a skin `"sarge"` para evitar estouro da Hunk Memory.

Navegue até a pasta da Injetora e dê permissão de execução:
```bash
cd meu-tcc-openarena/vm3-injetora/scripts
chmod +x bots_senoidal.sh
```

**Cenário A: Baseline (Baixa Carga)**
Uma onda suave operando entre 2 e 10 bots, definindo o padrão de consumo em modo de repouso.
```bash
HOST=192.168.56.10 PORT=27960 RCON_PASS=sua_senha OFFSET=6 AMP=4 PERIOD=600 MIN=2 MAX=10 STEP=15 ./bots_senoidal.sh
```

**Cenário B: Teste de Estresse (Alta Carga)**
Força a engine aos seus limites matemáticos de colisão, oscilando agressivamente entre 15 e 25 bots sem derrubar a arquitetura.
```bash
HOST=192.168.56.10 PORT=27960 RCON_PASS=sua_senha OFFSET=20 AMP=5 PERIOD=600 MIN=15 MAX=25 STEP=15 ./bots_senoidal.sh
```

---

## 📊 Extração de Resultados (CSV)

O painel configurado no Grafana já inclui tabelas normalizadas (`VM1-Geral` e `VM3-Geral`) parametrizadas em grandezas absolutas.
Para gerar o CSV da monografia:
1. Clique nos três pontos (⋮) no topo do painel da Tabela > **Inspect** > **Data**.
2. Marque as opções **Apply panel transformations** e **Formatted data**.
3. Clique em **Download CSV**. 
4. O arquivo gerado unificará as métricas de Rede (B/s), Disco (B/s), RAM (%) e CPU (%) linha por linha a cada segundo.

---

## 📌 Conclusões Arquiteturais Coletadas
1. **O Falso Paradoxo de Escalabilidade:** Servidores baseados em arquiteturas legadas (*id Tech 3*) não escalam verticalmente. A adição de múltiplos núcleos não melhora a performance, visto que o processamento da IA (`botlib` e AAS) depende de uma única *thread*.
2. **O Ponto de Saturação (CPU):** Um único núcleo moderno resolve a física do jogo rapidamente e permanece ocioso à espera do próximo tickrate. Mesmo elevando o `sv_fps` para `500` (overclock da engine), o limite máximo de estresse absoluto de CPU extraível com 25 bots se consolida na faixa de **43% a 47%**.
3. **Colapso Estrutural:** O servidor não falha por falta de hardware na VM hospedeira, mas sim por limites de alocação de blocos na memória de 32-bits e estrangulamento na fila UDP da thread principal.
