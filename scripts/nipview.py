import os
import paramiko
from dotenv import load_dotenv
import logging

# Configuração de logging
logging.basicConfig(filename="deploy.log", level=logging.INFO,
                    format="%(asctime)s - %(levelname)s - %(message)s")

# Carrega variáveis do .env
load_dotenv()
SSH_USER = os.getenv("SSH_USER")
SSH_KEY = os.getenv("SSH_KEY")
SSH_PORT = int(os.getenv("SSH_PORT", "22"))
IP_FILE = "ips.txt"

SAFE_MODE = False  # True = não executa rm -rf

# Identificação automática do pacote
PACKAGE = next((f for f in os.listdir(".") if f.startswith("nip-view-package_") and f.endswith(".tar.gz")), None)
if not PACKAGE:
    print("[-] Nenhum pacote encontrado.")
    exit(1)

RELEASE = PACKAGE.replace("nip-view-package_", "").replace(".tar.gz", "")
REMOTE_UPLOAD_DIR = "/hd/dev/nip-view"
REMOTE_EXTRACT_DIR = f"/hd/dev/nip-view-{RELEASE}"

def connect_ssh(ip):
    key = paramiko.RSAKey.from_private_key_file(SSH_KEY)
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(ip, port=SSH_PORT, username=SSH_USER, pkey=key, timeout=10)
    return client

with open(IP_FILE) as f:
    for ip in f:
        ip = ip.strip()
        if not ip:
            continue
        print(f"\n🚀 Processando {ip}")
        logging.info(f"Iniciando deploy em {ip}")
        try:
            ssh_client = connect_ssh(ip)
            
            # 1. Envia o arquivo via SFTP
            sftp = ssh_client.open_sftp()
            sftp.put(PACKAGE, f"/tmp/{PACKAGE}")
            sftp.close()

            cleanup_cmd = "echo '[SAFE MODE] Não removendo arquivos.'" if SAFE_MODE else f"rm -rf {REMOTE_UPLOAD_DIR} {REMOTE_EXTRACT_DIR}"

            # 2. Consolida o script Bash que vai rodar no Debian como root
            remote_bash_script = f"""set -e
mkdir -p {REMOTE_UPLOAD_DIR} {REMOTE_EXTRACT_DIR}
mv /tmp/{PACKAGE} {REMOTE_UPLOAD_DIR}/
tar --warning=no-unknown-keyword -xzf {REMOTE_UPLOAD_DIR}/{PACKAGE} -C {REMOTE_EXTRACT_DIR}/
cd {REMOTE_EXTRACT_DIR}
find . -type f -name "*.sh" -exec chmod +x {{}} +
./install.sh next $(pwd)
cd /
{cleanup_cmd}
"""

            # 3. Executa de forma síncrona com privilégios de root
            cmd_to_run = f"sudo bash -c '{remote_bash_script}'"
            stdin, stdout, stderr = ssh_client.exec_command(cmd_to_run)

            # 4. Exibe a saída do Debian em tempo real no seu Windows
            for line in iter(stdout.readline, ""):
                print(line, end="")
                logging.info(line.strip())

            # 5. Validação real de sucesso ou erro
            exit_status = stdout.channel.recv_exit_status()
            err_output = stderr.read().decode()

            if exit_status == 0:
                print(f"[+] Deploy concluído com SUCESSO em {ip}")
                logging.info(f"Deploy concluído em {ip}")
            else:
                print(f"[-] ERRO no deploy em {ip} (Código de saída: {exit_status})")
                if err_output:
                    print(f"Detalhe do erro:\n{err_output}")
                logging.error(f"Erro em {ip}: {err_output}")

            ssh_client.close()

        except Exception as e:
            print(f"[-] Falha ao conectar ou executar em {ip}: {e}")
            logging.error(f"Falha em {ip}: {e}")