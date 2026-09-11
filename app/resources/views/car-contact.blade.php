@php
    $whatsappPhone = $contact['whatsapp_phone'] ?? ltrim($contact['phone_e164'], '+');
    $encodedMessage = rawurlencode($message);
    $mailSubject = rawurlencode('По поводу машины');
    $mailBody = rawurlencode($message);
@endphp
<!doctype html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="robots" content="noindex, nofollow">
    <meta name="theme-color" content="#101419">
    <title>Связаться с владельцем авто</title>
    <link rel="icon" type="image/png" sizes="32x32" href="{{ asset('images/favicon-32.png') }}?v=brand4">
    <link rel="apple-touch-icon" sizes="180x180" href="{{ asset('images/apple-touch-icon.png') }}?v=brand4">
    <link rel="stylesheet" href="{{ asset('css/car-contact.css') }}?v=2">
</head>
<body class="car-contact car-contact--{{ $contact['accent'] }}">
    <main class="car-contact__shell" aria-labelledby="contact-title">
        <section class="car-contact__panel">
            <header class="car-contact__header">
                <div class="car-contact__brand" aria-label="Auralith">
                    <img class="car-contact__logo" src="{{ asset('images/logo-mark.png') }}?v=brand4" alt="" width="48" height="48">
                    <span>Auralith</span>
                </div>
                <p class="car-contact__kicker">Контакт владельца</p>
                <h1 id="contact-title">Если машина мешает, напишите или позвоните</h1>
            </header>

            <a class="car-contact__call" href="tel:{{ $contact['phone_e164'] }}" aria-label="Позвонить {{ $contact['phone_pretty'] }}">
                <span class="car-contact__call-icon" aria-hidden="true">
                    <svg viewBox="0 0 24 24">
                        <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.9.33 1.77.63 2.61a2 2 0 0 1-.45 2.11L8.02 9.71a16 16 0 0 0 6.27 6.27l1.27-1.27a2 2 0 0 1 2.11-.45c.84.3 1.71.51 2.61.63A2 2 0 0 1 22 16.92Z"/>
                    </svg>
                </span>
                <span>
                    <strong>Позвонить</strong>
                    <em>{{ $contact['phone_pretty'] }}</em>
                </span>
            </a>

            <nav class="car-contact__actions" aria-label="Способы связи">
                <a class="car-contact__action car-contact__action--whatsapp" href="https://wa.me/{{ $whatsappPhone }}?text={{ $encodedMessage }}">
                    <svg viewBox="0 0 24 24" aria-hidden="true">
                        <path d="M20.52 3.48A11.82 11.82 0 0 0 12.08 0C5.49 0 .14 5.35.14 11.94c0 2.1.55 4.15 1.6 5.95L0 24l6.25-1.64a11.93 11.93 0 0 0 5.83 1.48h.01c6.58 0 11.94-5.35 11.94-11.94 0-3.19-1.24-6.19-3.51-8.42Zm-8.43 18.34h-.01a9.9 9.9 0 0 1-5.04-1.38l-.36-.21-3.71.97.99-3.61-.23-.37a9.86 9.86 0 0 1-1.51-5.28c0-5.45 4.43-9.88 9.88-9.88 2.64 0 5.12 1.03 6.98 2.9a9.8 9.8 0 0 1 2.89 6.98c0 5.45-4.43 9.88-9.88 9.88Zm5.42-7.4c-.3-.15-1.76-.87-2.03-.97-.27-.1-.47-.15-.67.15-.2.3-.77.97-.94 1.17-.17.2-.35.22-.65.08-.3-.15-1.25-.46-2.38-1.47-.88-.78-1.47-1.75-1.64-2.05-.17-.3-.02-.46.13-.6.13-.13.3-.35.45-.52.15-.17.2-.3.3-.5.1-.2.05-.37-.03-.52-.08-.15-.67-1.62-.92-2.22-.24-.58-.49-.5-.67-.51h-.57c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.49s1.07 2.88 1.22 3.08c.15.2 2.1 3.21 5.1 4.5.71.31 1.27.49 1.7.63.72.23 1.37.2 1.88.12.57-.09 1.76-.72 2.01-1.42.25-.7.25-1.29.17-1.42-.07-.13-.27-.2-.57-.35Z"/>
                    </svg>
                    <span>WhatsApp</span>
                </a>
                @if(! empty($contact['telegram']))
                    <a class="car-contact__action car-contact__action--telegram" href="https://t.me/{{ $contact['telegram'] }}">
                        <svg viewBox="0 0 24 24" aria-hidden="true">
                            <path d="M21.94 4.13 18.62 19.8c-.25 1.1-.9 1.37-1.83.85l-5.05-3.72-2.44 2.35c-.27.27-.5.5-1.02.5l.36-5.14 9.36-8.45c.41-.36-.09-.56-.63-.2L5.8 13.29.82 11.73c-1.08-.34-1.1-1.08.23-1.6L20.5 2.64c.9-.34 1.69.2 1.44 1.49Z"/>
                        </svg>
                        <span>Телеграм</span>
                    </a>
                @endif
                @if(! empty($contact['email']))
                    <a class="car-contact__action car-contact__action--mail" href="mailto:{{ $contact['email'] }}?subject={{ $mailSubject }}&body={{ $mailBody }}">
                        <svg viewBox="0 0 24 24" aria-hidden="true">
                            <path d="M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Zm0 4.2 8 5 8-5V6l-8 5-8-5v2.2Z"/>
                        </svg>
                        <span>{{ $contact['email'] }}</span>
                    </a>
                @endif
            </nav>
        </section>
    </main>
</body>
</html>
