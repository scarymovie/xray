# VLESS Reality VPN Server

Сервер для развёртывания VLESS Reality VPN с обходом блокировок в России и Китае.

## Почему VLESS Reality?

- **Маскировка под HTTPS** — трафик выглядит как обычное посещение сайта
- **Reality** — дополнительный слой обфускации без необходимости в реальном TLS-сертификате
- **uTLS** — имитация TLS-отпечатков популярных браузеров
- **Работает в Китае и РФ** — устойчив к DPI-блокировкам

## Требования

- Сервер Ubuntu 20.04+ с публичным IP
- Открытые порты: 443 (или другой на выбор)
- Доступ root

## Структура проекта

```
.
├── deploy.sh         # Полная установка сервера
├── clients.sh        # Управление клиентами (add/remove/list)
├── gen-keys.sh       # Генерация ключей для Reality
├── setup.sh          # Установка зависимостей
└── README.md         # Документация
```

## Быстрый старт

### На сервере (Ubuntu 24.04)

```bash
# 1. Развёртывание (всё автоматически)
sudo bash deploy.sh

# 2. Добавить клиентов
sudo bash clients.sh add iphone
sudo bash clients.sh add android

# 3. Получить ссылку
cat /etc/vless/vless-link.txt
# или для конкретного клиента
cat /etc/vless/client-iphone.txt
```

## Управление клиентами

```bash
# Добавить клиента
sudo bash clients.sh add <name>

# Список клиентов
sudo bash clients.sh list

# Показать конфигурацию клиента
sudo bash clients.sh show <name>

# Удалить клиента
sudo bash clients.sh remove <name>

# Включить/выключить
sudo bash clients.sh enable <name>
sudo bash clients.sh disable <name>
```

### Примеры

```bash
sudo bash clients.sh add iphone
sudo bash clients.sh add android
sudo bash clients.sh add laptop
sudo bash clients.sh list
```

## Команды управления Xray

```bash
# Статус
sudo systemctl status xray

# Перезапуск
sudo systemctl restart xray

# Логи
sudo journalctl -u xray -f

# Остановить
sudo systemctl stop xray
```

## Файлы на сервере

```
/usr/local/etc/xray/config.json  # Конфигурация Xray
/etc/vless/server.json           # Параметры сервера
/etc/vless/clients.json          # База клиентов
/etc/vless/client-*.txt          # VLESS ссылки
/etc/vless/vless-link.txt        # Первая ссылка
```

## Формат VLESS ссылки

```
vless://uuid@ip:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=shortid&type=tcp#name
                                                                 ^^^
                                                            publicKey (обязательно!)
```

**Параметры:**
- `uuid` — идентификатор клиента
- `security=reality` — протокол
- `sni` — домен маскировки
- `fp=chrome` — fingerprint браузера
- `pbk` — **публичный ключ** (обязательно!)
- `sid` — ShortId

## Клиенты

### v2rayNG (Windows/Android)
1. `+` → "Импорт из буфера обмена"
2. Вставьте vless:// ссылку
3. Подключиться

### Hiddify (Windows/macOS/Linux/Android/iOS)
1. `+` → Import
2. Вставьте ссылку или QR код
3. Подключиться

### FoXray (iOS)
1. Профиль → Добавить → Из буфера обмена
2. Подключиться

## Проверка

После подключения:
1. Откройте https://whoer.net или https://2ip.ru
2. Проверьте что IP изменился на серверный
3. Проверьте отсутствие утечек DNS

## Исправление ошибок

### Ошибка: "PublicKey property is invalid"

В ссылке отсутствует `pbk` (публичный ключ).

```bash
# Перегенерировать ключи
sudo bash gen-keys.sh

# Пересоздать клиента
sudo bash clients.sh add <name>
```

### Xray не запускается

```bash
# Проверить конфиг
sudo jq . /usr/local/etc/xray/config.json

# Посмотреть логи
sudo journalctl -u xray -n 20 --no-pager
```

## Лицензия

MIT
