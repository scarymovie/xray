package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	xrayVersion    = "1.8.24"
	configDir      = "/etc/vless"
	configFile     = "/etc/vless/config.json"
	systemdService = "/etc/systemd/system/xray.service"
	xrayBin        = "/usr/local/bin/xray"
)

// XrayConfig структура конфигурации Xray
type XrayConfig struct {
	Log              *LogConfig              `json:"log"`
	API              *APIConfig              `json:"api"`
	DNS              *DNSConfig              `json:"dns"`
	Inbounds         []Inbound               `json:"inbounds"`
	Outbounds        []Outbound              `json:"outbounds"`
	Routing          *RoutingConfig          `json:"routing"`
	Transport        *TransportConfig        `json:"transport"`
	Policy           *PolicyConfig           `json:"policy"`
	Reverse          *ReverseConfig          `json:"reverse"`
	FakeDNS          *FakeDNSConfig          `json:"fakedns"`
	Stats            *StatsConfig            `json:"stats"`
	Observatory      *ObservatoryConfig      `json:"observatory"`
	BurstObservatory *BurstObservatoryConfig `json:"burstObservatory"`
}

type LogConfig struct {
	LogLevel string `json:"loglevel"`
	Access   string `json:"access"`
	Error    string `json:"error"`
}

type APIConfig struct {
	Tag   string       `json:"tag"`
	Serve *ServeConfig `json:"serve"`
}

type ServeConfig struct {
	DomainAddress string `json:"domainAddress"`
}

type DNSConfig struct {
	Hosts         map[string]any `json:"hosts"`
	Servers       []any          `json:"servers"`
	QueryStrategy string         `json:"queryStrategy"`
}

type Inbound struct {
	Port           int             `json:"port"`
	Protocol       string          `json:"protocol"`
	Settings       map[string]any  `json:"settings"`
	StreamSettings *StreamSettings `json:"streamSettings"`
	Sniffing       *SniffingConfig `json:"sniffing"`
}

type StreamSettings struct {
	Network         string           `json:"network"`
	Security        string           `json:"security"`
	RealitySettings *RealitySettings `json:"realitySettings"`
	TCPSettings     *TCPSettings     `json:"tcpSettings"`
}

type RealitySettings struct {
	Show             bool     `json:"show"`
	Dest             string   `json:"dest"`
	Xver             uint64   `json:"xver"`
	ServerNames      []string `json:"serverNames"`
	PrivateKey       string   `json:"privateKey"`
	MinClientVer     string   `json:"minClientVer"`
	MaxClientVer     string   `json:"maxClientVer"`
	MaxTimeDiff      uint64   `json:"maxTimeDiff"`
	ProxyProtocolVer uint64   `json:"proxyProtocolVer"`
	ShortIDs         []string `json:"shortIds"`
}

type TCPSettings struct {
	Header *TCPHeader `json:"header"`
}

type TCPHeader struct {
	Type string `json:"type"`
}

type SniffingConfig struct {
	Enabled      bool     `json:"enabled"`
	DestOverride []string `json:"destOverride"`
	RouteOnly    bool     `json:"routeOnly"`
}

type Outbound struct {
	Protocol string         `json:"protocol"`
	Settings map[string]any `json:"settings"`
	Tag      string         `json:"tag"`
}

type RoutingConfig struct {
	DomainStrategy string        `json:"domainStrategy"`
	Rules          []RoutingRule `json:"rules"`
}

type RoutingRule struct {
	Type        string   `json:"type"`
	IP          []string `json:"ip"`
	OutboundTag string   `json:"outboundTag"`
}

type TransportConfig struct{}
type PolicyConfig struct{}
type ReverseConfig struct{}
type FakeDNSConfig struct{}
type StatsConfig struct{}
type ObservatoryConfig struct{}
type BurstObservatoryConfig struct{}

// ServerConfig хранит данные сервера
type ServerConfig struct {
	Port       int
	PrivateKey string
	ShortID    string
	ServerName string
	UUID       string
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	command := os.Args[1]

	switch command {
	case "install":
		install()
	case "status":
		status()
	case "config":
		showConfig()
	case "generate":
		generateKeys()
	case "uninstall":
		uninstall()
	default:
		fmt.Printf("Неизвестная команда: %s\n", command)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`VLESS Reality Server Manager

Использование:
  go run main.go <command>

Команды:
  install    Установка и настройка Xray-core с VLESS Reality
  status     Проверка статуса сервиса
  config     Показать клиентскую конфигурацию
  generate   Генерация новых ключей
  uninstall  Удаление Xray-core и конфигурации`)
}

func generateKeys() {
	// Генерация приватного ключа X25519
	cmd := exec.Command("xray", "x25519")
	output, err := cmd.Output()
	if err == nil {
		fmt.Println("X25519 ключи:")
		fmt.Println(string(output))
		return
	}

	// Если xray не установлен, генерируем случайные ключи
	privateKey := generateRandomHex(32)
	shortID := generateRandomHex(8)

	fmt.Println("Сгенерированные ключи (для Reality):")
	fmt.Printf("PrivateKey: %s\n", privateKey)
	fmt.Printf("ShortId: %s\n", shortID)
}

func generateRandomHex(length int) string {
	bytes := make([]byte, length)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func generateUUID() string {
	uuid := make([]byte, 16)
	rand.Read(uuid)
	// Версия 4, вариант 1
	uuid[6] = (uuid[6] & 0x0f) | 0x40
	uuid[8] = (uuid[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", uuid[0:4], uuid[4:6], uuid[6:8], uuid[8:10], uuid[10:])
}

func install() {
	if runtime.GOOS != "linux" {
		fmt.Println("⚠️  Команда install работает только на Linux (Ubuntu)")
		fmt.Println("\n=== Подробная инструкция для Ubuntu 24.04 ===\n")
		fmt.Println("📋 Шаг 1: Подготовка сервера")
		fmt.Println("-----------------------------------")
		fmt.Println("sudo apt update && sudo apt upgrade -y")
		fmt.Println("sudo apt install -y golang-go curl unzip\n")

		fmt.Println("🔓 Шаг 2: Открытие портов")
		fmt.Println("-----------------------------------")
		fmt.Println("# UFW firewall:")
		fmt.Println("sudo ufw enable")
		fmt.Println("sudo ufw allow 22/tcp    # SSH")
		fmt.Println("sudo ufw allow 443/tcp   # VLESS")
		fmt.Println("sudo ufw status\n")
		fmt.Println("# Для облачных провайдеров также откройте порт 443 в панели управления!\n")

		fmt.Println("📦 Шаг 3: Установка Xray-core")
		fmt.Println("-----------------------------------")
		fmt.Println("# Автоматическая установка:")
		fmt.Println(`bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install`)
		fmt.Println("\n# Или ручная:")
		fmt.Println("wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip")
		fmt.Println("unzip Xray-linux-64.zip")
		fmt.Println("sudo mv xray /usr/local/bin/ && sudo chmod +x /usr/local/bin/xray")
		fmt.Println("xray version  # проверка\n")

		fmt.Println("⚙️  Шаг 4: Настройка systemd")
		fmt.Println("-----------------------------------")
		fmt.Println("# Создайте файл /etc/systemd/system/xray.service:")
		fmt.Println(`
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -c /etc/vless/config.json
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
`)
		fmt.Println("# Применить:")
		fmt.Println("sudo systemctl daemon-reload")
		fmt.Println("sudo systemctl enable xray")
		fmt.Println("sudo systemctl start xray")
		fmt.Println("sudo systemctl status xray\n")

		fmt.Println("🚀 Шаг 5: Запуск vless")
		fmt.Println("-----------------------------------")
		fmt.Println("go build -o vless .")
		fmt.Println("sudo ./vless install  # из-под root на сервере")
		fmt.Println("./vless config        # получить клиентскую конфигурацию")
		fmt.Println()
		return
	}

	fmt.Println("🚀 Установка VLESS Reality сервера...")

	// Проверка root
	if os.Geteuid() != 0 {
		fmt.Println("❌ Требуется запуск от root")
		os.Exit(1)
	}

	// Создание директории
	fmt.Println("📁 Создание директории конфигурации...")
	if err := os.MkdirAll(configDir, 0755); err != nil {
		fmt.Printf("❌ Ошибка создания директории: %v\n", err)
		os.Exit(1)
	}

	// Генерация данных
	port := 443
	privateKey := generateRandomHex(32)
	shortID := generateRandomHex(8)
	uuid := generateUUID()
	serverName := "www.microsoft.com" // Целевой домен для маскировки

	fmt.Println("🔑 Генерация ключей...")
	fmt.Printf("   Port: %d\n", port)
	fmt.Printf("   UUID: %s\n", uuid)
	fmt.Printf("   PrivateKey: %s\n", privateKey)
	fmt.Printf("   ShortId: %s\n", shortID)
	fmt.Printf("   ServerName: %s\n", serverName)

	// Создание конфигурации
	config := createConfig(port, privateKey, shortID, uuid, serverName)

	configPath := filepath.Join(configDir, "config.json")
	if err := writeJSON(configPath, config); err != nil {
		fmt.Printf("❌ Ошибка записи конфигурации: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("✅ Конфигурация создана:", configPath)

	// Установка Xray
	fmt.Println("\n📦 Установка Xray-core...")
	if err := installXray(); err != nil {
		fmt.Printf("⚠️  Ошибка установки Xray: %v\n", err)
		fmt.Println("\nПопробуйте вручную:")
		fmt.Println(`bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install`)
	}

	// Создание systemd сервиса
	fmt.Println("\n⚙️  Настройка systemd сервиса...")
	if err := createSystemdService(); err != nil {
		fmt.Printf("⚠️  Ошибка создания сервиса: %v\n", err)
	}

	// Запуск сервиса
	fmt.Println("\n🔄 Запуск сервиса...")
	runCommand("systemctl", "daemon-reload")
	runCommand("systemctl", "enable", "xray")
	runCommand("systemctl", "start", "xray")

	fmt.Println("\n✅ Установка завершена!")
	fmt.Println("\n📋 Для просмотра клиентской конфигурации выполните:")
	fmt.Println("   go run main.go config")
	fmt.Println("\n📊 Проверка статуса:")
	fmt.Println("   go run main.go status")

	// Сохранение данных сервера для client config
	saveServerConfig(ServerConfig{
		Port:       port,
		PrivateKey: privateKey,
		ShortID:    shortID,
		ServerName: serverName,
		UUID:       uuid,
	})
}

func createConfig(port int, privateKey, shortID, uuid, serverName string) *XrayConfig {
	return &XrayConfig{
		Log: &LogConfig{
			LogLevel: "warning",
			Access:   "/var/log/xray/access.log",
			Error:    "/var/log/xray/error.log",
		},
		Inbounds: []Inbound{
			{
				Port:     port,
				Protocol: "vless",
				Settings: map[string]any{
					"clients": []map[string]any{
						{
							"id":   uuid,
							"flow": "xtls-rprx-vision",
						},
					},
					"decryption": "none",
				},
				StreamSettings: &StreamSettings{
					Network:  "tcp",
					Security: "reality",
					RealitySettings: &RealitySettings{
						Show:             false,
						Dest:             fmt.Sprintf("%s:443", serverName),
						Xver:             0,
						ServerNames:      []string{serverName, "www.apple.com"},
						PrivateKey:       privateKey,
						MinClientVer:     "1.8.0",
						MaxClientVer:     "",
						MaxTimeDiff:      86400000,
						ProxyProtocolVer: 0,
						ShortIDs:         []string{shortID, ""},
					},
					TCPSettings: &TCPSettings{
						Header: &TCPHeader{
							Type: "none",
						},
					},
				},
				Sniffing: &SniffingConfig{
					Enabled:      true,
					DestOverride: []string{"http", "tls", "quic"},
					RouteOnly:    false,
				},
			},
		},
		Outbounds: []Outbound{
			{
				Protocol: "freedom",
				Tag:      "direct",
				Settings: map[string]any{},
			},
		},
		Routing: &RoutingConfig{
			DomainStrategy: "AsIs",
			Rules:          []RoutingRule{},
		},
	}
}

func writeJSON(path string, v any) error {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

func installXray() error {
	// Проверка наличия curl
	if _, err := exec.LookPath("curl"); err != nil {
		return fmt.Errorf("curl не найден")
	}

	// Скрипт установки Xray
	script := fmt.Sprintf(`bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version %s`, xrayVersion)

	cmd := exec.Command("bash", "-c", script)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func createSystemdService() error {
	serviceContent := `[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=` + xrayBin + ` run -c ` + configFile + `
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
`
	return os.WriteFile(systemdService, []byte(serviceContent), 0644)
}

func status() {
	fmt.Println("📊 Статус сервиса Xray:\n")
	runCommand("systemctl", "status", "xray", "--no-pager")
}

func showConfig() {
	// Чтение сохранённой конфигурации
	cfg, err := loadServerConfig()
	if err != nil {
		fmt.Println("❌ Конфигурация не найдена. Запустите 'install' сначала.")
		fmt.Println("\nИли проверьте файл:", filepath.Join(configDir, "server.json"))
		os.Exit(1)
	}

	// Получение IP сервера
	serverIP := getServerIP()
	if serverIP == "" {
		serverIP = "<YOUR_SERVER_IP>"
	}

	clientConfig := generateClientConfig(serverIP, cfg)

	fmt.Println("\n📱 Клиентская конфигурация (VLESS Reality):\n")
	fmt.Println("=== vless:// ссылка ===")
	fmt.Println(clientConfig.VLESSLink)
	fmt.Println("\n=== JSON для импорта ===")
	fmt.Println(clientConfig.JSON)
	fmt.Println("\n=== Параметры ===")
	fmt.Printf("Адрес: %s\n", serverIP)
	fmt.Printf("Порт: %d\n", cfg.Port)
	fmt.Printf("UUID: %s\n", cfg.UUID)
	fmt.Printf("ServerName: %s\n", cfg.ServerName)
	fmt.Printf("ShortId: %s\n", cfg.ShortID)
}

type ClientConfig struct {
	VLESSLink string
	JSON      string
}

func generateClientConfig(serverIP string, cfg ServerConfig) *ClientConfig {
	// vless://uuid@server:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=publickey&sid=shortid&type=tcp&headerType=none#VLESS-Reality
	vlessLink := fmt.Sprintf("vless://%s@%s:%d?encryption=none&security=reality&sni=%s&fp=chrome&sid=%s&type=tcp&headerType=none#VLESS-Reality",
		cfg.UUID, serverIP, cfg.Port, cfg.ServerName, cfg.ShortID)

	jsonConfig := map[string]any{
		"remarks": "VLESS Reality",
		"outbounds": []map[string]any{
			{
				"protocol": "vless",
				"settings": map[string]any{
					"vnext": []map[string]any{
						{
							"address": serverIP,
							"port":    cfg.Port,
							"users": []map[string]any{
								{
									"id":         cfg.UUID,
									"encryption": "none",
									"flow":       "xtls-rprx-vision",
								},
							},
						},
					},
				},
				"streamSettings": map[string]any{
					"network":  "tcp",
					"security": "reality",
					"realitySettings": map[string]any{
						"serverName":  cfg.ServerName,
						"fingerprint": "chrome",
						"shortId":     cfg.ShortID,
					},
				},
			},
		},
	}

	jsonData, _ := json.MarshalIndent(jsonConfig, "", "  ")

	return &ClientConfig{
		VLESSLink: vlessLink,
		JSON:      string(jsonData),
	}
}

func getServerIP() string {
	// Попытка получить публичный IP
	cmd := exec.Command("curl", "-s", "ifconfig.me")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func saveServerConfig(cfg ServerConfig) {
	data, _ := json.MarshalIndent(cfg, "", "  ")
	path := filepath.Join(configDir, "server.json")
	os.WriteFile(path, data, 0644)
}

func loadServerConfig() (ServerConfig, error) {
	var cfg ServerConfig
	path := filepath.Join(configDir, "server.json")
	data, err := os.ReadFile(path)
	if err != nil {
		// Пробуем альтернативный путь
		path = "server.json"
		data, err = os.ReadFile(path)
		if err != nil {
			return cfg, err
		}
	}
	json.Unmarshal(data, &cfg)
	return cfg, nil
}

func uninstall() {
	if runtime.GOOS != "linux" {
		fmt.Println("⚠️  Команда uninstall работает только на Linux")
		return
	}

	if os.Geteuid() != 0 {
		fmt.Println("❌ Требуется запуск от root")
		os.Exit(1)
	}

	fmt.Println("🗑️  Удаление Xray Reality сервера...")

	runCommand("systemctl", "stop", "xray")
	runCommand("systemctl", "disable", "xray")

	os.Remove(systemdService)
	runCommand("systemctl", "daemon-reload")

	os.RemoveAll(configDir)
	os.Remove(xrayBin)

	fmt.Println("✅ Удаление завершено")
}

func runCommand(name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()
}
