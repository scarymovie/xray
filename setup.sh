#!/bin/bash
# Quick setup script for Ubuntu 24.04
# Запуск: bash setup.sh

set -e

echo "🚀 VLESS Server Quick Setup"
echo "==========================="

# Проверка root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите от root: sudo bash setup.sh"
    exit 1
fi

echo ""
echo "📦 Установка зависимостей..."
apt update
apt install -y golang-go curl unzip jq qrencode

echo ""
echo "✅ Зависимости установлены!"
echo ""
echo "📋 Далее:"
echo "   1. sudo bash deploy.sh          # Установка сервера"
echo "   2. sudo bash clients.sh add <name>  # Добавить клиентов"
echo ""
