# WAVEBREAK Web

Публичный сайт WAVEBREAK: главная, тарифы, технология и приложения.

Клиентского веб-кабинета нет. Регистрация, вход, подписки и устройства находятся
в мобильном и десктопном приложениях. Старые адреса кабинета перенаправляются на
`/download`; форм изменения клиентских данных сайт не содержит.

Все четыре страницы используют общий layout, шапку, футер, стили
`public/css/wavebreak-site.css` и анимацию `public/js/wavebreak-motion.js`.
Тарифы загружаются из API: при ошибке нет подставных цен.
Ссылки загрузки пока отключены и обозначены «Скоро».

The application calls `wavebreak-core` through HTTP only. It does not own or migrate Core tables.

## Local

```bash
composer install
php artisan serve --host=0.0.0.0 --port=8000
```

Set:

```text
WAVEBREAK_CORE_URL=http://localhost:8080
```
