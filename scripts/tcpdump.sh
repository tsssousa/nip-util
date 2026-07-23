#!/bin/bash

# ==========================================
# Variáveis de Configuração
# ==========================================
LOG_DIR="/hd/log/icmp-test"
TCPDUMP_DIR="${LOG_DIR}/tcpdump"
WEB_DIR="/usr/share/mini-httpd/html/icmp-test"
ROTATE_TIME=420

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
# 2. Seleção de Interface
# ==========================================
echo -e "\n[+] Interfaces de rede disponíveis:"
ifconfig

echo ""
echo -n "Qual interface você deseja usar? (Digite o nome/número ou 'all'): "
read -r interface

# Valida se o usuário digitou algo
if [ -z "$interface" ]; then
    echo "[-] Nenhuma interface fornecida. Cancelando."
    exit 1
fi

# ==========================================
# 3. Execução do TCPDump
# ==========================================
if [ "$interface" = "all" ]; then
    echo "[+] Você escolheu TODAS as interfaces."
    
    # Pega todas as interfaces ignorando a de loopback (lo)
    interfaces=$(ifconfig | grep -o "^[a-z0-9]*" | grep -v "lo")
    
    for i in $interfaces; do
        if [ -n "$i" ]; then
            echo "    -> Iniciando tcpdump na interface: $i"
            nohup tcpdump -n -i "$i" -w "${TCPDUMP_DIR}/log_${i}_%M.pcap" -G $ROTATE_TIME > /dev/null 2>&1 &
        fi
    done
else
    echo "[+] Você escolheu a interface: $interface"
    nohup tcpdump -n -i "$interface" -w "${TCPDUMP_DIR}/log_${interface}_%M.pcap" -G $ROTATE_TIME > /dev/null 2>&1 &
fi

echo -e "\n[+] Captura(s) iniciada(s) em segundo plano com sucesso!"
