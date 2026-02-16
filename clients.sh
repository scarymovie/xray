#!/bin/bash
# VLESS Client Management Script
# Добавление, удаление и просмотр клиентов
# Запуск: sudo bash clients.sh <command> [args]

set -e

CONFIG_FILE="/etc/vless/config.json"
SERVER_FILE="/etc/vless/server.json"
CLIENTS_FILE="/etc/vless/clients.json"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_section() { echo -e "\n${BLUE}═══${NC} ${YELLOW}$1${NC} ${BLUE}═══${NC}"; }

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash clients.sh <command>"
    exit 1
fi

# Проверка наличия jq
if ! command -v jq &> /dev/null; then
    echo "📦 Установка jq..."
    apt install -y jq
fi

# Проверка конфигурации
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Конфигурация не найдена: $CONFIG_FILE"
    echo "Запустите сначала установку: sudo bash deploy.sh"
    exit 1
fi

# Инициализация файла клиентов
if [ ! -f "$CLIENTS_FILE" ]; then
    echo '[]' > "$CLIENTS_FILE"
fi

# Получить базовые параметры
get_server_params() {
    # Принудительно получаем IPv4 (он надёжнее для VPN)
    SERVER_IP=$(curl -4 -s ifconfig.me)
    
    # Если не получилось, пробуем альтернативу
    if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "" ]; then
        SERVER_IP=$(curl -4 -s ipv4.me)
    fi
    
    PORT=$(jq -r '.inbounds[0].port' "$CONFIG_FILE")
    SERVER_NAME=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_FILE")
    PRIVATE_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    
    # Проверка на IPv6 - если есть двоеточия, берём в скобки
    if echo "$SERVER_IP" | grep -q ":"; then
        SERVER_IP="[$SERVER_IP]"
    fi
}

# Генерация UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# Добавление клиента
add_client() {
    local name="$1"
    
    if [ -z "$name" ]; then
        log_error "Укажите имя клиента: sudo bash clients.sh add <name>"
        echo "Пример: sudo bash clients.sh add iphone"
        exit 1
    fi
    
    # Проверка на дубликат
    if jq -e ".[] | select(.name == \"$name\")" "$CLIENTS_FILE" > /dev/null 2>&1; then
        log_error "Клиент с именем '$name' уже существует"
        exit 1
    fi
    
    get_server_params
    UUID=$(generate_uuid)
    CREATED=$(date +%Y-%m-%d_%H:%M:%S)
    
    # Добавление в файл клиентов
    jq --arg name "$name" \
       --arg uuid "$UUID" \
       --arg created "$CREATED" \
       '. += [{"name": $name, "uuid": $uuid, "created": $created, "enabled": true}]' \
       "$CLIENTS_FILE" > "${CLIENTS_FILE}.tmp" && mv "${CLIENTS_FILE}.tmp" "$CLIENTS_FILE"
    
    # Добавление в конфигурацию Xray
    jq --arg uuid "$UUID" \
       '.inbounds[0].settings.clients += [{"id": $uuid, "flow": "xtls-rprx-vision"}]' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Перезапуск Xray
    systemctl restart xray
    
    # Генерация ссылки
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SERVER_NAME}&fp=chrome&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-${name}"
    
    log_section "Клиент добавлен"
    echo "Имя: $name"
    echo "UUID: $UUID"
    echo "Создан: $CREATED"
    echo ""
    echo "📱 VLESS ссылка:"
    echo "----------------------------------------"
    echo "$VLESS_LINK"
    echo "----------------------------------------"
    echo ""
    
    # Сохранение ссылки в файл
    echo "$VLESS_LINK" > "/etc/vless/client-${name}.txt"
    log_info "Ссылка сохранена: /etc/vless/client-${name}.txt"
    
    # QR код (если установлен qrencode)
    if command -v qrencode &> /dev/null; then
        echo ""
        echo "📷 QR код:"
        qrencode -t ANSIUTF8 "$VLESS_LINK"
    fi
}

# Удаление клиента
remove_client() {
    local name="$1"
    
    if [ -z "$name" ]; then
        log_error "Укажите имя клиента: sudo bash clients.sh remove <name>"
        exit 1
    fi
    
    # Проверка существования
    if ! jq -e ".[] | select(.name == \"$name\")" "$CLIENTS_FILE" > /dev/null 2>&1; then
        log_error "Клиент '$name' не найден"
        echo "Доступные клиенты:"
        list_clients
        exit 1
    fi
    
    UUID=$(jq -r ".[] | select(.name == \"$name\") | .uuid" "$CLIENTS_FILE")
    
    # Удаление из файла клиентов
    jq "del(.[] | select(.name == \"$name\"))" "$CLIENTS_FILE" > "${CLIENTS_FILE}.tmp" && mv "${CLIENTS_FILE}.tmp" "$CLIENTS_FILE"
    
    # Удаление из конфигурации Xray
    jq --arg uuid "$UUID" \
       '.inbounds[0].settings.clients = [.inbounds[0].settings.clients[] | select(.id != $uuid)]' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Перезапуск Xray
    systemctl restart xray
    
    # Удаление файла ссылки
    rm -f "/etc/vless/client-${name}.txt"
    
    log_info "Клиент '$name' удалён"
}

# Список клиентов
list_clients() {
    get_server_params
    
    echo ""
    printf "${BLUE}%-20s %-36s %-10s %s${NC}\n" "ИМЯ" "UUID" "СТАТУС" "СОЗДАН"
    echo "--------------------------------------------------------------------------------"
    
    jq -r '.[] | "\(.name | .[0:18]) \(.uuid) \(.enabled | if . then "✅" else "❌" end) \(.created)"' "$CLIENTS_FILE"
    
    echo ""
    echo "Всего клиентов: $(jq 'length' "$CLIENTS_FILE")"
    echo ""
}

# Показать конфигурацию клиента
show_client() {
    local name="$1"
    
    if [ -z "$name" ]; then
        log_error "Укажите имя клиента: sudo bash clients.sh show <name>"
        exit 1
    fi
    
    if ! jq -e ".[] | select(.name == \"$name\")" "$CLIENTS_FILE" > /dev/null 2>&1; then
        log_error "Клиент '$name' не найден"
        exit 1
    fi
    
    get_server_params
    UUID=$(jq -r ".[] | select(.name == \"$name\") | .uuid" "$CLIENTS_FILE")
    
    VLESS_LINK="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&sni=${SERVER_NAME}&fp=chrome&sid=${SHORT_ID}&type=tcp&headerType=none#VLESS-${name}"
    
    log_section "Клиент: $name"
    echo "UUID: $UUID"
    echo ""
    echo "📱 VLESS ссылка:"
    echo "----------------------------------------"
    echo "$VLESS_LINK"
    echo "----------------------------------------"
    
    # JSON конфигурация для импорта
    echo ""
    echo "📄 JSON для импорта:"
    echo "----------------------------------------"
    cat << EOF
{
  "remarks": "VLESS-${name}",
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER_IP}",
            "port": ${PORT},
            "users": [
              {
                "id": "${UUID}",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "${SERVER_NAME}",
          "fingerprint": "chrome",
          "shortId": "${SHORT_ID}"
        }
      }
    }
  ]
}
EOF
    echo "----------------------------------------"
}

# Включить/выключить клиента
toggle_client() {
    local name="$1"
    local action="$2"
    
    if [ -z "$name" ]; then
        log_error "Укажите имя клиента: sudo bash clients.sh toggle <name> [on|off]"
        exit 1
    fi
    
    if ! jq -e ".[] | select(.name == \"$name\")" "$CLIENTS_FILE" > /dev/null 2>&1; then
        log_error "Клиент '$name' не найден"
        exit 1
    fi
    
    if [ "$action" = "off" ]; then
        jq "(.[] | select(.name == \"$name\") | .enabled) = false" "$CLIENTS_FILE" > "${CLIENTS_FILE}.tmp" && mv "${CLIENTS_FILE}.tmp" "$CLIENTS_FILE"
        log_info "Клиент '$name' выключен"
    else
        jq "(.[] | select(.name == \"$name\") | .enabled) = true" "$CLIENTS_FILE" > "${CLIENTS_FILE}.tmp" && mv "${CLIENTS_FILE}.tmp" "$CLIENTS_FILE"
        log_info "Клиент '$name' включен"
    fi
}

# Экспорт всех клиентов
export_clients() {
    get_server_params
    
    echo "{"
    echo "  \"server\": {"
    echo "    \"address\": \"${SERVER_IP}\","
    echo "    \"port\": ${PORT},"
    echo "    \"serverName\": \"${SERVER_NAME}\","
    echo "    \"shortId\": \"${SHORT_ID}\""
    echo "  },"
    echo "  \"clients\": $(cat "$CLIENTS_FILE")"
    echo "}"
}

# Помощь
print_help() {
    echo ""
    echo "📋 VLESS Client Manager"
    echo ""
    echo "Использование: sudo bash clients.sh <command> [args]"
    echo ""
    echo "Команды:"
    echo "  add <name>       Добавить нового клиента"
    echo "  remove <name>    Удалить клиента"
    echo "  list             Показать список клиентов"
    echo "  show <name>      Показать конфигурацию клиента"
    echo "  enable <name>    Включить клиента"
    echo "  disable <name>   Выключить клиента"
    echo "  export           Экспорт всех клиентов (JSON)"
    echo "  help             Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  sudo bash clients.sh add iphone"
    echo "  sudo bash clients.sh add android"
    echo "  sudo bash clients.sh list"
    echo "  sudo bash clients.sh show iphone"
    echo "  sudo bash clients.sh remove iphone"
    echo "  sudo bash clients.sh disable iphone"
    echo "  sudo bash clients.sh enable iphone"
    echo ""
}

# Основная логика
case "${1:-help}" in
    add)
        add_client "$2"
        ;;
    remove|rm)
        remove_client "$2"
        ;;
    list|ls)
        list_clients
        ;;
    show)
        show_client "$2"
        ;;
    enable)
        toggle_client "$2" "on"
        ;;
    disable)
        toggle_client "$2" "off"
        ;;
    export)
        export_clients
        ;;
    help|--help|-h)
        print_help
        ;;
    *)
        log_error "Неизвестная команда: $1"
        print_help
        exit 1
        ;;
esac
