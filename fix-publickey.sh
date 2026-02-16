#!/bin/bash
# Исправление конфигурации Reality (добавление publicKey)

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash fix-publickey.sh"
    exit 1
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"

echo "🔑 Проверка конфигурации Reality..."

# Проверка наличия publicKey
if jq -e '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_FILE" > /dev/null 2>&1; then
    echo "✅ publicKey уже есть в конфигурации"
    jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_FILE"
else
    echo "⚠️  publicKey отсутствует, генерируем..."
    
    # Генерация ключей
    KEYS=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    
    echo "   Private: $PRIVATE_KEY"
    echo "   Public:  $PUBLIC_KEY"
    
    # Обновление конфига
    jq --arg pk "$PUBLIC_KEY" --arg sk "$PRIVATE_KEY" \
       '.inbounds[0].streamSettings.realitySettings.publicKey = $pk |
        .inbounds[0].streamSettings.realitySettings.privateKey = $sk' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    echo "✅ publicKey добавлен в конфигурацию"
    
    # Перезапуск Xray
    systemctl restart xray
    echo "✅ Xray перезапущен"
fi

echo ""
echo "📱 Публичный ключ для клиента:"
jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_FILE"
