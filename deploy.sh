#!/bin/bash
# VLESS Reality Server Deployment Script for Ubuntu 24.04
# Запуск: bash deploy.sh

set -e

echo "🚀 VLESS Reality Server Deployment"
echo "=================================="

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash deploy.sh"
    exit 1
fi

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Шаг 1: Обновление
echo -e "\n📋 Шаг 1: Обновление системы..."
apt update && apt upgrade -y
log_info "Система обновлена"

# Шаг 2: Установка зависимостей
echo -e "\n📦 Шаг 2: Установка зависимостей..."
apt install -y golang-go curl unzip jq
log_info "Зависимости установлены"

# Шаг 3: Открытие портов
echo -e "\n🔓 Шаг 3: Настройка firewall..."
if ! command -v ufw &> /dev/null; then
    apt install -y ufw
fi

ufw allow 22/tcp
ufw allow 443/tcp
ufw --force enable
log_info "Порты 22 и 443 открыты"

# Шаг 4: Установка Xray-core
echo -e "\n📦 Шаг 4: Установка Xray-core..."
if command -v xray &> /dev/null; then
    log_warn "Xray уже установлен, пропускаем"
else
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    log_info "Xray-core установлен"
fi

xray version

# Шаг 5: Создание директории
echo -e "\n📁 Шаг 5: Создание директории конфигурации..."
mkdir -p /etc/vless
log_info "Директория /etc/vless создана"

# Шаг 6: Генерация ключей
echo -e "\n🔑 Шаг 6: Генерация ключей..."
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)
PRIVATE_KEY=$(xray x25519 | grep "Private key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)
SERVER_NAME="www.microsoft.com"

if [ -z "$PRIVATE_KEY" ]; then
    # Fallback если xray x25519 не сработал
    PRIVATE_KEY=$(openssl rand -hex 32)
fi

echo "   PORT: $PORT"
echo "   UUID: $UUID"
echo "   PrivateKey: $PRIVATE_KEY"
echo "   ShortId: $SHORT_ID"
echo "   ServerName: $SERVER_NAME"
log_info "Ключи сгенерированы"

# Шаг 7: Создание конфигурации
echo -e "\n⚙️  Шаг 7: Создание конфигурации..."
cat > /etc/vless/config.json << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SERVER_NAME:443",
          "xver": 0,
          "serverNames": ["$SERVER_NAME", "www.apple.com"],
          "privateKey": "$PRIVATE_KEY",
          "minClientVer": "1.8.0",
          "maxClientVer": "",
          "maxTimeDiff": 86400000,
          "shortIds": ["$SHORT_ID", ""]
        },
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
log_info "Конфигурация создана: /etc/vless/config.json"

# Шаг 8: Настройка systemd
echo -e "\n⚙️  Шаг 8: Настройка systemd сервиса..."
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -c /etc/vless/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl start xray
log_info "Systemd сервис настроен"

# Шаг 9: Проверка статуса
echo -e "\n📊 Шаг 9: Проверка статуса..."
sleep 2
systemctl status xray --no-pager

# Шаг 10: Сохранение конфигурации клиента
echo -e "\n💾 Шаг 10: Сохранение клиентской конфигурации..."
SERVER_IP=$(curl -s ifconfig.me)

cat > /etc/vless/server.json << EOF
{
  "address": "$SERVER_IP",
  "port": $PORT,
  "uuid": "$UUID",
  "serverName": "$SERVER_NAME",
  "shortId": "$SHORT_ID",
  "privateKey": "$PRIVATE_KEY"
}
EOF

# Генерация vless:// ссылки
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SERVER_NAME}&fp=chrome&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality"

echo ""
echo "=========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "=========================================="
echo ""
echo "📱 Клиентская конфигурация:"
echo "----------------------------------------"
echo "vless:// ссылка:"
echo "$VLESS_LINK"
echo ""
echo "📄 Файл конфигурации: /etc/vless/server.json"
echo ""
echo "🔧 Команды управления:"
echo "   systemctl status xray    - статус"
echo "   systemctl restart xray   - перезапуск"
echo "   journalctl -u xray -f    - логи"
echo ""
echo "📋 Для просмотра конфигурации:"
echo "   cat /etc/vless/server.json"
echo "=========================================="

# Сохранение vless ссылки в файл
echo "$VLESS_LINK" > /etc/vless/vless-link.txt
log_info "VLESS ссылка сохранена в /etc/vless/vless-link.txt"
