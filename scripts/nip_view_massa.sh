#!/bin/bash

# ==========================================
# Configurações Iniciais
# ==========================================
SSH_USER="root"
IP_FILE="ips.txt"

# ==========================================
# 1. Identificação Automática do Pacote
# ==========================================
PACKAGE=$(ls nip-view-package_*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$PACKAGE" ]; then
    echo "[-] Erro: Nenhum arquivo 'nip-view-package_*.tar.gz' encontrado nesta pasta!"
    exit 1
fi

RELEASE=$(echo "$PACKAGE" | sed 's/nip-view-package_//;s/\.tar\.gz//')

echo "[+] Pacote encontrado automaticamente: $PACKAGE"
echo "[+] Release identificada: $RELEASE"

REMOTE_UPLOAD_DIR="/hd/dev/nip-view"
REMOTE_EXTRACT_DIR="/hd/dev/nip-view-${RELEASE}"

# ==========================================
# 2. Validações Locais
# ==========================================
if [ ! -f "$IP_FILE" ]; then
    echo "[-] Erro: O arquivo de IPs '$IP_FILE' não existe na pasta atual."
    exit 1
fi

# ==========================================
# 3. Execução do Deploy
# ==========================================
echo -e "\n[+] Iniciando processo de deploy em massa..."

while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue

    echo -e "\n=========================================================="
    echo "🚀 Processando IP: $ip"
    echo "=========================================================="

    # 3.1 Cria as pastas no servidor remoto
    echo "   [1/3] Criando diretórios remotos..."
    ssh -n "${SSH_USER}@${ip}" "mkdir -p ${REMOTE_UPLOAD_DIR} ${REMOTE_EXTRACT_DIR}"
    if [ $? -ne 0 ]; then
        echo "   [-] Falha de conexão ou permissão no IP $ip. Pulando."
        continue
    fi

    # 3.2 Envia o arquivo tar.gz
    echo "   [2/3] Enviando pacote ${PACKAGE}..."
    scp "${PACKAGE}" "${SSH_USER}@${ip}:${REMOTE_UPLOAD_DIR}/"
    if [ $? -ne 0 ]; then
        echo "   [-] Erro na transferência para o IP $ip. Pulando."
        continue
    fi

    # 3.3 Extrai, instala e LIMPA
    echo "   [3/3] Extraindo, instalando e limpando..."
    ssh -n "${SSH_USER}@${ip}" "
        echo '      -> Descompactando para ${REMOTE_EXTRACT_DIR}...'
        tar -xzf ${REMOTE_UPLOAD_DIR}/${PACKAGE} -C ${REMOTE_EXTRACT_DIR}/
        
        echo '      -> Ajustando permissões dos arquivos .sh...'
        cd ${REMOTE_EXTRACT_DIR} || exit 1
        find . -type f -name '*.sh' -exec chmod +x {} \\;
        
        echo '      -> Rodando install.sh...'
        if ./install.sh next \$(pwd); then
            echo '      -> Instalação concluída com sucesso! Limpando arquivos temporários...'
            
            # Sai da pasta antes de apagá-la (para não dar erro de 'dispositivo ocupado')
            cd / 
            rm -rf ${REMOTE_UPLOAD_DIR} ${REMOTE_EXTRACT_DIR}
        else
            echo '      -> [ERRO] Falha no install.sh. Os arquivos foram mantidos em ${REMOTE_EXTRACT_DIR} para analise.'
            exit 1
        fi
    "

    if [ $? -eq 0 ]; then
        echo "   [+] Deploy concluído e rastro apagado em $ip!"
    else
        echo "   [-] Deploy falhou durante a execução remota em $ip."
    fi

done < "$IP_FILE"

echo -e "\n[+] Todos os servidores da lista foram processados!"
