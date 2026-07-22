#!/bin/bash
# monitor_peers.sh - Monitoramento Inteligente de Peers SIP com Linha de Corte e Logs de 1h
# Uso: ./monitor_peers.sh [intervalo_segundos] [opcao_modo_1_a_3]
# Exemplo background: nohup ./monitor_peers.sh 5 2 > /dev/null 2>&1 &

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
# DEFINIÇÃO DO MODO DE FILTRO (VIA PARÂMETRO)
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
        echo -e "-> Foco definido: Monitoramento Completo (Gera mais logs)."
        ;;
    *)
        MODE="CRITICO"
        echo -e "-> Opção inválida recebida. Usando padrão: Apenas Desconexões Reais."
        ;;
esac

# Função para definir o nome do arquivo baseado na hora atual (ex: registro_2026-06-10_13h.txt)
atualizar_arquivo_log() {
    ARQUIVO_LOG="$DIR_LOG/registro_$(date '+%Y-%m-%d_%Hh').txt"
}

# Inicializa o primeiro arquivo de log
atualizar_arquivo_log

echo "----------------------------------------------------------"
echo "Monitorando peers SIP a cada ${INTERVALO}s... (Ctrl+C para parar)"
echo "Logs de 1h salvos em: $DIR_LOG/"
echo "---"

get_peers() {
    asterisk -rx "sip show peers" | tail -n +2 | head -n -1 | tr -s ' '
}

get_peers > "$ANTERIOR"
TOTAL_PEERS=$(wc -l < "$ANTERIOR")
MSG_INICIAL="[$(date '+%Y-%m-%d %H:%M:%S')] Monitoramento Iniciado Modo [$MODE] (${TOTAL_PEERS} peers)"

echo "$MSG_INICIAL"
echo "========================================" >> "$ARQUIVO_LOG"
echo "$MSG_INICIAL" >> "$ARQUIVO_LOG"

while sleep "$INTERVALO"; do
    # RECALCULA O NOME DO ARQUIVO: Se mudou a hora no sistema, o script passa a gravar no arquivo novo automaticamente
    atualizar_arquivo_log

    get_peers > "$ATUAL"

    MUDANCAS=$(awk -v data_hora="$(date '+%Y-%m-%d %H:%M:%S')" -v modo="$MODE" '
    function extrair_dados(linha, dados) {
        dados["ip"] = "Unspecified"
        dados["porta"] = "0"
        dados["status"] = "UNKNOWN"
        dados["ms"] = "0"

        split(linha, partes, " ")
        dados["peer"] = partes[1]

        if (linha ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
            match(linha, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/)
            dados["ip"] = substr(linha, RSTART, RLENGTH)

            if (match(linha, /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ [0-9]+/)) {
                split(substr(linha, RSTART, RLENGTH), ip_p, " ")
                dados["porta"] = ip_p[2]
            }
        }

        # Isola o status macro (OK, UNREACHABLE, etc) e extrai o ms de forma limpa
        if (linha ~ / UNREACHABLE /) dados["status"] = "UNREACHABLE"
        else if (linha ~ / UNKNOWN /) dados["status"] = "UNKNOWN"
        else if (linha ~ / OK /) {
            dados["status"] = "OK"
            if (match(linha, /\([0-9]+ ms\)/)) {
                substring = substr(linha, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", substring)
                dados["ms"] = substring
            }
        }
        else if (linha ~ / LAGGED /) {
            dados["status"] = "LAGGED"
            if (match(linha, /\([0-9]+ ms\)/)) {
                substring = substr(linha, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", substring)
                dados["ms"] = substring
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

            # Validação baseada no modo escolhido
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
                if (ms_ant[peer] != atu["ms"] && status_ant[peer] == "OK" && atu["status"] == "OK") {
                    motivo = motivo "    - Latência variou de [" ms_ant[peer] "ms] para [" atu["ms"] "ms]\n"
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
        # Qualquer remoção/queda total entra em qualquer modo por ser Crítico
        for (i in presente) {
            print "[" data_hora "] === RAMAL FICOU OFFLINE OU FOI REMOVIDO ==="
            print "< " linha_antiga[i] "\n"
        }
    }' "$ANTERIOR" "$ATUAL")

    if [ -n "$MUDANCAS" ]; then
        echo -e "\r\033[K\n$MUDANCAS"
        echo "$MUDANCAS" >> "$ARQUIVO_LOG"
    else
        echo -ne "\r\033[K[$(date '+%H:%M:%S')] Monitorando no modo [$MODE]... Sem alterações críticas."
    fi

    cp "$ATUAL" "$ANTERIOR"
done
