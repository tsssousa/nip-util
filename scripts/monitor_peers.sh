#!/bin/bash

PID_FILE="/tmp/monitor_peers.pid"

# ==========================================
# VERIFICAÇÃO E AUTO-NOHUP (Apenas Processo Principal)
# ==========================================
if [ "${AUTO_NOHUP:-0}" -eq 0 ]; then
    
    # 1. Verifica se já está rodando ANTES de exibir o menu
    if [ -f "$PID_FILE" ]; then
        RUNNING_PID=$(cat "$PID_FILE")
        if ps -p "$RUNNING_PID" > /dev/null 2>&1; then
            echo -e "\n[!] Atenção: O monitoramento já está rodando em background! (PID: $RUNNING_PID)\n"
            exit 1
        else
            # Limpa PID fantasma de execução morta abruptamente
            rm -f "$PID_FILE"
        fi
    fi

    echo "=========================================="
    echo " Escolha o tempo de retenção dos logs:"
    echo " 1 - 24 horas"
    echo " 2 - 36 horas"
    echo " 3 - 48 horas"
    echo " 4 - 7 dias"
    echo "=========================================="
    read -p "Digite a opção desejada (1-4) [Padrão: 4]: " OPCAO_RETENCAO

    case "$OPCAO_RETENCAO" in
        1) export MINUTOS_RETENCAO=1440 ;;  # 24h * 60m
        2) export MINUTOS_RETENCAO=2160 ;;  # 36h * 60m
        3) export MINUTOS_RETENCAO=2880 ;;  # 48h * 60m
        4|"") export MINUTOS_RETENCAO=10080 ;; # 7d * 24h * 60m
        *) echo "Opção inválida. Usando 7 dias por padrão."; export MINUTOS_RETENCAO=10080 ;;
    esac

    export AUTO_NOHUP=1
    
    # 2. Inicia em background
    nohup "$0" "$@" > /dev/null 2>&1 &
    
    # 3. Salva o PID do processo em background
    BG_PID=$!
    echo "$BG_PID" > "$PID_FILE"
    
    echo -e "\nMonitoramento iniciado em background com nohup (PID $BG_PID)."
    echo "Os logs serão mantidos por $(($MINUTOS_RETENCAO / 60)) horas."
    echo "Acompanhe os logs em: /hd/log/icmp-test/monitor_Ip/"
    exit 0
fi

# ==========================================
# CÓDIGO EM BACKGROUND (Daqui para baixo)
# ==========================================
# Uso: ./monitor_peers.sh [intervalo_segundos] [opcao_modo_1_a_3]

set -uo pipefail

INTERVALO="${1:-5}"
OPCAO="${2:-1}"  # Padrão é o Modo 1 (Crítico) se não for especificado

DIR_TMP=$(mktemp -d)
ANTERIOR="$DIR_TMP/anterior.txt"
ATUAL="$DIR_TMP/atual.txt"

DIR_LOG="/hd/log/icmp-test/monitor_Ip"
mkdir -p "$DIR_LOG"

# Garante que o arquivo PID seja deletado quando o monitoramento for parado
trap 'rm -rf "$DIR_TMP"; rm -f "$PID_FILE"; echo -e "\n\nMonitoramento encerrado."; exit 0' INT TERM EXIT

# ==========================================
# DEFINIÇÃO DO MODO DE FILTRO
# ==========================================
case "$OPCAO" in
    1|"CRITICO")
        MODE="CRITICO"
        ;;
    2|"REDE")
        MODE="REDE"
        ;;
    3|"TUDO"|"HARDCORE")
        MODE="TUDO"
        ;;
    *)
        MODE="CRITICO"
        ;;
esac

# ==========================================
# GESTÃO DE LOGS E RETENÇÃO DINÂMICA
# ==========================================
atualizar_arquivo_log() {
    NOVO_LOG="$DIR_LOG/registro_$(date '+%Y-%m-%d').txt"
    
    RETENCAO_ATUAL="${MINUTOS_RETENCAO:-10080}"
    
    if [ "${ARQUIVO_LOG:-}" != "$NOVO_LOG" ]; then
        ARQUIVO_LOG="$NOVO_LOG"
        find "$DIR_LOG" -type f -name "registro_*.txt" -mmin +"$RETENCAO_ATUAL" -delete 2>/dev/null
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
        
        dados["peer"] = partes[1]

        if (match(linha, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)) {
            dados["ip"] = substr(linha, RSTART, RLENGTH)
        }

        if (linha ~ / UNREACHABLE/) dados["status"] = "UNREACHABLE"
        else if (linha ~ / UNKNOWN/) dados["status"] = "UNKNOWN"
        else if (linha ~ / OK/) dados["status"] = "OK"
        else if (linha ~ / LAGGED/) dados["status"] = "LAGGED"
        else if (linha ~ / REJECTED/) dados["status"] = "REJECTED"

        if (match(linha, /\([0-9]+ ms\)/)) {
            substring = substr(linha, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", substring)
            dados["ms"] = substring
        }

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

            if (status_ant[peer] != atu["status"]) {
                motivo = motivo "    - Status alterado de [" status_ant[peer] "] para [" atu["status"] "]\n"
                mudou = 1
            }

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

            if (modo == "TUDO") {
                diff = atu["ms"] - ms_ant[peer]
                if (diff < 0) diff = -diff
                
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
