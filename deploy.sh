#!/bin/bash
# VLESS Reality Server Deployment Script for Ubuntu 24.04
# Запуск: sudo bash deploy.sh

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
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Шаг 1: Обновление
echo -e "\n📋 Шаг 1: Обновление системы..."
apt update && apt upgrade -y
log_info "Система обновлена"

# Шаг 2: Установка зависимостей
echo -e "\n📦 Шаг 2: Установка зависимостей..."
apt install -y curl jq openssl
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

# Шаг 5: Генерация ключей (новый формат Xray 26+)
echo -e "\n🔑 Шаг 5: Генерация ключей..."
PORT=443
UUID=$(cat /proc/sys/kernel/random/uuid)

# Генерация ключей через xray (новый формат: PrivateKey, Hash32)
KEYS=$(xray x25519 2>&1)
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Hash32:" | awk '{print $2}')

# Fallback если не получилось
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    log_warn "Не удалось сгенерировать ключи через xray, используем openssl"
    PRIVATE_KEY=$(openssl rand -base64 32 | tr -d '\n')
    PUBLIC_KEY=$(openssl rand -base64 32 | tr -d '\n')
fi

SHORT_ID=$(openssl rand -hex 8)
SERVER_NAME="www.microsoft.com"

echo "   PORT: $PORT"
echo "   UUID: ${UUID:0:8}..."
echo "   PrivateKey: ${PRIVATE_KEY:0:16}..."
echo "   PublicKey: ${PUBLIC_KEY:0:16}..."
echo "   ShortId: $SHORT_ID"
echo "   ServerName: $SERVER_NAME"
log_info "Ключи сгенерированы"

# Шаг 6: Создание конфигурации
echo -e "\n⚙️  Шаг 6: Создание конфигурации..."
cat > /usr/local/etc/xray/config.json << EOF
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
          "publicKey": "$PUBLIC_KEY",
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
log_info "Конфигурация создана: /usr/local/etc/xray/config.json"

# Шаг 7: Настройка systemd
echo -e "\n⚙️  Шаг 7: Настройка systemd сервиса..."
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
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
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

# Шаг 8: Проверка статуса
echo -e "\n📊 Шаг 8: Проверка статуса..."
sleep 2
if systemctl is-active --quiet xray; then
    log_info "Xray запущен и работает"
else
    log_error "Ошибка запуска Xray"
    journalctl -u xray -n 10 --no-pager
    exit 1
fi

# Шаг 9: Сохранение конфигурации клиента
echo -e "\n💾 Шаг 9: Сохранение клиентской конфигурации..."
mkdir -p /etc/vless

# Получаем IP сервера (IPv4)
SERVER_IP=$(curl -4 -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -4 -s ipv4.me)
fi

# Проверка на IPv6
if echo "$SERVER_IP" | grep -q ":"; then
    SERVER_IP_BRACKETED="[$SERVER_IP]"
else
    SERVER_IP_BRACKETED="$SERVER_IP"
fi

cat > /etc/vless/server.json << EOF
{
  "address": "$SERVER_IP",
  "port": $PORT,
  "uuid": "$UUID",
  "serverName": "$SERVER_NAME",
  "shortId": "$SHORT_ID",
  "publicKey": "$PUBLIC_KEY"
}
EOF

# Генерация vless:// ссылки с publicKey
VLESS_LINK="vless://${UUID}@${SERVER_IP_BRACKETED}:${PORT}?encryption=none&security=reality&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-Reality"

echo ""
echo "=========================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "=========================================="
echo ""
echo "📱 Клиентская конфигурация:"
echo "----------------------------------------"
echo "vless:// ссылка:"
echo "$VLESS_LINK"
echo "----------------------------------------"
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

# Сохранение ссылки
echo "$VLESS_LINK" > /etc/vless/vless-link.txt
log_info "VLESS ссылка сохранена: /etc/vless/vless-link.txt"
