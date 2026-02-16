#!/bin/bash
# VLESS Reality Fix Script
# Исправление конфигурации Reality (проблема с сертификатом)
# Запуск: sudo bash fix-reality.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash fix-reality.sh"
    exit 1
fi

echo "🔧 Исправление конфигурации VLESS Reality"
echo "=========================================="

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Шаг 1: Остановка Xray
echo -e "\n📋 Шаг 1: Остановка Xray..."
systemctl stop xray
log_info "Xray остановлен"

# Шаг 2: Сохранение старого конфига (backup)
echo -e "\n💾 Шаг 2: Создание резервной копии..."
if [ -f /usr/local/etc/xray/config.json ]; then
    cp /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.backup
    log_info "Backup: /usr/local/etc/xray/config.json.backup"
fi

# Шаг 3: Генерация ключей
echo -e "\n🔑 Шаг 3: Генерация ключей X25519..."
KEYS=$(xray x25519 2>&1)
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Hash32:" | awk '{print $2}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    log_error "Не удалось сгенерировать ключи!"
    echo "Вывод xray x25519: $KEYS"
    exit 1
fi

log_info "Ключи сгенерированы"
echo "   Private: ${PRIVATE_KEY:0:20}..."
echo "   Public:  ${PUBLIC_KEY:0:20}..."

# Шаг 4: Генерация UUID и ShortId
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(openssl rand -hex 8)
PORT=443
SNI="yahoo.com"
DEST="yahoo.com:443"

echo ""
echo "   UUID: $UUID"
echo "   ShortId: $SHORT_ID"
echo "   SNI: $SNI"
echo "   Dest: $DEST"

# Шаг 5: Создание конфигурации
echo -e "\n⚙️  Шаг 5: Создание конфигурации..."
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
          "dest": "$DEST",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "publicKey": "$PUBLIC_KEY",
          "minClientVer": "",
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
log_info "Конфигурация создана"

# Шаг 6: Запуск Xray
echo -e "\n🔄 Шаг 6: Запуск Xray..."
systemctl daemon-reload
systemctl enable xray
systemctl start xray
sleep 2

if systemctl is-active --quiet xray; then
    log_info "Xray запущен"
else
    log_error "Ошибка запуска Xray"
    journalctl -u xray -n 10 --no-pager
    exit 1
fi

# Шаг 7: Получение IP сервера
SERVER_IP=$(curl -4 -s ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -4 -s ipv4.me)
fi

# Шаг 8: Генерация ссылки
VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#VLESS-Fixed"

# Шаг 9: Сохранение конфигурации
echo -e "\n💾 Шаг 9: Сохранение данных..."
mkdir -p /etc/vless

cat > /etc/vless/server.json << EOF
{
  "address": "$SERVER_IP",
  "port": $PORT,
  "uuid": "$UUID",
  "serverName": "$SNI",
  "publicKey": "$PUBLIC_KEY",
  "shortId": "$SHORT_ID",
  "dest": "$DEST"
}
EOF

echo "$VLESS_LINK" > /etc/vless/vless-link-fixed.txt

# Итог
echo ""
echo "=========================================="
echo "✅ ГОТОВО! Конфигурация исправлена"
echo "=========================================="
echo ""
echo "📱 VLESS ссылка (скопируйте в клиент):"
echo "----------------------------------------"
echo "$VLESS_LINK"
echo "----------------------------------------"
echo ""
echo "📄 Параметры подключения:"
echo "   IP:        $SERVER_IP"
echo "   Port:      $PORT"
echo "   UUID:      $UUID"
echo "   SNI:       $SNI"
echo "   PublicKey: $PUBLIC_KEY"
echo "   ShortId:   $SHORT_ID"
echo "   Flow:      xtls-rprx-vision"
echo ""
echo "🔧 В v2rayNG настройте:"
echo "   - Security: reality"
echo "   - SNI: $SNI"
echo "   - Fingerprint: chrome"
echo "   - Flow: xtls-rprx-vision"
echo ""
echo "📋 Файлы:"
echo "   /etc/vless/vless-link-fixed.txt - ссылка"
echo "   /etc/vless/server.json - параметры"
echo "=========================================="
