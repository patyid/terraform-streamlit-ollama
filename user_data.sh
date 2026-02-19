#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log) 2>&1
echo "==== STARTED: $(date -Is) ===="

# ============================================
# 1. SSM AGENT
# ============================================
if snap list amazon-ssm-agent &>/dev/null; then
    snap start amazon-ssm-agent 2>/dev/null || true
elif ! systemctl is-active --quiet amazon-ssm-agent 2>/dev/null; then
    apt-get update -y && apt-get install -y snapd
    snap install amazon-ssm-agent --classic
    snap start amazon-ssm-agent
fi

# ============================================
# 2. VARIAVEIS
# ============================================
APP_REPO="${app_git_repo}"
APP_BRANCH="${app_git_branch}"
APP_NAME="${app_dir_name}"
ENTRY_POINT="${streamlit_entry}"
MODEL_NAME="${ollama_model}"

APP_BASE="/opt/app"
CLONE_PATH="$APP_BASE/$APP_NAME"
VENV_PATH="$APP_BASE/venv"
DATA_PATH="/var/lib/ollama-data"

# ============================================
# 3. PACOTES (COM SQLITE3)
# ============================================
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget git nvme-cli python3 python3-venv build-essential net-tools sqlite3

# ============================================
# 4. DISK SETUP
# ============================================
mkdir -p "$DATA_PATH"

ROOT_DEV="$(findmnt -n -o SOURCE / | sed 's/p[0-9]*$//')"
DATA_DEV=""

for dev in $(ls /dev/nvme*n1 2>/dev/null); do
    if [ "$(basename "$dev")" != "$(basename "$ROOT_DEV")" ]; then
        DATA_DEV="$dev"
        break
    fi
done

if [ -n "$DATA_DEV" ] && [ -b "$DATA_DEV" ]; then
    if ! blkid "$DATA_DEV" >/dev/null 2>&1; then
        mkfs.ext4 -F "$DATA_DEV"
    fi
    mount "$DATA_DEV" "$DATA_PATH" 2>/dev/null || true
    grep -q "$DATA_PATH" /etc/fstab || echo "$DATA_DEV $DATA_PATH ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# ============================================
# 5. OLLAMA (PERMISSOES CORRETAS)
# ============================================
curl -fsSL https://ollama.com/install.sh | sh

# Cria diretorios com dono correto ANTES de iniciar
mkdir -p "$DATA_PATH/.ollama"
mkdir -p "$DATA_PATH/ollama"
chown -R ollama:ollama "$DATA_PATH/.ollama"
chown -R ollama:ollama "$DATA_PATH/ollama"
chmod 755 "$DATA_PATH"

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<'OVR'
[Service]
Environment="OLLAMA_MODELS=/var/lib/ollama-data/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Restart=always
RestartSec=5
OVR

systemctl daemon-reload
systemctl restart ollama

for i in $(seq 1 60); do
    curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 2
done

sudo -u ollama OLLAMA_MODELS="$DATA_PATH/ollama" ollama pull "$MODEL_NAME" || true

# ============================================
# 6. APLICACAO
# ============================================
mkdir -p "$APP_BASE"

if [ -d "$CLONE_PATH/.git" ]; then
    cd "$CLONE_PATH" && git pull origin "$APP_BRANCH"
else
    git clone --branch "$APP_BRANCH" "$APP_REPO" "$CLONE_PATH"
fi

FOUND_FILE=$(find "$CLONE_PATH" -name "$ENTRY_POINT" -type f | head -n 1)
[ -z "$FOUND_FILE" ] && { echo "Entry point nao encontrado!"; exit 1; }

WORK_DIR=$(dirname "$FOUND_FILE")

python3 -m venv "$VENV_PATH"
"$VENV_PATH/bin/pip" install --upgrade pip setuptools wheel

if [ -f "$WORK_DIR/requirements.txt" ]; then
    "$VENV_PATH/bin/pip" install -r "$WORK_DIR/requirements.txt"
else
    "$VENV_PATH/bin/pip" install streamlit langchain langchain-ollama langchain-community python-dotenv
fi

# ============================================
# 7. PERMISSOES (CORRECAO CRITICA)
# ============================================

# Aplicacao: ubuntu
chown -R ubuntu:ubuntu "$APP_BASE"

# Diretorio de dados: ubuntu (para o SQLite funcionar)
chown ubuntu:ubuntu "$DATA_PATH"
chmod 755 "$DATA_PATH"

# Banco de dados: cria como ubuntu com sqlite3
sudo -u ubuntu bash -c "sqlite3 '$DATA_PATH/chat_history.db' 'CREATE TABLE IF NOT EXISTS message_store (id INTEGER PRIMARY KEY, session_id TEXT, message TEXT);'"
chmod 644 "$DATA_PATH/chat_history.db"

# Ollama mantem suas pastas
chown -R ollama:ollama "$DATA_PATH/.ollama"
chown -R ollama:ollama "$DATA_PATH/ollama"

# ============================================
# 8. STREAMLIT SERVICE
# ============================================
cat > /etc/systemd/system/streamlit.service <<'SERVICE'
[Unit]
Description=Streamlit Application
After=network.target ollama.service
Requires=ollama.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=WORKDIR_PLACEHOLDER
Environment=PYTHONUNBUFFERED=1
Environment=HOME=/home/ubuntu
Environment=PATH=VENV_PLACEHOLDER/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=CHAT_HISTORY_DB=/var/lib/ollama-data/chat_history.db
Environment=OLLAMA_BASE_URL=http://127.0.0.1:11434
Environment=OLLAMA_MODEL=MODEL_PLACEHOLDER
ExecStartPre=/bin/sh -c 'until curl -sf http://127.0.0.1:11434/api/tags; do sleep 2; done'
ExecStart=VENV_PLACEHOLDER/bin/streamlit run ENTRY_PLACEHOLDER --server.port 8501 --server.address 0.0.0.0
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

sed -i "s|WORKDIR_PLACEHOLDER|$WORK_DIR|g" /etc/systemd/system/streamlit.service
sed -i "s|VENV_PLACEHOLDER|$VENV_PATH|g" /etc/systemd/system/streamlit.service
sed -i "s|ENTRY_PLACEHOLDER|$FOUND_FILE|g" /etc/systemd/system/streamlit.service
sed -i "s|MODEL_PLACEHOLDER|$MODEL_NAME|g" /etc/systemd/system/streamlit.service

systemctl daemon-reload
systemctl enable streamlit
systemctl restart streamlit

echo "==== COMPLETED: $(date -Is) ===="
touch /var/lib/cloud/instance/sem/userdata.ok