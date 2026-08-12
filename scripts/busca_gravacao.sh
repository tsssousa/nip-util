#!/bin/bash

# ==========================================
# Variáveis de Configuração
# ==========================================
BASE_DIR="/hd/monitor"
DEST_DIR="/hd/log/icmp-test/gravacao" # <-- Pasta de destino física no servidor
URL_BASE_PATH="/icmp-test/gravacao"   # <-- Caminho base para a URL web

echo "========================================"
echo "       BUSCA E EXPORTAÇÃO DE GRAVAÇÕES"
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
    echo "[!] Gravações encontradas!"
    
    # Cria o diretório de destino uma única vez
    echo "[+] Preparando pasta de destino: $DEST_DIR"
    mkdir -p "$DEST_DIR"
    
    # Lê a lista de arquivos, mostra na tela e realiza a cópia
    echo "$arquivos" | while read -r arquivo; do
        tamanho=$(du -h "$arquivo" | awk '{print $1}')
        
        # Faz a cópia do arquivo para o destino
        cp "$arquivo" "$DEST_DIR/"
        
        # Mostra na tela o que está acontecendo
        echo " -> Copiado: $arquivo ($tamanho)"
    done
    
    # ==========================================
    # 4. Geração do Link de Acesso Web
    # ==========================================
    echo -e "\n[+] Obtendo IP externo para gerar o link..."
    # O '-s' deixa o curl silencioso (sem mostrar barra de progresso)
    EXTERNAL_IP=$(curl -s ipinfo.io/ip)
    
    # Prevenção: caso o servidor esteja sem internet ou o curl falhe
    if [ -z "$EXTERNAL_IP" ]; then
        EXTERNAL_IP="SEU_IP"
    fi
    
    LINK_WEB="https://${EXTERNAL_IP}:4443${URL_BASE_PATH}"
    
    echo -e "[+] Concluído! Todos os arquivos foram enviados para: $DEST_DIR"
    echo -e "[+] Acesse as gravações pelo navegador no link abaixo:"
    echo -e "\n    -> $LINK_WEB\n"
fi
