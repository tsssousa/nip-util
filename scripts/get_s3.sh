#!/bin/bash

DEST_DIR="/hd/dir_dev/pcap"
BUCKET="s3://nextip-kamailio-logs/kamailio-dump"
SBCS=("172-30-2-12" "172-30-3-75")

mkdir -p "$DEST_DIR"

read -p "Digite a data desejada (DD/MM/AAAA) [ex: 15/09/2026]: " DATA_INPUT

if [ -z "$DATA_INPUT" ]; then
    echo "❌ Data obrigatória."
    exit 1
fi

read -p "Digite a hora desejada (HH) [ex: 14 para 14h, ou Enter para todas]: " HORA_INPUT

DIA=$(echo "$DATA_INPUT" | cut -d'/' -f1)
MES=$(echo "$DATA_INPUT" | cut -d'/' -f2)
ANO=$(echo "$DATA_INPUT" | cut -d'/' -f3)

S3_PATH_SUFFIX="$ANO/$MES/$DIA"
DATA_NOMES="$ANO-$MES-$DIA"

echo -e "\n🔍 Buscando arquivos para a data $DATA_INPUT nos SBCs..."

LISTA_EXIBICAO=()
TAMANHOS=()
S3_URLS=()

for sbc in "${SBCS[@]}"; do
    CANDIDATE_PATH="$BUCKET/$sbc/$S3_PATH_SUFFIX/"
    
    # Obtém as linhas com data, hora, tamanho legível e caminho do arquivo
    FOUND_RAW=$(aws s3 ls "$CANDIDATE_PATH" --recursive --human-readable 2>/dev/null)
    
    if [ -n "$HORA_INPUT" ]; then
        FOUND_RAW=$(echo "$FOUND_RAW" | grep "_${DATA_NOMES}_${HORA_INPUT}-")
    fi
    
    while read -r line; do
        if [ -n "$line" ]; then
            SIZE=$(echo "$line" | awk '{print $3 " " $4}')
            FILE_KEY=$(echo "$line" | awk '{print $5}')
            
            FULL_S3="s3://nextip-kamailio-logs/$FILE_KEY"
            
            S3_URLS+=("$FULL_S3")
            TAMANHOS+=("$SIZE")
        fi
    done <<< "$FOUND_RAW"
done

if [ ${#S3_URLS[@]} -eq 0 ]; then
    echo "❌ Nenhum arquivo encontrado."
    exit 1
fi

echo -e "\n--------------------------------------------------------------------------------"
echo "Arquivos encontrados:"
echo "--------------------------------------------------------------------------------"
for idx in "${!S3_URLS[@]}"; do
    printf "  [%2d] (%-9s) %s\n" "$((idx+1))" "${TAMANHOS[$idx]}" "${S3_URLS[$idx]}"
done
echo "  [ A] Baixar TODOS os arquivos listados"
echo "  [ Q] Sair"
echo "--------------------------------------------------------------------------------"

read -p "Digite os números desejados (ex: '1 9' ou '1-4' ou 'A'): " OPCAO

ARQUIVOS_SELECIONADOS=()

if [[ "$OPCAO" =~ ^[Aa]$ ]]; then
    ARQUIVOS_SELECIONADOS=("${S3_URLS[@]}")
elif [[ "$OPCAO" =~ ^[Qq]$ ]]; then
    echo "Saindo..."
    exit 0
else
    INDEXES=()
    for part in $OPCAO; do
        if [[ "$part" =~ ^[0-9]+-[0-9]+$ ]]; then
            START=$(echo "$part" | cut -d'-' -f1)
            END=$(echo "$part" | cut -d'-' -f2)
            for ((i=START; i<=END; i++)); do
                INDEXES+=("$i")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            INDEXES+=("$part")
        fi
    done

    for num in "${INDEXES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le "${#S3_URLS[@]}" ]; then
            ARQUIVOS_SELECIONADOS+=("${S3_URLS[$((num-1))]}")
        fi
    done
fi

if [ ${#ARQUIVOS_SELECIONADOS[@]} -eq 0 ]; then
    echo "❌ Nenhuma opção válida foi selecionada."
    exit 1
fi

BAIXADOS_PCAP=()

# Processo de Download, Renomeação (com IP do SBC) e Descompactação
for s3_file in "${ARQUIVOS_SELECIONADOS[@]}"; do
    SBC=$(echo "$s3_file" | awk -F'/' '{print $5}')
    ARQ_NAME=$(basename "$s3_file")
    
    DEST_GZ="$DEST_DIR/${SBC}_${ARQ_NAME}"
    
    echo "⬇️ Baixando $s3_file..."
    aws s3 cp "$s3_file" "$DEST_GZ"
    
    if [[ "$DEST_GZ" == *.gz ]]; then
        echo "📦 Descompactando $DEST_GZ..."
        gzip -df "$DEST_GZ"
        DEST_PCAP="${DEST_GZ%.gz}"
        BAIXADOS_PCAP+=("$DEST_PCAP")
    else
        BAIXADOS_PCAP+=("$DEST_GZ")
    fi
done

echo -e "\n✅ Download concluído em $DEST_DIR/"

FINAL_TARGETS=("${BAIXADOS_PCAP[@]}")

# Opção de Merge
if [ ${#BAIXADOS_PCAP[@]} -gt 1 ]; then
    read -p "Deseja Fazer MERGE de todos os PCAPs baixados em um único arquivo? (s/n): " DO_MERGE
    if [[ "$DO_MERGE" =~ ^[Ss]$ ]]; then
        MERGED_FILE="$DEST_DIR/merged_${DATA_NOMES}_${HORA_INPUT:-full}.pcap"
        echo "🔀 Executando mergecap em ${#BAIXADOS_PCAP[@]} arquivos..."
        
        mergecap -w "$MERGED_FILE" "${BAIXADOS_PCAP[@]}"
        
        if [ -f "$MERGED_FILE" ]; then
            echo "✅ Arquivo mesclado com sucesso: $MERGED_FILE"
            
            # Limpa os arquivos individuais deixando apenas o mergeado
            echo "🗑️ Removendo arquivos individuais descompactados..."
            for file_to_remove in "${BAIXADOS_PCAP[@]}"; do
                rm -f "$file_to_remove"
            done
            
            FINAL_TARGETS=("$MERGED_FILE")
        else
            echo "❌ Falha ao tentar mesclar arquivos. Mantendo arquivos originais."
        fi
    fi
fi

# Opção de abrir no sngrep
if [ ${#FINAL_TARGETS[@]} -gt 0 ]; then
    read -p "Deseja abrir no sngrep agora? (s/n): " ABRIR
    if [[ "$ABRIR" =~ ^[Ss]$ ]]; then
        sngrep -I "${FINAL_TARGETS[@]}"
    fi
fi
