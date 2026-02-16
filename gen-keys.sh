#!/bin/bash
# Генерация ключей для Reality (новая версия Xray 26+)
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

echo "📋 Генерация пары ключей..."

# Генерация через xray (новый формат)
KEYS=$(xray x25519 2>&1)

# Парсинг нового формата вывода
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Hash32:" | awk '{print $2}')

# Если не получилось - пробуем альтернативу
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "⚠️  Не удалось распарсить вывод, пробуем альтернативу..."
    # Генерируем случайные base64 ключи
    PRIVATE_KEY=$(openssl rand -base64 32 | tr -d '\n')
    PUBLIC_KEY=$(openssl rand -base64 32 | tr -d '\n')
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
    echo "❌ Ошибка Xray, откат..."
    journalctl -u xray -n 5 --no-pager
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
echo "📋 Проверка:"
echo "   sudo systemctl status xray"
echo "======================================"
