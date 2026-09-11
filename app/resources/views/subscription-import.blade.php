<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Auralith | Импорт подписки</title>
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Montserrat:wght@600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #0a0f18;
            --surface: #111a2a;
            --text: #e6ebf3;
            --muted: #8a94a6;
            --line: rgba(138, 148, 166, .26);
            --accent: #4f7eb5;
            --accent-2: #6b93c0;
            --green: #4ade80;
        }

        * { box-sizing: border-box; }

        body {
            min-height: 100vh;
            margin: 0;
            font-family: "Inter", sans-serif;
            color: var(--text);
            background:
                radial-gradient(circle at 90% 4%, rgba(79,126,181,.2), transparent 30%),
                radial-gradient(circle at 0% 92%, rgba(74,222,128,.08), transparent 30%),
                var(--bg);
        }

        .wrap {
            width: min(720px, 92vw);
            margin: 36px auto;
        }

        .brand {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            margin-bottom: 18px;
            color: var(--text);
            text-decoration: none;
            font-family: "Montserrat", sans-serif;
            font-weight: 700;
        }

        .brand img {
            width: 42px;
            height: 42px;
            border-radius: 10px;
            padding: 5px;
            background: #fff;
        }

        .card {
            border: 1px solid var(--line);
            border-radius: 18px;
            padding: 24px;
            background: linear-gradient(180deg, rgba(17,26,42,.9), rgba(10,15,24,.96));
            box-shadow: 0 24px 80px rgba(0,0,0,.28);
        }

        .eyebrow {
            margin: 0 0 8px;
            color: #9bb9dc;
            font-size: .76rem;
            font-weight: 700;
            letter-spacing: .08em;
            text-transform: uppercase;
        }

        h1 {
            margin: 0 0 8px;
            font-family: "Montserrat", sans-serif;
            font-size: clamp(1.65rem, 6vw, 2.25rem);
        }

        .lead {
            margin: 0 0 18px;
            color: #b7c5d8;
            line-height: 1.5;
        }

        .url-box {
            display: grid;
            gap: 8px;
            margin-bottom: 18px;
        }

        .url-box span {
            color: var(--muted);
            font-size: .82rem;
        }

        .url-box code {
            display: block;
            overflow-wrap: anywhere;
            border: 1px solid rgba(138,148,166,.28);
            border-radius: 12px;
            padding: 11px 12px;
            background: rgba(5,9,16,.72);
            color: #cfe3ff;
            font-size: .86rem;
        }

        .apps {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 12px;
            margin-bottom: 16px;
        }

        .app-card {
            min-width: 0;
            border: 1px solid rgba(138,148,166,.22);
            border-radius: 14px;
            padding: 14px;
            background: rgba(8,12,20,.54);
        }

        .app-card strong {
            display: block;
            margin-bottom: 10px;
            font-family: "Montserrat", sans-serif;
        }

        .import-btn {
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 40px;
            border-radius: 10px;
            background: linear-gradient(135deg, var(--accent), var(--accent-2));
            color: #f7fbff;
            text-decoration: none;
            font-weight: 700;
        }

        .fallback {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-top: 10px;
        }

        .fallback a {
            color: #9ec3ee;
            font-size: .78rem;
            text-decoration: none;
        }

        .note {
            margin: 0;
            border: 1px solid rgba(251,191,36,.26);
            border-radius: 12px;
            padding: 12px;
            background: rgba(251,191,36,.06);
            color: #d8c998;
            font-size: .86rem;
            line-height: 1.45;
        }

        .raw-link {
            display: inline-flex;
            margin-top: 14px;
            color: var(--muted);
            font-size: .84rem;
        }

        @media (max-width: 720px) {
            .wrap { margin: 22px auto; }
            .card { padding: 18px; }
            .apps { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
<main class="wrap">
    <a href="{{ route('home') }}" class="brand">
        <img src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="Auralith">
        <span>Auralith</span>
    </a>

    <section class="card">
        <p class="eyebrow">Импорт подписки</p>
        <h1>Откройте конфигурацию в приложении</h1>
        <p class="lead">Выберите установленный клиент. Браузер передаст ссылку приложению, а подписка добавится автоматически.</p>

        <div class="url-box">
            <span>Subscription URL · {{ $nodeName }}</span>
            <code>{{ $subscriptionUrl }}</code>
        </div>

        <div class="apps">
            @foreach($apps as $app)
                <article class="app-card">
                    <strong>{{ $app['name'] }}</strong>
                    <a class="import-btn" href="{{ $app['href'] }}">Открыть</a>
                    <div class="fallback">
                        <a href="{{ $app['ios'] }}" target="_blank" rel="noopener">App Store</a>
                        <a href="{{ $app['android'] }}" target="_blank" rel="noopener">Google Play</a>
                    </div>
                </article>
            @endforeach
        </div>

        <p class="note">Если приложение не установлено, кнопка импорта может ничего не открыть. Установите клиент через App Store или Google Play, затем вернитесь на эту страницу.</p>
        <a class="raw-link" href="{{ $rawUrl }}">Открыть raw-конфигурацию</a>
    </section>
</main>
</body>
</html>
