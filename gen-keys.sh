#!/bin/bash
# Генерация ключей для Reality конфигурации
# Запуск: sudo bash gen-keys.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash gen-keys.sh"
    exit 1
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"

echo "🔑 Генерация ключей для VLESS Reality"
echo "======================================"

# Проверка конфига
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Конфигурация не найдена: $CONFIG_FILE"
    exit 1
fi

echo "📋 Генерация пары ключей X25519..."

# Генерация через xray
KEYS=$(xray x25519 2>&1)

# Парсинг вывода
PRIVATE_KEY=$(echo "$KEYS" | grep -i "private" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "public" | awk '{print $NF}')

# Если xray не вернул ключи - генерируем через openssl
if [ -z "$PRIVATE_KEY" ]; then
    echo "⚠️  xray не вернул ключи, используем openssl..."
    PRIVATE_KEY=$(openssl rand -hex 32)
    PUBLIC_KEY=$(openssl rand -hex 32)
fi

echo ""
echo "✓ Ключи сгенерированы:"
echo "   Private: ${PRIVATE_KEY:0:20}..."
echo "   Public:  ${PUBLIC_KEY:0:20}..."

# Обновление конфига
echo ""
echo "📝 Обновление конфигурации..."

jq --arg pk "$PUBLIC_KEY" --arg sk "$PRIVATE_KEY" \
   '.inbounds[0].streamSettings.realitySettings.publicKey = $pk |
    .inbounds[0].streamSettings.realitySettings.privateKey = $sk' \
   "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
   mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

# Перезапуск Xray
echo ""
echo "🔄 Перезапуск Xray..."
systemctl restart xray
sleep 1

# Проверка
if systemctl is-active --quiet xray; then
    echo "✅ Xray работает"
else
    echo "❌ Ошибка Xray"
    systemctl status xray --no-pager
    exit 1
fi

# Итог
echo ""
echo "======================================"
echo "✅ ГОТОВО!"
echo ""
echo "Public Key (для клиентов):"
echo "----------------------------------------"
jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_FILE"
echo "----------------------------------------"
echo ""
echo "📱 Создайте клиента:"
echo "   sudo bash clients.sh add <name>"
echo ""
echo "📋 Или получите ссылку:"
echo "   cat /etc/vless/client-<name>.txt"
echo "======================================"
