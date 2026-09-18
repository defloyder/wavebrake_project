@extends('layout')

@section('title', 'Скачать WAVEBREAK')
@section('description', 'Приложения WAVEBREAK для смартфона и компьютера. Аккаунт, тарифы, подключения и устройства управляются внутри приложения.')
@section('body_class', 'wb-shell wb-public')

@section('content')
@include('partials.public-header', ['active' => 'download'])

<main class="download-page">
    <section class="download-hero">
        <div class="wb-container download-layout">
            <div class="download-copy">
                <p class="wb-kicker">Приложения WAVEBREAK</p>
                <h1>Всё управление — на вашем устройстве.</h1>
                <p class="wb-lead">Создание аккаунта, тариф, подключения и статистика будут доступны в мобильном и десктопном приложениях.</p>
            </div>

            <div class="download-options" aria-label="Доступные платформы">
                <article class="download-option">
                    <span class="download-platform">Windows</span>
                    <strong>Для компьютера</strong>
                    <p>Управление подключением и рабочими профилями с одного экрана.</p>
                    <button class="wb-btn wb-btn--primary" type="button" disabled>Скоро</button>
                </article>
                <article class="download-option">
                    <span class="download-platform">Android и iOS</span>
                    <strong>Для смартфона</strong>
                    <p>Аккаунт, тариф и подключение всегда под рукой.</p>
                    <button class="wb-btn" type="button" disabled>Скоро</button>
                </article>
            </div>

            <p class="download-note">Ссылки появятся здесь после публикации сборок.</p>
        </div>
    </section>
</main>
@endsection
