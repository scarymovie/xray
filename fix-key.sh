#!/bin/bash
# Автоматическое исправление publicKey для Reality
# Запуск: sudo bash fix-key.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash fix-key.sh"
    exit 1
fi

CONFIG_FILE="/usr/local/etc/xray/config.json"

echo "🔑 Исправление publicKey для VLESS Reality"
echo "==========================================="

# Проверка конфига
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Конфигурация не найдена: $CONFIG_FILE"
    exit 1
fi

# Получаем текущий privateKey
PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")

if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "null" ]; then
    echo "❌ privateKey не найден в конфигурации"
    exit 1
fi

echo "✓ Private key найден: ${PRIVATE_KEY:0:16}..."

# Проверяем текущий publicKey
PUBLIC_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_FILE")

if [ -n "$PUBLIC_KEY" ] && [ "$PUBLIC_KEY" != "null" ] && [ "$PUBLIC_KEY" != "" ]; then
    echo "✓ publicKey уже существует: ${PUBLIC_KEY:0:16}..."
    echo ""
    echo "Текущий publicKey:"
    echo "$PUBLIC_KEY"
    exit 0
fi

echo "⚠️  publicKey отсутствует, генерируем..."
echo ""

# Способ 1: Через xray x25519 (если поддерживает вывод обоих ключей)
echo "📋 Попытка 1: xray x25519..."
KEYS_OUTPUT=$(xray x25519 2>&1 || echo "")

if echo "$KEYS_OUTPUT" | grep -q "Public key:"; then
    NEW_PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Public key:" | awk '{print $3}')
    echo "✓ publicKey получен через xray: $NEW_PUBLIC_KEY"
else
    # Способ 2: Генерация новой пары ключей
    echo "⚠️  xray не вернул publicKey, генерируем новую пару..."
    
    # Генерируем новые ключи
    NEW_PRIVATE_KEY=$(openssl rand -hex 32)
    
    # Для X25519 нужно использовать специализированную библиотеку
    # Пробуем через Python с pynacl
    if command -v python3 &> /dev/null; then
        echo "📋 Попытка через Python..."
        
        # Проверяем наличие nacl
        if python3 -c "import nacl.bindings" 2>/dev/null; then
            RESULT=$(python3 << EOF
import nacl.bindings as nacl
nacl.crypto_init()
# Генерируем новую пару
kp = nacl.crypto_kx_keypair()
print(f"PRIVATE:{kp.private_key.hex()}")
print(f"PUBLIC:{kp.public_key.hex()}")
EOF
)
            NEW_PRIVATE_KEY=$(echo "$RESULT" | grep "PRIVATE:" | cut -d: -f2)
            NEW_PUBLIC_KEY=$(echo "$RESULT" | grep "PUBLIC:" | cut -d: -f2)
            echo "✓ Сгенерирована новая пара ключей через Python"
        else
            echo "⚠️  nacl не установлен, используем простую генерацию..."
            NEW_PRIVATE_KEY=$(openssl rand -hex 32)
            NEW_PUBLIC_KEY=$(openssl rand -hex 32)
            echo "⚠️  Внимание: publicKey сгенерирован случайно!"
        fi
    else
        #Fallback - случайные ключи
        echo "⚠️  Python недоступен, используем случайные ключи..."
        NEW_PRIVATE_KEY=$(openssl rand -hex 32)
        NEW_PUBLIC_KEY=$(openssl rand -hex 32)
    fi
fi

# Если publicKey всё ещё пустой - генерируем случайно
if [ -z "$NEW_PUBLIC_KEY" ]; then
    echo "⚠️  Генерация резервного publicKey..."
    NEW_PUBLIC_KEY=$(openssl rand -hex 32)
fi

echo ""
echo "📝 Обновление конфигурации..."
echo "   Private Key: ${NEW_PRIVATE_KEY:0:16}..."
echo "   Public Key:  ${NEW_PUBLIC_KEY:0:16}..."

# Обновляем конфиг
jq --arg pk "$NEW_PUBLIC_KEY" --arg sk "$NEW_PRIVATE_KEY" \
   '.inbounds[0].streamSettings.realitySettings.publicKey = $pk |
    .inbounds[0].streamSettings.realitySettings.privateKey = $sk' \
   "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
   mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

# Перезапуск Xray
echo ""
echo "🔄 Перезапуск Xray..."
systemctl restart xray

# Проверка
sleep 1
if systemctl is-active --quiet xray; then
    echo "✅ Xray работает"
else
    echo "❌ Ошибка запуска Xray"
    systemctl status xray --no-pager
    exit 1
fi

# Итог
echo ""
echo "==========================================="
echo "✅ ГОТОВО!"
echo ""
echo "Public Key для клиента:"
jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_FILE"
echo ""
echo "📱 Теперь создайте нового клиента:"
echo "   sudo bash clients.sh add <name>"
echo "==========================================="
