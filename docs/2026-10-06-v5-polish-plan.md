# V5: доводка (П1–П17) — фаза 0, аудит и план

Дата: 06.10.2026. Ветка `app-main-sync`. Владелец попросил работать без остановок между
фазами; остановки только перед деплоем на сервер, миграцией боевой БД и публикацией.

## Как проверяем вёрстку без эмулятора

Эмулятора на машине нет, телефон не всегда подключён. Сделан стенд скриншотов:
`wavebreak-mobile/test_screens/screens_test.dart` — настоящее приложение (подменный Core,
вход выполнен) рендерится в `flutter test` на 320×568, 360×640, 412×915 (textScale 1.0 и 1.3)
и 800×1280 / 1280×800, PNG — в `test_screens/out/` (в git не кладутся). Шрифты настоящие
(Inter, Noto Serif как «serif»). Шейдер сферы под flutter_tester не работает — там простая
сфера. Стенд падает на переполнениях раскладки → служит автоматической проверкой П4.

```bash
cd wavebreak-mobile && flutter test test_screens --update-goldens
WB_SHOTS=home,settings WB_SIZES=320x568 flutter test test_screens --update-goldens
```

«До»: 136 снимков. Падают (переполнения или ListTile в цветной подложке без Material):
все страницы настроек на всех телефонных размерах; главная на 320×568 — кнопки шапки
наезжают на логотип, подпись «Настройки» в баре обрезана, карточка сессии под баром.

## Карта по пунктам

| П | Где |
|---|---|
| П1 Windows белое окно | `wavebreak-pc/lib/main.dart`, `app/bootstrap.dart`, `windows/runner/*.cpp`, `windows/installer/wavebreak.iss` (VC++ рантайм не кладётся) |
| П2 затемнение под сферой | `features/home/home_screen.dart` (мобильное тело), `home_vitals.dart` (`SessionPanel`, `_GlassCard`) |
| П3a/П3b переключение | см. ниже |
| П3c логотип сферы | `features/immersive/living_core.dart` `_emblem` (векторная W) → знак `assets/branding/wavebreak_mark_square.png` (`WavebreakMark`), как был на `ConnectButton` до `ef90df6` |
| П3d логи в метриках | `features/metrics/metrics_tabs.dart` `LogsTab`, вкладки в `metrics_screen.dart`; экспорт остаётся в `settings/support_screen.dart` |
| П3e/П4 вход и малые экраны | `features/auth/welcome_screen.dart`, `login_screen.dart`, `home/home_screen.dart`, `home_vitals.dart`, `shell/app_shell.dart` |
| П5 сфера | `features/immersive/living_core.dart` |
| П6/П8 настройки | `features/settings/*` (11 пунктов верхнего уровня), `shared/detail_scaffold.dart`, `shared/wb_card.dart` |
| П7 нижний бар | `features/shell/app_shell.dart` (мобильный бар) |
| П9 тарифы/промокоды | `features/subscription/subscription_screen.dart`, Core `/v1/plans`, `/v1/subscriptions` |
| П10 серверы | `features/locations/locations_screen.dart`, `shared/subscription_accordion.dart` |
| П11 протоколы в шапке | `features/home/location_bar.dart` |
| П12 главная | `home_screen.dart` (секции подписки, выбора локации) |
| П13 блокировка | `shared/app_lock_gate.dart`, `settings/pin_verify_screen.dart`, `shared/pin_keypad.dart`, `services/biometric/biometric_service.dart` |
| П14/П15 | `settings/support_screen.dart`, `settings/about_screen.dart` |
| П16 персонализация | `settings/personalization_screen.dart`, `core/theme/personalization_controller.dart` |
| П17 сторонние подписки | `services/custom_servers/*` (уже есть: ссылки, base64, URL-подписки) |

## Где сейчас меняется локация/протокол

1. Шапка главной: строка сервера → своё выпадающее окно (`showLocationSheet`).
2. Шапка главной: сегменты Direct / Hysteria2 (`LocationBar`).
3. Низ главной: аккордеон серверов (`SubscriptionAccordion` в `home_screen.dart`).
4. Вкладка «Серверы» (`LocationsScreen`).
5. Уведомление VPN: «Сменить сервер» (окно `LocationPickerActivity`) и «⇄ протокол».
6. Подсказка «нет трафика»: кнопка «Попробовать другой протокол».
7. Плитка быстрых настроек — только вкл/выкл (не выбор).

Все пути в итоге вызывают `ConnectionManager.selectLocation` — путь подключения один.
Различаются **объекты локаций**: сегменты шапки строились из списка WAVEBREAK по стране
(узлы Core + личные ссылки вперемешку), а для своих серверов шапка показывала протоколы
Стамбула WAVEBREAK вместо протоколов текущего сервера. Причину «VLESS не взлетает из
шапки» без журнала с телефона владельца точно не назвать — делаем один каталог серверов
(место → протоколы), из которого берут и шапка, и «Серверы», и тест, что оба места
выбирают один и тот же объект.

После П3b остаются: шапка (только протокол; строка сервера ведёт во вкладку «Серверы») и
вкладка «Серверы». Убираются: своё окно выбора в шапке, аккордеон внизу главной, кнопки
уведомления и `LocationPickerActivity`, кнопка «Попробовать другой протокол» (текст
подсказки остаётся и указывает на переключатель в шапке).

## Переводы

Языки: en, ru, es, de, fr, pt, tr. Ключи `AppStrings` обязательны во всех 7 (иначе не
соберётся), значений, совпадающих с английским, единицы (единицы измерения — нормально).
Проблема — захардкоженный текст мимо `AppStrings`:
- `metrics/metrics_screen.dart` ~20, `metrics/metrics_tabs.dart` ~30 (весь экран метрик — RU);
- `home/home_vitals.dart`: «мс», «Задержка», «Загрузка», «Сессия», «↓ Приём», «↑ Отдача»;
- `metrics/metrics_chart.dart`: «мин», «сейчас»;
- `shared/subscription_accordion.dart`: «Auto · Fastest» (EN).
Фаза 7: тест, который падает на кириллице/латинице в виджетах мимо `AppStrings`.

## Новая структура настроек (П6)

Сейчас 11 пунктов верхнего уровня. Станет 6 групп:

| Группа | Внутри |
|---|---|
| Аккаунт | почта, подписка и тарифы, промокод, устройства, выход |
| Подключение | автоподключение и т. п. (connection), блокировка без VPN, кнопка в шторке, батарея |
| Безопасность | PIN, биометрия, блокировка приложения |
| Оформление | язык, акцент, стиль сферы, фон, плотность, размер текста, анимации, качество эффектов |
| Уведомления | как сейчас |
| Помощь | поддержка (диагностика), обновления, о приложении |

Внутренние страницы — общие компоненты: `SettingsPage` (заголовок + назад),
`SettingsGroup` (подпись + стеклянный блок), `SettingsRow` (иконка, текст, значение,
шеврон), `SettingsSwitch`, `SettingsFooter`.

## Персонализация (П16) — предлагаемый список

1. Акцент (есть): авто по флагу / фиксированные цвета.
2. Стиль сферы: «Земля» (как сейчас) / «Стекло» (без текстуры) / «Минимум» (кольцо).
3. Интенсивность фона: тихий / обычный / яркий (число и яркость волн).
4. Плотность интерфейса: обычная / компактная.
5. Размер текста (есть), меньше анимации (есть), качество эффектов (есть).
Всё работает и на «Экономии».

## Порядок работ

Фаза 1 (П1, П3a–e, П2, П4, П7) → фаза 2 (П5) → фаза 3 (цвет, П6, П8, П10–П15) →
фаза 4 (П9; деплой Core и миграция — с «ок») → фаза 5 (П17) → фаза 6 (П16) → фаза 7
(переводы, проверка, сборка). Итоги и состояние — `docs/PROJECT-STATE.md`.
