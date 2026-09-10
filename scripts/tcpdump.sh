#!/bin/bash

# ==========================================
# Variáveis de Configuração
# ==========================================
LOG_DIR="/hd/log/icmp-test"
TCPDUMP_DIR="${LOG_DIR}/tcpdump"
WEB_DIR="/usr/share/mini-httpd/html/icmp-test"
ROTATE_TIME=420

# ==========================================
# 0. Identificação do Ambiente (Nuvem vs Física)
# ==========================================
detect_environment() {
    local sys_vendor=""
    if [ -f /sys/class/dmi/id/sys_vendor ]; then
        sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    fi

    # Checa assinaturas comuns de provedores de Nuvem (Cloud) / Hipervisores
    if echo "$sys_vendor" | grep -iqE "amazon|google|microsoft|qemu|kvm|vmware|xen|openstack"; then
        echo "NUVEM"
    else
        echo "CENTRAL_FISICA"
    fi
}

ENV_TYPE=$(detect_environment)
echo "[+] Ambiente identificado: $ENV_TYPE"

# ==========================================
# 1. Preparação dos Diretórios
# ==========================================
echo "[+] Criando diretório de logs..."
mkdir -p "$TCPDUMP_DIR"

echo "[+] Configurando link simbólico para o servidor web..."
if [ ! -d "$WEB_DIR" ]; then
    ln -s "$LOG_DIR" "$WEB_DIR"
else
    rm -rf "$WEB_DIR"
    ln -s "$LOG_DIR" "$WEB_DIR"
fi

# ==========================================
# 2. Seleção de Interface (Com Regra da ens5 em Nuvem)
# ==========================================
echo -e "\n[+] Interfaces de rede disponíveis:"
ifconfig

# Se for NUVEM e a interface ens5 existir no sistema, usa ens5 automaticamente
if [ "$ENV_TYPE" = "NUVEM" ] && ip link show ens5 >/dev/null 2>&1; then
    interface="ens5"
    echo -e "\n[!] Ambiente Nuvem detectado: Selecionando a interface '$interface' automaticamente."
else
    echo ""
    echo -n "Qual interface você deseja usar? (Digite o nome/número ou 'all'): "
    read -r interface
fi

# Valida se uma interface foi definida
if [ -z "$interface" ]; then
    echo "[-] Nenhuma interface fornecida. Cancelando."
    exit 1
fi

# ==========================================
# 3. Execução do TCPDump
# ==========================================
# Formato do datetime: AAAAMMDD-HHMMSS (%Y%m%d-%H%M%S)
# O tcpdump expande as variáveis de tempo nativamente ao usar o parâmetro -G

if [ "$interface" = "all" ]; then
    echo "[+] Você escolheu TODAS as interfaces."
    
    # Pega todas as interfaces ignorando a de loopback (lo)
    interfaces=$(ifconfig | grep -o "^[a-z0-9]*" | grep -v "lo")
    
    for i in $interfaces; do
        if [ -n "$i" ]; then
            echo "    -> Iniciando tcpdump na interface: $i ($ENV_TYPE)"
            nohup tcpdump -n -i "$i" -w "${TCPDUMP_DIR}/log_${ENV_TYPE}_${i}_%Y%m%d-%H%M%S.pcap" -G $ROTATE_TIME > /dev/null 2>&1 &
        fi
    done
else
    echo "[+] Executando na interface: $interface ($ENV_TYPE)"
    nohup tcpdump -n -i "$interface" -w "${TCPDUMP_DIR}/log_${ENV_TYPE}_${interface}_%Y%m%d-%H%M%S.pcap" -G $ROTATE_TIME > /dev/null 2>&1 &
fi

echo -e "\n[+] Captura(s) iniciada(s) em segundo plano com sucesso!"
