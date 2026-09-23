#!/bin/bash

# Verifica se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
   echo "Este script precisa ser executado como root. Tente rodar com: sudo $0"
   exit 1
fi

echo "=> Fazendo backup do sources.list atual..."
mv /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F)

echo "=> Configurando repositórios do Debian Buster (archive)..."
echo "deb [check-valid-until=no] http://archive.debian.org/debian buster main contrib non-free" > /etc/apt/sources.list
echo "deb [check-valid-until=no] http://archive.debian.org/debian-security buster/updates main contrib non-free" >> /etc/apt/sources.list

echo "=> Atualizando índices do apt (ignorando valid-until)..."
apt-get -o Acquire::Check-Valid-Until=false update

echo "=> Importando chaves GPG do MySQL..."
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C || true
wget -qO- https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 | apt-key add - || true
wget -qO- https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | apt-key add - || true

echo "=> Atualizando índices novamente com as novas chaves..."
apt-get -o Acquire::Check-Valid-Until=false update
apt-get update

echo "=> Instalando sngrep e htop..."
apt install sngrep htop -y

echo "=> Script finalizado com sucesso!"
