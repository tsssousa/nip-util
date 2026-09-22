#!/bin/bash

# ==========================================
# AUTO-NOHUP (Joga para background automaticamente)
# ==========================================
if [ "${AUTO_NOHUP:-0}" -eq 0 ]; then
    export AUTO_NOHUP=1
    nohup "$0" "$@" > /dev/null 2>&1 &
    echo "Monitoramento iniciado em background com nohup (PID $!)."
    echo "Acompanhe os logs em: /hd/log/icmp-test/monitor_Ip/"
    exit 0
fi

# monitor_peers.sh - Monitoramento Inteligente de Peers SIP com Linha de Corte e Logs de 1h
# Uso: ./monitor_peers.sh [intervalo_segundos] [opcao_modo_1_a_3]

set -uo pipefail

INTERVALO="${1:-5}"
OPCAO="${2:-1}"  # Padrão é o Modo 1 (Crítico) se não for especificado

DIR_TMP=$(mktemp -d)
ANTERIOR="$DIR_TMP/anterior.txt"
ATUAL="$DIR_TMP/atual.txt"

DIR_LOG="/hd/log/icmp-test/monitor_Ip"
mkdir -p "$DIR_LOG"

trap 'rm -rf "$DIR_TMP"; echo -e "\n\nMonitoramento encerrado."; exit 0' INT TERM

# ==========================================
# DEFINIÇÃO DO MODO DE FILTRO
# ==========================================
case "$OPCAO" in
    1|"CRITICO")
        MODE="CRITICO"
        echo -e "-> Foco definido: Apenas Desconexões Reais."
        ;;
    2|"REDE")
        MODE="REDE"
        echo -e "-> Foco definido: Desconexões e Alterações de IP/Porta."
        ;;
    3|"TUDO"|"HARDCORE")
        MODE="TUDO"
        echo -e "-> Foco definido: Monitoramento Completo (Gera mais logs, tolerância de 20ms)."
        ;;
    *)
        MODE="CRITICO"
        echo -e "-> Opção inválida recebida. Usando padrão: Apenas Desconexões Reais."
        ;;
esac

# ==========================================
# GESTÃO DE LOGS E RETENÇÃO DE 24H
# ==========================================
atualizar_arquivo_log() {
    NOVO_LOG="$DIR_LOG/registro_$(date '+%Y-%m-%d_%Hh').txt"
    
    # Se for a primeira execução ou se a hora mudou, atualiza a variável e faz a limpeza
    if [ "${ARQUIVO_LOG:-}" != "$NOVO_LOG" ]; then
        ARQUIVO_LOG="$NOVO_LOG"
        # Limpa arquivos de log que tenham mais de 24 horas (1440 minutos)
        find "$DIR_LOG" -type f -name "registro_*.txt" -mmin +1440 -delete 2>/dev/null
    fi
}

atualizar_arquivo_log

get_peers() {
    asterisk -rx "sip show peers" | tail -n +2 | head -n -1 | tr -s ' '
}

get_peers > "$ANTERIOR"
TOTAL_PEERS=$(wc -l < "$ANTERIOR")
MSG_INICIAL="[$(date '+%Y-%m-%d %H:%M:%S')] Monitoramento Iniciado Modo [$MODE] (${TOTAL_PEERS} peers)"

echo "$MSG_INICIAL" >> "$ARQUIVO_LOG"
echo "========================================" >> "$ARQUIVO_LOG"

while sleep "$INTERVALO"; do
    atualizar_arquivo_log
    get_peers > "$ATUAL"

    MUDANCAS=$(awk -v data_hora="$(date '+%Y-%m-%d %H:%M:%S')" -v modo="$MODE" '
    function extrair_dados(linha, dados) {
        dados["ip"] = "Unspecified"
        dados["porta"] = "0"
        dados["status"] = "UNKNOWN"
        dados["ms"] = "0"

        n = split(linha, partes, " ")
        
        # O nome do peer no Asterisk costuma ser o campo 1
        dados["peer"] = partes[1]

        # 1. Extrai IP exato via Regex
        if (match(linha, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            dados["ip"] = substr(linha, RSTART, RLENGTH)
        }

        # 2. Extrai Status
        if (linha ~ / UNREACHABLE/) dados["status"] = "UNREACHABLE"
        else if (linha ~ / UNKNOWN/) dados["status"] = "UNKNOWN"
        else if (linha ~ / OK/) dados["status"] = "OK"
        else if (linha ~ / LAGGED/) dados["status"] = "LAGGED"
        else if (linha ~ / REJECTED/) dados["status"] = "REJECTED"

        # 3. Extrai Latência Limpa
        if (match(linha, /\([0-9]+ ms\)/)) {
            substring = substr(linha, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", substring)
            dados["ms"] = substring
        }

        # 4. Extrai Porta (MUITO MAIS PRECISO)
        # Na saída do Asterisk, a porta é sempre a coluna anterior ao Status
        for (i = 1; i <= n; i++) {
            if (partes[i] ~ /^(OK|UNREACHABLE|UNKNOWN|LAGGED|REJECTED)/) {
                if (i > 1 && partes[i-1] ~ /^[0-9]+$/) {
                    dados["porta"] = partes[i-1]
                }
                break
            }
        }
    }

    NR==FNR {
        linha_antiga[$1] = $0
        extrair_dados($0, ant)
        ip_ant[$1] = ant["ip"]
        porta_ant[$1] = ant["porta"]
        status_ant[$1] = ant["status"]
        ms_ant[$1] = ant["ms"]
        presente[$1] = 1
        next
    }
    {
        peer = $1
        extrair_dados($0, atu)

        if (!(peer in presente)) {
            if (modo == "TUDO") {
                print "[" data_hora "] === NOVO RAMAL REGISTRADO ==="
                print "> " $0 "\n"
            }
        } else {
            mudou = 0
            motivo = ""

            # Critico: Mudança de Status
            if (status_ant[peer] != atu["status"]) {
                motivo = motivo "    - Status alterado de [" status_ant[peer] "] para [" atu["status"] "]\n"
                mudou = 1
            }

            # Rede: IP ou Porta
            if (modo == "REDE" || modo == "TUDO") {
                if (ip_ant[peer] != atu["ip"]) {
                    motivo = motivo "    - IP alterado de [" ip_ant[peer] "] para [" atu["ip"] "]\n"
                    mudou = 1
                }
                if (porta_ant[peer] != atu["porta"] && atu["porta"] != "0" && porta_ant[peer] != "0") {
                    motivo = motivo "    - Porta alterada de [" porta_ant[peer] "] para [" atu["porta"] "]\n"
                    mudou = 1
                }
            }

            # Tudo: Variações bruscas de Latência
            if (modo == "TUDO") {
                diff = atu["ms"] - ms_ant[peer]
                if (diff < 0) diff = -diff
                
                # Tolerância de 20ms para evitar logs de oscilação normal (jitter)
                if (diff >= 20 && status_ant[peer] == "OK" && atu["status"] == "OK") {
                    motivo = motivo "    - Latência variou drasticamente de [" ms_ant[peer] "ms] para [" atu["ms"] "ms]\n"
                    mudou = 1
                }
            }

            if (mudou) {
                print "[" data_hora "] === ALTERAÇÃO NO RAMAL: " peer " ==="
                print "Anterior: " linha_antiga[peer]
                print "Atual:    " $0
                printf "%s\n", motivo
            }
            delete presente[peer]
        }
    }
    END {
        for (i in presente) {
            print "[" data_hora "] === RAMAL FICOU OFFLINE OU FOI REMOVIDO ==="
            print "< " linha_antiga[i] "\n"
        }
    }' "$ANTERIOR" "$ATUAL")

    if [ -n "$MUDANCAS" ]; then
        echo "$MUDANCAS" >> "$ARQUIVO_LOG"
    fi

    cp "$ATUAL" "$ANTERIOR"
done
