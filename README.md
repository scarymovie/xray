# VLESS Reality VPN Server

Сервер для развёртывания VLESS Reality VPN с обходом блокировок в России и Китае.

## Почему VLESS Reality?

- **Маскировка под HTTPS** — трафик выглядит как обычное посещение сайта
- **Reality** — дополнительный слой обфускации без необходимости в реальном TLS-сертификате
- **uTLS** — имитация TLS-отпечатков популярных браузеров
- **Работает в Китае и РФ** — устойчив к DPI-блокировкам

## Требования

- Сервер Ubuntu 20.04+ с публичным IP
- Доменное имя,指向щее на сервер (опционально для Reality)
- Открытые порты: 443 (или другой на выбор)
- Go 1.21+ на сервере (для сборки бинарника)

## Задачи

### 1. Подготовка сервера

- [ ] Обновить систему (`apt update && apt upgrade`)
- [ ] Открыть порты в firewall (UFW)
- [ ] Установить зависимости

### 2. Установка Xray-core

- [ ] Скачать и установить Xray-core
- [ ] Настроить systemd-сервис для автозапуска

### 3. Конфигурация VLESS Reality

- [ ] Сгенерировать приватный ключ и short ID
- [ ] Настроить inbound для VLESS Reality
- [ ] Настроить outbound (freedom)
- [ ] Указать целевой домен для маскировки (dest)

### 4. Запуск и проверка

- [ ] Запустить сервис Xray
- [ ] Проверить статус сервиса
- [ ] Протестировать подключение с клиента

### 5. Настройка клиента

- [ ] Сгенерировать клиентскую конфигурацию
- [ ] Настроить клиент (Hiddify, NekoBox, v2rayNG)
- [ ] Проверить утечки DNS

## Быстрый старт

### На сервере (Ubuntu 24.04)

#### Вариант A: Автоматическая установка (скрипт)

```bash
# 1. Установка зависимостей
sudo bash setup.sh

# 2. Развёртывание сервера
sudo bash deploy.sh

# 3. Добавить клиентов
sudo bash clients.sh add iphone
sudo bash clients.sh add android

# 4. Получить ссылку
cat /etc/vless/client-iphone.txt
```

#### Вариант B: Пошаговая установка

#### Шаг 1: Подготовка сервера

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка Go (если не установлен)
sudo apt install -y golang-go

# Проверка версии Go
go version
```

#### Шаг 2: Открытие портов (UFW firewall)

```bash
# Включить UFW (если не включён)
sudo ufw enable

# Разрешить SSH (чтобы не потерять доступ!)
sudo ufw allow 22/tcp

# Разрешить порт для VLESS (443)
sudo ufw allow 443/tcp

# Проверка статуса
sudo ufw status
```

**Альтернативно (если используется iptables напрямую):**
```bash
# Проверка текущих правил
sudo iptables -L -n

# Добавление правила для порта 443
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Сохранение правил (Ubuntu)
sudo netfilter-persistent save
```

**Для облачных провайдеров (AWS, GCP, Azure, Oracle):**
Также нужно открыть порт в панели управления облаком:
- **AWS EC2**: Security Groups → Inbound Rules → Add Rule → TCP:443
- **Google Cloud**: VPC Network → Firewall → Create Rule
- **Oracle Cloud**: Security List → Ingress Rules → Add

#### Шаг 3: Установка Xray-core

**Способ 1: Автоматическая установка (рекомендуется)**
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

**Способ 2: Ручная установка**
```bash
# Скачать последнюю версию
XRAY_VERSION=25.2.27
wget https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip

# Установить unzip если нет
sudo apt install -y unzip

# Распаковать
unzip Xray-linux-64.zip

# Переместить бинарник
sudo mv xray /usr/local/bin/
sudo chmod +x /usr/local/bin/xray

# Создать директорию для конфигурации
sudo mkdir -p /usr/local/etc/xray
```

**Проверка установки:**
```bash
xray version
```

#### Шаг 4: Настройка systemd

Systemd — система инициализации в Ubuntu. Она управляет сервисами.

**Создание сервиса:**
```bash
sudo nano /etc/systemd/system/xray.service
```

**Содержимое файла:**
```ini
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
ExecStart=/usr/local/bin/xray run -c /etc/vless/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
```

**Команды управления сервисом:**
```bash
# Перезагрузить конфигурацию systemd
sudo systemctl daemon-reload

# Включить автозапуск
sudo systemctl enable xray

# Запустить сервис
sudo systemctl start xray

# Проверить статус
sudo systemctl status xray

# Просмотр логов
sudo journalctl -u xray -f

# Перезапустить сервис
sudo systemctl restart xray

# Остановить сервис
sudo systemctl stop xray
```

#### Шаг 5: Развёртывание vless

```bash
# Клонирование репозитория (или скопируйте файлы вручную)
git clone <repo-url> && cd vless

# Сборка бинарника
go build -o vless .

# Запуск установки (от root)
sudo ./vless install

# Проверка статуса
sudo ./vless status

# Получить клиентскую конфигурацию
./vless config
```

### Локальная разработка

```bash
go run main.go install    # Покажет инструкцию для ручной установки
go run main.go generate   # Генерация ключей
go run main.go config     # Показать клиентскую конфигурацию
```

## Структура проекта

```
.
├── main.go           # CLI утилита для управления
├── go.mod            # Go модуль
├── deploy.sh         # Скрипт автоматической установки сервера
├── clients.sh        # Скрипт управления клиентами
├── setup.sh          # Быстрая установка зависимостей
├── fix-publickey.sh  # Исправление publicKey в конфиге
├── README.md         # Документация
└── vless.exe         # Скомпилированный бинарник (Windows)
```

## Файлы на сервере

```
/etc/vless/
├── config.json       # Конфигурация Xray-core
├── server.json       # Параметры сервера
├── clients.json      # База данных клиентов
├── client-*.txt      # VLESS ссылки для каждого клиента
└── vless-link.txt    # Ссылка первого клиента
```

## Команды CLI

| Команда | Описание |
|---------|----------|
| `install` | Установка Xray-core и настройка VLESS Reality |
| `status` | Проверка статуса сервиса |
| `config` | Показать клиентскую конфигурацию (vless:// ссылка + JSON) |
| `generate` | Генерация новых ключей X25519 |
| `uninstall` | Удаление Xray и конфигурации |

## Управление клиентами

Для добавления и управления клиентами используйте скрипт `clients.sh`.

### Установка зависимостей

```bash
sudo apt install -y jq qrencode
```

### Команды

| Команда | Описание |
|---------|----------|
| `sudo bash clients.sh add <name>` | Добавить нового клиента |
| `sudo bash clients.sh remove <name>` | Удалить клиента |
| `sudo bash clients.sh list` | Показать список всех клиентов |
| `sudo bash clients.sh show <name>` | Показать конфигурацию клиента |
| `sudo bash clients.sh enable <name>` | Включить клиента |
| `sudo bash clients.sh disable <name>` | Выключить клиента |
| `sudo bash clients.sh export` | Экспорт всех клиентов (JSON) |

### Примеры использования

```bash
# Добавить клиентов для разных устройств
sudo bash clients.sh add iphone
sudo bash clients.sh add android
sudo bash clients.sh add laptop
sudo bash clients.sh add wife_phone

# Посмотреть список клиентов
sudo bash clients.sh list

# Показать конфигурацию конкретного клиента
sudo bash clients.sh show iphone

# Временное отключение клиента
sudo bash clients.sh disable laptop
sudo bash clients.sh enable laptop

# Удаление клиента
sudo bash clients.sh remove laptop

# Экспорт всех клиентов
sudo bash clients.sh export > backup.json
```

### Файлы клиентов

- `/etc/vless/clients.json` — база данных клиентов
- `/etc/vless/client-<name>.txt` — vless:// ссылка для каждого клиента
- `/etc/vless/config.json` — основная конфигурация Xray

## Клиенты

### v2rayNG (Windows/Android)

1. **Импорт ссылки:**
   - Откройте v2rayNG
   - Нажмите `+` → **"Импорт из буфера обмена"**
   - Или отсканируйте QR код

2. **Проверка настроек:**
   - Flow: `xtls-rprx-vision`
   - Reality ShortId: (из ссылки)
   - Reality ServerName: `www.microsoft.com`

3. **Подключение:** Выберите сервер → кнопка подключения

### Hiddify (Windows/macOS/Linux/Android/iOS)

1. **Импорт:**
   - Откройте Hiddify
   - Нажмите `+` или `Import`
   - Вставьте vless:// ссылку или QR код

2. **Подключение:** Большая кнопка в центре

3. **Проверка:** Откройте https://whoer.net или https://2ip.ru

### FoXray (iOS/macOS)

1. **Импорт:**
   - Откройте FoXray
   - Профиль → Добавить профиль → Из буфера обмена
   - Или отсканируйте QR код

2. **Подключение:** Выберите профиль → Connect

---

## Формат VLESS ссылки

### IPv4
```
vless://uuid@192.168.1.1:443?encryption=none&security=reality&sni=example.com&fp=chrome&pbk=PUBLIC_KEY&sid=shortid&type=tcp#name
                                                           ^^^
                                                      публичный ключ (обязательно!)
```

### IPv6 (адрес в скобках!)
```
vless://uuid@[2a0d:6c2:17:1f6::]:443?encryption=none&security=reality&sni=example.com&fp=chrome&pbk=PUBLIC_KEY&sid=shortid&type=tcp#name
```

**Параметры:**
- `uuid` — уникальный идентификатор клиента
- `security=reality` — протокол безопасности
- `sni` — домен для маскировки (www.microsoft.com)
- `fp=chrome` — отпечаток браузера
- `pbk` — **публичный ключ** (обязательно для Reality!)
- `sid` — ShortId для Reality
- `flow=xtls-rprx-vision` — поток (опционально, рекомендуется)

---

## Исправление ошибок

### Ошибка: "PublicKey property is invalid"

Это означает, что в ссылке отсутствует параметр `pbk` (публичный ключ).

**Решение:**

```bash
# 1. Проверить наличие publicKey в конфиге
sudo jq '.inbounds[0].streamSettings.realitySettings.publicKey' /usr/local/etc/xray/config.json

# 2. Если пусто — запустить скрипт исправления
sudo bash fix-publickey.sh

# 3. Пересоздать клиентов
sudo bash clients.sh add iphone
```

## Лицензия

MIT
