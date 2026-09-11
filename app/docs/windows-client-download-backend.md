# Auralith Windows Client Downloads

## Цель

Нужно отдать Windows-клиент Auralith и `latest.json` с сервера так, чтобы личный кабинет мог показывать кнопку скачивания на десктопе.

На стороне Laravel в личном кабинете уже ожидаются публичные пути:

- `/downloads/windows/Auralith_Installer.exe`
- `/downloads/windows/latest.json`

Физически файлы лежат на сервере:

```text
/opt/auralith/downloads/windows
```

## Что нужно положить на сервер

Минимальный набор:

```text
/opt/auralith/downloads/windows/AuralithSetup.exe
/opt/auralith/downloads/windows/Auralith_Installer.exe
/opt/auralith/downloads/windows/latest.json
```

Назначение файлов:

```text
AuralithSetup.exe        стандартный установщик
Auralith_Installer.exe   кастомный установщик, именно его скачивает кнопка в ЛК
latest.json              версия с автообновлениями, пока информативно
```

Рекомендуемо также хранить версионированный установщик:

```text
/opt/auralith/downloads/windows/Auralith-1.0.0-installer.exe
```

## Формат latest.json

```json
{
  "app": "Auralith",
  "platform": "windows",
  "channel": "stable",
  "version": "1.0.0",
  "build": 1,
  "required": false,
  "published_at": "2026-05-15T12:00:00+03:00",
  "download_url": "https://auralith.ru/downloads/windows/Auralith_Installer.exe",
  "file_name": "Auralith_Installer.exe",
  "sha256": "",
  "size_bytes": 0,
  "notes": [
    "Вход в приложение через сайт Auralith",
    "Поддержка polling-авторизации по session_key"
  ]
}
```

Поля:

- `version` — версия, которую видит пользователь и клиент.
- `build` — числовая сборка для сравнения обновлений.
- `required` — если `true`, клиент должен требовать обновление.
- `download_url` — публичная ссылка на установщик.
- `sha256` — желательно заполнить контрольную сумму файла.
- `size_bytes` — желательно заполнить размер файла.

## Nginx

Нужно отдать директорию как публичную статику:

```nginx
location /downloads/windows/ {
    alias /opt/auralith/downloads/windows/;
    try_files $uri =404;

    add_header Cache-Control "public, max-age=300";
    add_header X-Content-Type-Options "nosniff";
}
```

Для `latest.json` лучше короткий cache:

```nginx
location = /downloads/windows/latest.json {
    alias /opt/auralith/downloads/windows/latest.json;
    default_type application/json;
    add_header Cache-Control "no-cache";
    add_header X-Content-Type-Options "nosniff";
}
```

После изменения nginx:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Проверка

```bash
curl -I https://auralith.ru/downloads/windows/latest.json
curl -I https://auralith.ru/downloads/windows/Auralith_Installer.exe
curl https://auralith.ru/downloads/windows/latest.json
```

Ожидаем:

- `latest.json` отдаёт `200 OK` и `Content-Type: application/json`.
- `.exe` отдаёт `200 OK`.
- если файла нет, должен быть `404`, не редирект на Laravel.

## Связь с админкой Laravel

В админском дашборде есть блок версий клиента. Для стабильного канала укажите:

```text
Версия: 1.0.0
Путь загрузки: /downloads/windows/Auralith_Installer.exe
latest.json: /downloads/windows/latest.json
```

Личный кабинет берёт стабильный канал из таблицы `client_releases`. Если таблица ещё не заполнена, используется fallback:

```text
/downloads/windows/Auralith_Installer.exe
```

## Важно

Пока показываем кнопку скачивания только на десктопной версии личного кабинета. На мобильной версии блок скрыт через CSS.
