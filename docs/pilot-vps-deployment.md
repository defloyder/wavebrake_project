# WAVEBREAK Pilot VPS Deployment Runbook

Документ описывает безопасное тестовое развертывание WAVEBREAK на одной виртуалке. Цель пилота - поднять весь stack в отдельной папке, проверить API/Web/Admin/monitoring и подготовить основу для подключения mobile/desktop клиентов.

Runbook рассчитан на Ubuntu/Debian VPS в Нидерландах, но подойдет и для другой Linux VM с Docker.

## 0. Что будет развернуто

На одной VPS поднимается Docker Compose stack:

- PostgreSQL
- Redis
- RabbitMQ
- WAVEBREAK Core API
- WAVEBREAK Core worker
- Laravel Web
- Laravel Admin
- optional node-agent для тестового node enrollment
- Prometheus
- Grafana
- Loki
- Tempo
- OpenTelemetry Collector
- Alertmanager
- node-exporter
- cAdvisor
- PostgreSQL/Redis exporters

Рабочая папка пилота:

```text
/opt/wavebreak-pilot/current
```

Это важно: развертывание не должно трогать существующие проекты на сервере.

## 1. Что нужно заранее

Минимум:

- VPS IP.
- SSH-доступ к пользователю с `sudo`.
- Ubuntu 22.04/24.04 или Debian 12.
- 2 CPU / 4 GB RAM минимум для пилота; комфортнее 4 CPU / 8 GB RAM.
- 30+ GB disk.
- Открытый SSH порт.

Желательно:

- домен или поддомены для пилота;
- доступ к DNS;
- возможность открыть `80/443`.

Рекомендуемые поддомены:

```text
app-pilot.example.com     -> Web
admin-pilot.example.com   -> Admin
api-pilot.example.com     -> Core API
grafana-pilot.example.com -> Grafana
```

Если домена пока нет, можно тестировать через IP и порты:

```text
Web:     http://SERVER_IP:8000
Admin:   http://SERVER_IP:8002
Core:    http://SERVER_IP:18080
Grafana: http://SERVER_IP:13000
```

## 2. Безопасный доступ на сервер

Лучший вариант для деплоя агентом или разработчиком:

1. Создать временного пользователя:

```bash
sudo adduser wavebreakdeploy
sudo usermod -aG sudo wavebreakdeploy
```

2. Добавить SSH public key в:

```text
/home/wavebreakdeploy/.ssh/authorized_keys
```

3. Проверить вход:

```bash
ssh wavebreakdeploy@SERVER_IP
```

Не рекомендуется передавать root password в чаты. Лучше временный sudo-user + SSH key. После пилота пользователя можно удалить.

## 3. Подготовить сервер

Подключиться по SSH:

```bash
ssh wavebreakdeploy@SERVER_IP
```

Обновить систему:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl git ufw openssl jq htop
```

Установить Docker:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
```

Перезайти в SSH, чтобы группа `docker` применилась:

```bash
exit
ssh wavebreakdeploy@SERVER_IP
```

Проверить Docker:

```bash
docker version
docker compose version
```

## 4. Firewall для пилота

Минимально:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

Если тестируем без домена через прямые порты, временно открыть только нужное:

```bash
sudo ufw allow 8000/tcp   # Web
sudo ufw allow 8002/tcp   # Admin
sudo ufw allow 18080/tcp  # Core API
sudo ufw allow 13000/tcp  # Grafana
```

Внешне не нужно открывать:

```text
5432  PostgreSQL
6379  Redis
5672  RabbitMQ AMQP
15672 RabbitMQ UI
9090  Prometheus
9093  Alertmanager
3100  Loki
3200  Tempo
4317  OTLP
4318  OTLP HTTP
```

Внимание: Docker может публиковать порты через iptables. Для строгой прод-защиты нужен reverse proxy + bind ports на `127.0.0.1` или DOCKER-USER chain rules. Для пилота достаточно не светить доступ публично без необходимости и ограничить firewall/security group у провайдера.

## 5. Забрать код

Создать отдельную папку:

```bash
sudo mkdir -p /opt/wavebreak-pilot
sudo chown "$USER:$USER" /opt/wavebreak-pilot
```

Клонировать репозиторий:

```bash
git clone git@github.com:defloyder/wavebrake_project.git /opt/wavebreak-pilot/current
cd /opt/wavebreak-pilot/current
```

Если на сервере нет GitHub SSH key, можно использовать HTTPS clone:

```bash
git clone https://github.com/defloyder/wavebrake_project.git /opt/wavebreak-pilot/current
```

Проверить ветку:

```bash
git status
git log --oneline -3
```

## 6. Создать pilot `.env`

Перейти в инфраструктуру:

```bash
cd /opt/wavebreak-pilot/current/wavebreak-infrastructure
```

Создать `.env`:

```bash
cat > .env <<'EOF'
COMPOSE_PROJECT_NAME=wavebreak_pilot

# Host ports. For no-domain pilot these can be public.
# For reverse-proxy pilot prefer 127.0.0.1:18080 and 127.0.0.1:13000.
WAVEBREAK_API_PORT=18080
WAVEBREAK_GRAFANA_PORT=13000

# Node-agent optional values.
WAVEBREAK_NODE_CODE=NL-PILOT-01
WAVEBREAK_NODE_REGION=NL
EOF
```

Сейчас `docker-compose.yml` содержит local/dev secrets внутри файла. Для пилота это допустимо только как временная обкатка в закрытом окружении. Перед публичным production нужно вынести все secrets в env и заменить:

- PostgreSQL password;
- RabbitMQ user/password;
- `WAVEBREAK_JWT_SECRET`;
- `WAVEBREAK_BOT_SERVICE_TOKEN`;
- Laravel `APP_KEY`;
- Grafana admin password.

## 7. Собрать и поднять stack

Из папки:

```bash
cd /opt/wavebreak-pilot/current/wavebreak-infrastructure
```

Поднять базу и брокеры:

```bash
docker compose up -d postgres redis rabbitmq
```

Проверить:

```bash
docker compose ps postgres redis rabbitmq
```

Собрать и запустить миграции/Core/worker:

```bash
docker compose up -d --build wavebreak-migrate wavebreak-api wavebreak-worker
```

Поднять Web/Admin:

```bash
docker compose up -d --build wavebreak-web wavebreak-admin
```

Поднять monitoring:

```bash
docker compose up -d prometheus grafana loki tempo otel-collector alertmanager node-exporter cadvisor postgres-exporter redis-exporter
```

Проверить весь stack:

```bash
docker compose ps
```

## 8. Health checks

На сервере:

```bash
curl -s http://127.0.0.1:18080/healthz | jq
curl -s http://127.0.0.1:18080/readyz | jq
curl -I http://127.0.0.1:8000
curl -I http://127.0.0.1:8002
curl -s http://127.0.0.1:13000/api/health | jq
```

Ожидаемо:

- Core `/healthz` -> `status: ok`
- Core `/readyz` -> `status: ready`
- Web/Admin -> HTTP 200/302
- Grafana `/api/health` -> `database: ok`

Если что-то не поднялось:

```bash
docker compose logs --tail=200 wavebreak-migrate
docker compose logs --tail=200 wavebreak-api
docker compose logs --tail=200 wavebreak-worker
docker compose logs --tail=200 wavebreak-web
docker compose logs --tail=200 wavebreak-admin
```

## 9. Создать администратора

Создать первого superadmin:

```bash
docker compose run --rm wavebreak-api \
  wavebreak-cli admin create \
  --email admin@example.com \
  --role superadmin
```

CLI попросит пароль интерактивно. Пароль должен быть минимум 12 символов.

Можно передать пароль флагом, но это хуже, потому что он попадет в shell history:

```bash
docker compose run --rm wavebreak-api \
  wavebreak-cli admin create \
  --email admin@example.com \
  --role superadmin \
  --password 'CHANGE_ME_LONG_PASSWORD'
```

Admin UI:

```text
http://SERVER_IP:8002
```

## 10. Создать тестового пользователя

Через Web UI:

```text
http://SERVER_IP:8000/register
```

Или через Core API:

```bash
curl -s -X POST http://127.0.0.1:18080/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"pilot-user@example.com","password":"WaveBreakPilot123!"}' | jq
```

## 11. Проверить mobile/desktop API flow

На сервере:

```bash
BASE=http://127.0.0.1:18080
EMAIL="pilot-app-$(date +%s)@wavebreak.test"
PASSWORD="WaveBreakPilot123!"

REGISTER_RESPONSE=$(curl -s -X POST "$BASE/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.access_token')
REFRESH_TOKEN=$(echo "$REGISTER_RESPONSE" | jq -r '.tokens.refresh_token')

curl -s "$BASE/v1/client/bootstrap" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq

PLAN_ID=$(curl -s "$BASE/v1/plans" | jq -r '.plans[0].id')

curl -s -X POST "$BASE/v1/subscriptions" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"plan_id\":\"$PLAN_ID\"}" | jq

DEVICE_RESPONSE=$(curl -s -X POST "$BASE/v1/me/devices" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Pilot Desktop","platform":"desktop"}')

DEVICE_ID=$(echo "$DEVICE_RESPONSE" | jq -r '.id')
NODE_ID=$(curl -s "$BASE/v1/locations" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.nodes[0].id')

echo "device=$DEVICE_ID node=$NODE_ID"
```

Если `NODE_ID` пустой, значит в Core пока нет node. Нужно выполнить node enrollment из следующего шага.

## 12. Node enrollment для пилота

Создать enrollment token:

```bash
docker compose run --rm wavebreak-api \
  wavebreak-cli node token --region NL --ttl 24h
```

Скопировать токен из вывода:

```text
node enrollment token: <TOKEN>
```

Запустить node-agent profile:

```bash
WAVEBREAK_NODE_ENROLLMENT_TOKEN='<TOKEN>' \
WAVEBREAK_NODE_CODE='NL-PILOT-01' \
WAVEBREAK_NODE_REGION='NL' \
docker compose --profile node up -d --build wavebreak-node
```

Проверить heartbeat:

```bash
docker compose logs --tail=100 wavebreak-node
curl -s http://127.0.0.1:18080/v1/locations \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq
```

После появления online node можно создать grant:

```bash
NODE_ID=$(curl -s "$BASE/v1/locations" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.nodes[0].id')

GRANT_RESPONSE=$(curl -s -X POST "$BASE/v1/access/grants" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"node_id\":\"$NODE_ID\",\"device_id\":\"$DEVICE_ID\",\"protocol\":\"wireguard\"}")

GRANT_ID=$(echo "$GRANT_RESPONSE" | jq -r '.id')

curl -s "$BASE/v1/access/grants/$GRANT_ID/config" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq
```

На текущем этапе ожидаемый config status:

```json
{
  "config_status": "pending_runtime_config"
}
```

Это нормально: реальная генерация VPN config будет следующим backend pass.

## 13. Reverse proxy и домены

Для пилота без домена этот шаг можно пропустить.

Если есть домены, проще всего поставить Caddy на host:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Пример `/etc/caddy/Caddyfile`:

```text
app-pilot.example.com {
    reverse_proxy 127.0.0.1:8000
}

admin-pilot.example.com {
    reverse_proxy 127.0.0.1:8002
}

api-pilot.example.com {
    reverse_proxy 127.0.0.1:18080
}

grafana-pilot.example.com {
    reverse_proxy 127.0.0.1:13000
}
```

Проверить и перезагрузить:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

После этого приложение mobile/desktop должно использовать:

```text
https://api-pilot.example.com
```

## 14. Backup PostgreSQL для пилота

Создать директорию:

```bash
mkdir -p /opt/wavebreak-pilot/backups
```

Простой backup через контейнер PostgreSQL:

```bash
cd /opt/wavebreak-pilot/current/wavebreak-infrastructure

docker compose exec -T postgres pg_dump \
  -U wavebreak \
  -d wavebreak \
  --format=custom \
  | gzip -9 > /opt/wavebreak-pilot/backups/wavebreak-$(date -u +%Y%m%d%H%M%S).dump.gz
```

Проверить:

```bash
ls -lh /opt/wavebreak-pilot/backups
```

## 15. Обновление пилота

Перед обновлением:

```bash
cd /opt/wavebreak-pilot/current/wavebreak-infrastructure
docker compose ps
```

Backup:

```bash
docker compose exec -T postgres pg_dump \
  -U wavebreak \
  -d wavebreak \
  --format=custom \
  | gzip -9 > /opt/wavebreak-pilot/backups/wavebreak-before-update-$(date -u +%Y%m%d%H%M%S).dump.gz
```

Обновить код:

```bash
cd /opt/wavebreak-pilot/current
git pull --ff-only
```

Пересобрать и поднять:

```bash
cd /opt/wavebreak-pilot/current/wavebreak-infrastructure
docker compose up -d --build wavebreak-migrate wavebreak-api wavebreak-worker wavebreak-web wavebreak-admin
docker compose ps
curl -s http://127.0.0.1:18080/readyz | jq
```

## 16. Откат

Посмотреть историю:

```bash
cd /opt/wavebreak-pilot/current
git log --oneline -10
```

Откатить код на предыдущий commit:

```bash
git checkout <COMMIT_SHA>
cd wavebreak-infrastructure
docker compose up -d --build wavebreak-api wavebreak-worker wavebreak-web wavebreak-admin
```

Если миграции уже применились вперед, простой code rollback может быть недостаточен. Для серьезного rollback использовать DB backup.

## 17. Остановка пилота

Остановить контейнеры, но сохранить volumes:

```bash
cd /opt/wavebreak-pilot/current/wavebreak-infrastructure
docker compose down
```

Полностью удалить контейнеры и volumes пилота:

```bash
docker compose down -v
```

Внимание: `down -v` удалит PostgreSQL/Grafana volumes этого compose project.

## 18. Что я могу сделать сам, если дать доступ

Я могу зайти и развернуть пилот сам, не затрагивая остальное, если дать:

- IP сервера;
- SSH user;
- способ входа: SSH key или временный пароль;
- есть ли у пользователя `sudo`;
- домен/поддомены, если хотим HTTPS сразу;
- разрешение устанавливать Docker/Caddy/UFW;
- какие порты можно открыть наружу.

Безопаснее всего:

- создать временного пользователя `wavebreakdeploy`;
- добавить SSH key;
- дать ему `sudo`;
- после деплоя удалить пользователя или отключить доступ.

Я буду работать только в:

```text
/opt/wavebreak-pilot
```

И не буду трогать существующие папки/проекты без отдельного подтверждения.

## 19. Pilot acceptance checklist

Пилот считается поднятым, если:

- `docker compose ps` показывает все основные сервисы `Up`;
- `GET /readyz` Core возвращает `ready`;
- Web открывается;
- Admin открывается;
- создан superadmin;
- тестовый user регистрируется;
- `GET /v1/client/bootstrap` работает;
- создается subscription;
- создается device;
- node появляется online;
- создается access grant с `device_id`;
- `GET /v1/access/grants/{grantID}/config` возвращает `pending_runtime_config`;
- Grafana открывается;
- есть хотя бы один PostgreSQL backup.
