#!/bin/bash

# ==========================================
# Variáveis de Configuração
# ==========================================
BASE_DIR="/hd/monitor"

echo "========================================"
echo "       BUSCA DE GRAVAÇÕES"
echo "========================================"

# 1. Pede o número (pode ser o telefone do cliente ou um ramal)
echo -n "Digite o número (telefone do cliente ou ramal) para buscar: "
read -r numero

if [ -z "$numero" ]; then
    echo "[-] Nenhum número informado. Cancelando."
    exit 1
fi

# 2. Pede a data para otimizar a busca (opcional)
echo -n "Deseja filtrar por data? (Ex: 2026-08-11 ou pressione ENTER para buscar em tudo): "
read -r data_filtro

if [ -n "$data_filtro" ]; then
    SEARCH_DIR="${BASE_DIR}/${data_filtro}"
    if [ ! -d "$SEARCH_DIR" ]; then
        echo "[-] Erro: O diretório $SEARCH_DIR não existe. Verifique a data."
        exit 1
    fi
else
    SEARCH_DIR="$BASE_DIR"
fi

# 3. Executa a busca
echo -e "\n[+] Buscando por arquivos contendo '*${numero}*' em $SEARCH_DIR...\n"

# O comando find procura arquivos (-type f) ignorando maiúsculas/minúsculas (-iname)
arquivos=$(find "$SEARCH_DIR" -type f -iname "*${numero}*.wav" 2>/dev/null)

if [ -z "$arquivos" ]; then
    echo "[-] Nenhuma gravação encontrada para o número: $numero"
else
    echo "[!] Gravações encontradas:"
    
    # Lê a lista de arquivos e formata a saída mostrando o tamanho
    echo "$arquivos" | while read -r arquivo; do
        tamanho=$(du -h "$arquivo" | awk '{print $1}')
        echo " -> $arquivo (Tamanho: $tamanho)"
    done
fi
echo ""
