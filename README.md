# proxy-vpn (Xray only)

Контейнер поднимает HTTP и SOCKS прокси напрямую в `xray`:
- HTTP: `3128`
- SOCKS5: `1080`

Оба входа идут в один и тот же outbound VLESS/REALITY.

## Архитектура

`client(http:3128 or socks:1080) -> xray inbound -> xray outbound(VLESS/REALITY)`

## Запуск

1. Подготовить реальный конфиг Xray в `conf/xray.json` (файл gitignored).
2. Настроить пользователей (один из вариантов):
   - `PROXY_USERS=user1:pass1,user2:pass2`
   - либо legacy-вариант: `PROXY_USER=user1` + `PROXY_PASS=pass1`
3. Запустить:

```bash
docker compose up --build -d
```

Публикуемые порты по умолчанию описаны в [`docker-compose.yml`](docker-compose.yml):

- `3128:3128` — HTTP proxy
- `1080:1080` — SOCKS5 proxy

## Проверка

Проверки делать именно через прокси-порт, а не «прямым curl» из контейнера.

1. Прямой выход контейнера (контроль):

```sh
curl https://ipinfo.io/json | jq
```

2. Через HTTP прокси 3128 (с отключением bypass через `NO_PROXY`):

```sh
curl --noproxy '' -x http://127.0.0.1:3128 https://ipinfo.io/json | jq
```

3. Через SOCKS5 1080 (контрольная точка):

```sh
curl --socks5-hostname 127.0.0.1:1080 https://ipinfo.io/json | jq
```

Ожидание: IP из шага 2 должен совпадать с шагом 3.

Если без `--noproxy ''` получается «прямой» IP, значит `curl` обошел прокси из-за переменной окружения `NO_PROXY/no_proxy`.

## Мультипользовательская авторизация

`entrypoint` генерирует runtime-конфиг и подставляет одинаковые аккаунты в HTTP+SOCKS inbounds.

Формат переменной:

```sh
PROXY_USERS=user1:pass1,user2:pass2,user3:pass3
```

Если `PROXY_USERS` не задан, но заданы `PROXY_USER` + `PROXY_PASS`, используется один пользователь.

Если не задано ничего — прокси без пароля.

## Отладка

Проверить runtime-конфиг Xray:

```sh
cat /tmp/xray.runtime.json
```

Проверить логи контейнера:

```sh
docker logs vpn-proxy
```

## Примечания

- Реальный конфиг хранится в `conf/xray.json` (gitignored).
- В `conf/xray.json` задается outbound (VLESS/REALITY), а inbounds формируются в runtime через [`entrypoint.sh`](entrypoint.sh).
