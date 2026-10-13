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
    echo "[!] Gravações encontradas:"
    
    # Lista os arquivos encontrados antes de perguntar
    echo "$arquivos" | while read -r arquivo; do
        tamanho=$(du -h "$arquivo" | awk '{print $1}')
        echo " -> $arquivo ($tamanho)"
    done
    
    # Pergunta se o usuário deseja copiar
    echo -e "\n[?] Deseja copiar e compactar os arquivos encontrados para $DEST_DIR? [s/N]: \c"
    read -r confirmar_copia

    if [[ "$confirmar_copia" =~ ^[Ss]$ ]]; then
        # Cria o diretório de destino uma única vez
        echo -e "\n[+] Preparando pasta de destino: $DEST_DIR"
        mkdir -p "$DEST_DIR"
        
        # Realiza a cópia
        echo -e "[+] Copiando arquivos..."
        echo "$arquivos" | while read -r arquivo; do
            cp "$arquivo" "$DEST_DIR/"
            echo " -> Copiado: $(basename "$arquivo")"
        done
        
        # ==========================================
        # 4. Compactação dos arquivos para Download
        # ==========================================
        echo -e "\n[+] Gerando arquivo compactado para download..."
        
        # Usamos um subshell ( ) para entrar na pasta temporariamente e compactar
        if command -v zip &> /dev/null; then
            NOME_COMPACTADO="gravacoes_${numero}_$(date +%Y%m%d_%H%M%S).zip"
            (cd "$DEST_DIR" && zip -q "$NOME_COMPACTADO" *"${numero}"*.wav)
            echo " -> Criado arquivo ZIP: $NOME_COMPACTADO"
        else
            # Fallback (plano B): se não tiver o pacote "zip" instalado, usa o "tar" que é nativo do Linux
            NOME_COMPACTADO="gravacoes_${numero}_$(date +%Y%m%d_%H%M%S).tar.gz"
            (cd "$DEST_DIR" && tar -czf "$NOME_COMPACTADO" *"${numero}"*.wav)
            echo " -> Criado arquivo TAR.GZ: $NOME_COMPACTADO"
        fi
        
        # ==========================================
        # 5. Geração do Link de Acesso Web
        # ==========================================
        echo -e "\n[+] Obtendo IP externo para gerar os links..."
        EXTERNAL_IP=$(curl -s ipinfo.io/ip)
        
        # Prevenção: caso o servidor esteja sem internet ou o curl falhe
        if [ -z "$EXTERNAL_IP" ]; then
            EXTERNAL_IP="SEU_IP"
        fi
        
        LINK_PASTA="https://${EXTERNAL_IP}:4443${URL_BASE_PATH}"
        LINK_DOWNLOAD="https://${EXTERNAL_IP}:4443${URL_BASE_PATH}/${NOME_COMPACTADO}"
        
        echo -e "[+] Concluído! Todos os arquivos foram enviados e compactados com sucesso."
        echo -e "\n[+] Entregue estes links para o cliente:"
        echo -e "    -> Para OUVIR pelo navegador (Pasta): $LINK_PASTA"
        echo -e "    -> Para BAIXAR todos de uma vez:      $LINK_DOWNLOAD\n"
    else
        echo -e "\n[-] Ação cancelada pelo usuário."
    fi
fi
