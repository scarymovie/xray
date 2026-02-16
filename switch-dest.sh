#!/bin/bash
# VLESS Reality Dest Switcher
# Переключение dest домена для Reality
# Запуск: sudo bash switch-dest.sh <номер>
#
# Доступные домены:
#   1 - yahoo.com (по умолчанию)
#   2 - www.wikipedia.org
#   3 - www.amazon.com
#   4 - www.cloudflare.com
#   5 - www.apple.com
#   6 - www.microsoft.com
#   7 - www.google.com
#   8 - www.akamai.com
#   9 - www.fastly.com
#   10 - cdn.cloudflare.com

set -e

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash switch-dest.sh <номер>"
    exit 1
fi

# Список доменов
declare -A DESTS=(
    [1]="yahoo.com"
    [2]="www.wikipedia.org"
    [3]="www.amazon.com"
    [4]="www.cloudflare.com"
    [5]="www.apple.com"
    [6]="www.microsoft.com"
    [7]="www.google.com"
    [8]="www.akamai.com"
    [9]="www.fastly.com"
    [10]="cdn.cloudflare.com"
)

# Показать список если нет аргумента
if [ -z "$1" ]; then
    echo "📋 Доступные dest домены:"
    echo "================================"
    for key in "${!DESTS[@]}"; do
        echo "   $key - ${DESTS[$key]}"
    done
    echo "================================"
    echo ""
    echo "Использование: sudo bash switch-dest.sh <номер>"
    echo "Пример: sudo bash switch-dest.sh 2"
    exit 0
fi

# Проверка номера
if [ -z "${DESTS[$1]}" ]; then
    echo "❌ Неверный номер: $1"
    echo "Допустимые значения: 1-10"
    echo ""
    echo "Запустите без аргумента для просмотра списка"
    exit 1
fi

DEST="${DESTS[$1]}"
SNI="$DEST"
CONFIG_FILE="/usr/local/etc/xray/config.json"

echo "🔄 Переключение Reality dest"
echo "================================"
echo "Выбрано: $DEST (номер: $1)"

# Проверка конфига
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Конфигурация не найдена: $CONFIG_FILE"
    exit 1
fi

# Обновление конфига
echo ""
echo "📝 Обновление конфигурации..."
jq --arg dest "$DEST:443" --arg sni "$SNI" \
   '.inbounds[0].streamSettings.realitySettings.dest = $dest |
    .inbounds[0].streamSettings.realitySettings.serverNames = [$sni]' \
   "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
   mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

# Перезапуск Xray
echo ""
echo "🔄 Перезапуск Xray..."
systemctl restart xray
sleep 2

# Проверка
if systemctl is-active --quiet xray; then
    echo "✅ Xray перезапущен"
else
    echo "❌ Ошибка запуска Xray"
    systemctl status xray --no-pager
    exit 1
fi

# Показать текущие настройки
echo ""
echo "================================"
echo "✅ Готово!"
echo ""
echo "Текущие настройки:"
echo "   Dest: $DEST:443"
echo "   SNI:  $SNI"
echo ""
echo "📱 Обновите ссылку клиента:"
echo "   Измените sni=$SNI в vless:// ссылке"
echo "================================"

# Сохранение текущего dest
echo "$DEST" > /etc/vless/current-dest.txt
