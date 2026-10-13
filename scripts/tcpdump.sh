#!/bin/bash

PID_FILE="/tmp/tcpdump_manager.pid"

# ==========================================
# VERIFICAÇÃO E AUTO-NOHUP (Apenas Processo Principal)
# ==========================================
if [ "${AUTO_NOHUP:-0}" -eq 0 ]; then
    
    # 1. Verifica se já está rodando ANTES de exibir o menu
    if [ -f "$PID_FILE" ]; then
        RUNNING_PID=$(cat "$PID_FILE")
        # Verifica se o processo com esse PID realmente existe
        if ps -p "$RUNNING_PID" > /dev/null 2>&1; then
            echo -e "\n[!] Atenção: A captura do tcpdump já está rodando em background! (PID: $RUNNING_PID)\n"
            exit 1
        else
            # Processo não existe (morto à força). Limpa o arquivo obsoleto.
            rm -f "$PID_FILE"
        fi
    fi

    echo "=========================================="
    echo " Escolha o tempo de RETENÇÃO dos logs (.pcap):"
    echo " 1 - 2 horas"
    echo " 2 - 4 horas"
    echo " 3 - 7 horas"
    echo " 4 - 12 horas"
    echo " 5 - 24 horas"
    echo "=========================================="
    read -p "Digite a opção desejada (1-5) [Padrão: 5]: " OPCAO_RETENCAO

    # O rotate time padrão é 7 minutos (420 segundos).
    case "$OPCAO_RETENCAO" in
        1) export RETENTION_MINS=120; export RETENTION_FILES=18 ;;  # ~2 horas
        2) export RETENTION_MINS=240; export RETENTION_FILES=35 ;;  # ~4 horas
        3) export RETENTION_MINS=420; export RETENTION_FILES=60 ;;  # ~7 horas
        4) export RETENTION_MINS=720; export RETENTION_FILES=103 ;; # ~12 horas
        5|"") export RETENTION_MINS=1440; export RETENTION_FILES=206 ;; # ~24 horas
        *) echo "Opção inválida. Usando 24 horas."; export RETENTION_MINS=1440; export RETENTION_FILES=206 ;;
    esac
    
    export RETENTION_HOURS=$((RETENTION_MINS / 60))
    export AUTO_NOHUP=1
    
    # 2. Executa o próprio script em background
    nohup "$0" "$@" > /dev/null 2>&1 &
    BG_PID=$!
    
    # 3. Salva o PID do gerenciador
    echo "$BG_PID" > "$PID_FILE"
    
    echo -e "\n[+] Captura iniciada em background (PID do gerenciador: $BG_PID)."
    echo "[+] Retenção ativa: arquivos mais antigos que ${RETENTION_HOURS}h serão sobrescritos automaticamente."
    exit 0
fi

# ==========================================
# CÓDIGO EM BACKGROUND (Daqui para baixo)
# ==========================================

LOG_DIR="/hd/log/icmp-test"
TCPDUMP_DIR="${LOG_DIR}/tcpdump"
WEB_DIR="/usr/share/mini-httpd/html/icmp-test"
ROTATE_TIME=420          # 420 segundos = 7 minutos

# Quando o script gerenciador for encerrado, matamos os filhos (tcpdump) e limpamos o PID
trap 'rm -f "$PID_FILE"; kill $(jobs -p) 2>/dev/null; exit 0' INT TERM EXIT

# ==========================================
# 0. Identificação do Ambiente (Nuvem vs Física)
# ==========================================
detect_environment() {
    local sys_vendor=""
    if [ -f /sys/class/dmi/id/sys_vendor ]; then
        sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    fi

    if echo "$sys_vendor" | grep -iqE "amazon|google|microsoft|qemu|kvm|vmware|xen|openstack"; then
        echo "NUVEM"
    else
        echo "CENTRAL_FISICA"
    fi
}

ENV_TYPE=$(detect_environment)

# ==========================================
# 1. Preparação dos Diretórios e Limpeza Prévia
# ==========================================
mkdir -p "$TCPDUMP_DIR"

find "$TCPDUMP_DIR" -type f -name "*.pcap" -mmin +"$RETENTION_MINS" -delete 2>/dev/null

if [ ! -d "$WEB_DIR" ]; then
    ln -s "$LOG_DIR" "$WEB_DIR"
else
    rm -rf "$WEB_DIR"
    ln -s "$LOG_DIR" "$WEB_DIR"
fi

# ==========================================
# 2. Seleção de Interface
# ==========================================
if [ "$ENV_TYPE" = "NUVEM" ] && ip link show ens5 >/dev/null 2>&1; then
    interface="ens5"
else
    # Pega a interface da rota principal automaticamente (seguro e sem erro de sintaxe)
    interface=$(ip route show default | awk '/default/ {print $5}' | head -n 1)
    
    if [ -z "$interface" ]; then
        interface="all"
    fi
fi

# ==========================================
# 3. Execução do TCPDump com Retenção Ativa
# ==========================================

if [ "$interface" = "all" ]; then
    # Pega interfaces pulando o loopback (lo)
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v -E "^lo$" | cut -d'@' -f1)
    for i in $interfaces; do
        if [ -n "$i" ]; then
            tcpdump -n -i "$i" \
                -w "${TCPDUMP_DIR}/log_${ENV_TYPE}_${i}_%Y%m%d-%H%M%S.pcap" \
                -G $ROTATE_TIME \
                -W "$RETENTION_FILES" > /dev/null 2>&1 &
        fi
    done
else
    tcpdump -n -i "$interface" \
        -w "${TCPDUMP_DIR}/log_${ENV_TYPE}_${interface}_%Y%m%d-%H%M%S.pcap" \
        -G $ROTATE_TIME \
        -W "$RETENTION_FILES" > /dev/null 2>&1 &
fi

# O 'wait' segura o script rodando em background aguardando os processos tcpdump
wait
