#!/bin/bash

# ----------------------------------------------------------------------
# Script de Automação: Estrutura de Logs e Ajuste do AMD (nip-discadord)
# ----------------------------------------------------------------------

LOG_DIR="/hd/log/icmp-test/classificador"
LOG_FILE="$LOG_DIR/nip-discadord-amd.log"
VAR_LOG_LINK="/var/log/nip-discadord-amd.log"
CFG_LOG_DIR="/cfg/cust/raiz/var/log"
CFG_LOG_LINK="$CFG_LOG_DIR/nip-discadord-amd.log"
AMD_CONF="/etc/asterisk/amd.conf"

echo "[1/5] Criando diretórios no HD e ajustando permissões..."
mkdir -p "$LOG_DIR"
chmod -R 775 "$LOG_DIR"

echo "[2/5] Montando a partição /cfg..."
mount /cfg/ 2>/dev/null

echo "[3/5] Configurando links simbólicos em /var/log e /cfg..."
# Mover log antigo caso exista como arquivo regular
if [ -f "$VAR_LOG_LINK" ] && [ ! -L "$VAR_LOG_LINK" ]; then
    mv "$VAR_LOG_LINK" "$LOG_DIR/" 2>/dev/null
fi

# Criar link principal no /var/log
ln -sf "$LOG_FILE" "$VAR_LOG_LINK"

# Criar estrutura e link de persistência na partição /cfg
mkdir -p "$CFG_LOG_DIR"
ln -sf "$LOG_FILE" "$CFG_LOG_LINK"

echo "[4/5] Desmontando a partição /cfg..."
umount /cfg/ 2>/dev/null

echo "[5/5] Atualizando /etc/asterisk/amd.conf para reduzir caixa postal..."
if [ -f "$AMD_CONF" ]; then
    # Backup da configuração original
    cp "$AMD_CONF" "${AMD_CONF}.bak_$(date +%Y%m%d_%H%M%S)"

    # Sobrescreve o bloco [general] com os parâmetros otimizados
    cat << 'EOF' > "$AMD_CONF"
[general]
initial_silence = 2500
greeting = 1200
after_greeting_silence = 800
total_analysis_time = 4000
min_word_length = 100
between_words_silence = 50
maximum_number_of_words = 2
silence_threshold = 256
EOF
else
    echo "Aviso: $AMD_CONF não encontrado. Pulando etapa do AMD."
fi

echo "[Reboot] Reiniciando serviço do discador..."
if [ -f "/etc/init.d/nip-discadord" ]; then
    /etc/init.d/nip-discadord stop
    sleep 1
    /etc/init.d/nip-discadord start
    echo "Serviço NIP-DISCADORD reiniciado com sucesso."
else
    echo "Aviso: Script /etc/init.d/nip-discadord não encontrado."
fi

echo "--- Processo concluído com sucesso! ---"
