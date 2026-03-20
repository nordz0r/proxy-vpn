# proxy-vpn

[![Release](https://img.shields.io/github/v/release/nordz0r/proxy-vpn?style=flat-square&color=brightgreen)](https://github.com/nordz0r/proxy-vpn/releases)
[![Docker Image](https://img.shields.io/badge/ghcr.io-nordz0r%2Fproxy--vpn-blue?style=flat-square)](https://ghcr.io/nordz0r/proxy-vpn)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen?style=flat-square)](LICENSE)

**[English version](README.en.md)**

HTTP и SOCKS5 прокси-сервер на базе [Xray-core](https://github.com/XTLS/Xray-core) в Docker-контейнере. Принимает конфиги, экспортированные из **[Amnezia VPN](https://amnezia.org/)** (протокол VLESS + REALITY), и превращает их в полноценный прокси для браузера, системы или любого приложения.

## Зачем это нужно

Amnezia VPN генерирует конфигурации Xray (VLESS + REALITY) для обхода блокировок. Этот проект берёт такой конфиг и поднимает на его основе HTTP и/или SOCKS5 прокси-сервер, к которому можно подключить:

- браузер (через настройки прокси или расширения вроде FoxyProxy)
- мобильные устройства и IoT
- приложения и скрипты (`curl`, `wget`, и т.д.)
- любые устройства в локальной сети

```
Клиент ──► HTTP  :3128  ─┐
                          ├──► Xray ──► VLESS/REALITY ──► Интернет
Клиент ──► SOCKS :1080  ─┘
```

Приватные сети и российские домены маршрутизируются **напрямую**, минуя туннель.

## Возможности

- **HTTP и SOCKS5 прокси** — два протокола одновременно
- **Конфиги из Amnezia VPN** — используйте экспортированный Xray JSON как есть
- **VLESS + REALITY** — современный протокол обхода DPI-блокировок
- **Раздельная маршрутизация** — российские домены/IP и приватные сети идут напрямую
- **Аутентификация** — поддержка нескольких пользователей
- **Пользовательские домены для прямого доступа** — настройка через переменные окружения
- **Метрики Xray** — опциональный HTTP-эндпоинт статистики
- **Multi-arch** — `linux/amd64` и `linux/arm64`
- **Минимальный образ** — Alpine Linux, один процесс, ~30 МБ

## Быстрый старт

### Одной вставкой на чистой машине

```bash
mkdir -p /opt/proxy-vpn/conf && cd /opt/proxy-vpn
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/nordz0r/proxy-vpn/main/docker-compose.yml
curl -fsSL -o .env https://raw.githubusercontent.com/nordz0r/proxy-vpn/main/.env.example
curl -fsSL -o conf/xray.json https://raw.githubusercontent.com/nordz0r/proxy-vpn/main/conf/xray.json.example

# Отредактируйте conf/xray.json: сервер, UUID, publicKey, shortId, serverName
# Отредактируйте .env: порты, логин/пароль прокси или оставьте auth-поля пустыми

docker compose up -d
```

Проверка:

```bash
docker compose logs -f vpn-proxy
```

### 1. Подготовьте конфиг Xray

Экспортируйте конфигурацию из Amnezia VPN в формате Xray JSON или создайте вручную:

```bash
cp conf/xray.json.example conf/xray.json
# Отредактируйте conf/xray.json — укажите адрес сервера, UUID, ключи REALITY
```

### 2. Настройте окружение

```bash
cp .env.example .env
# Отредактируйте .env — задайте логин и пароль для прокси
```

### 3. Запустите

```bash
docker compose up -d
```

Образ автоматически скачается из GitHub Container Registry.

Для сборки локально:

```bash
docker compose up --build -d
```

## Конфигурация

### Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---|---|
| `HTTP_PORT` | — | Порт HTTP-прокси (например, `3128`). Если не задан — HTTP-прокси не запускается |
| `SOCKS_PORT` | — | Порт SOCKS5-прокси (например, `1080`). Если не задан — SOCKS5-прокси не запускается |
| `PROXY_USERS` | — | Мульти-аутентификация: `user1:pass1,user2:pass2` |
| `PROXY_USER` | — | Логин (одиночный пользователь, fallback) |
| `PROXY_PASS` | — | Пароль (одиночный пользователь, fallback) |
| `XRAY_CONFIG` | `/etc/xray/conf.json` | Путь к базовому конфигу внутри контейнера |
| `DIRECT_DOMAINS` | — | Домены для прямого доступа (через запятую/точку с запятой), поддержка `*.example.com` |
| `LOG_LEVEL` | `warning` | Уровень логирования Xray: `none`, `error`, `warning`, `info`, `debug`. При `info`/`debug` включается access-лог (IP клиента, назначение, маршрут) |
| `METRICS_PORT` | — | Порт HTTP-метрик Xray (например, `9999`) |

> **Примечание:** необходимо указать хотя бы один из портов (`HTTP_PORT` или `SOCKS_PORT`), иначе контейнер не запустится.

### Аутентификация

Настраивается через переменные окружения, **не** в `xray.json`:

```bash
# Несколько пользователей (через запятую или точку с запятой)
PROXY_USERS=alice:secret1,bob:secret2

# Один пользователь
PROXY_USER=alice
PROXY_PASS=secret1

# Пустые/незаполненные значения = открытый прокси (без аутентификации)
# Например, можно оставить так:
PROXY_USERS=
PROXY_USER=
```

### Маршрутизация

Entrypoint автоматически добавляет правила маршрутизации:

| Совпадение | Действие |
|---|---|
| `geoip:private` + `geoip:ru` | Напрямую (минуя туннель) |
| `geosite:private` + `geosite:category-ru` + `domain:local` + `DIRECT_DOMAINS` | Напрямую (минуя туннель) |
| Всё остальное | Через прокси (VLESS/REALITY) |

Добавление пользовательских доменов для прямого доступа:

```bash
DIRECT_DOMAINS=*.corp.local,*.lan,example.internal
```

## Проверка работы

```bash
# Должен показать IP VPN-сервера
curl -x http://user:pass@127.0.0.1:3128 https://ipinfo.io/json

# Должен показать ваш реальный IP (российский сайт — идёт напрямую)
curl -x http://user:pass@127.0.0.1:3128 https://2ip.ru

# Проверка SOCKS5
curl --socks5-hostname user:pass@127.0.0.1:1080 https://ipinfo.io/json
```

## TLS-терминация (опционально)

Пример конфигурации Angie/nginx для TLS-терминации перед локальными портами прокси:

```nginx
# Убедитесь, что в конфиге есть:
# stream {
#   include /etc/angie/stream.d/*.conf;
# }

# HTTPS-прокси через TLS
server {
    listen 446 ssl;
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    proxy_pass 127.0.0.1:3128;
}
```

## Архитектура

- **entrypoint.sh** генерирует `/tmp/xray.runtime.json` при старте контейнера:
  - добавляет `http-in` / `socks-in` inbound'ы с аутентификацией и sniffing'ом
  - добавляет `direct` outbound (freedom) и правила маршрутизации
  - помечает первый outbound в базовом конфиге тегом `proxy`
- **network_mode: host** — порты привязываются напрямую к хосту
- **dumb-init** как PID 1 для корректной обработки сигналов
- Проверка готовности: оба порта должны ответить в течение 30 секунд

## Отладка

```bash
# Логи контейнера
docker compose logs -f vpn-proxy

# Посмотреть сгенерированный конфиг
docker exec vpn-proxy cat /tmp/xray.runtime.json | jq
```

## Ключевые слова

Xray proxy, VLESS proxy, REALITY proxy, Amnezia VPN proxy, HTTP proxy Xray, SOCKS5 proxy Xray, Docker proxy VPN, обход блокировок, прокси-сервер Xray, прокси для браузера, Amnezia VPN конфиг, Xray Docker, split tunneling, раздельная маршрутизация, прокси Россия
