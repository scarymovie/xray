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
# 1. Скопируйте deploy.sh на сервер (или создайте вручную)
# 2. Запустите от root:
sudo bash deploy.sh

# 3. После установки получите ссылку:
cat /etc/vless/vless-link.txt
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
├── deploy.sh         # Скрипт автоматической установки
├── README.md         # Документация
└── vless.exe         # Скомпилированный бинарник (Windows)
```

## Команды CLI

| Команда | Описание |
|---------|----------|
| `install` | Установка Xray-core и настройка VLESS Reality |
| `status` | Проверка статуса сервиса |
| `config` | Показать клиентскую конфигурацию (vless:// ссылка + JSON) |
| `generate` | Генерация новых ключей X25519 |
| `uninstall` | Удаление Xray и конфигурации |

## Клиенты

- **Windows**: v2rayNG, Hiddify
- **macOS**: Hiddify, FoXray
- **Linux**: Hiddify, v2rayN
- **Android**: v2rayNG, Hiddify
- **iOS**: FoXray, Hiddify

## Лицензия

MIT
