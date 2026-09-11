@extends('admin.layout')

@section('title', 'Авто QR '.$card->phone_pretty)

@section('content')
<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;gap:12px;flex-wrap:wrap">
    <div>
        <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Auto</p>
        <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">{{ $card->phone_pretty }}</h2>
    </div>
    <div style="display:flex;gap:10px;flex-wrap:wrap">
        <a class="adm-btn adm-btn-sm" href="{{ route('admin.car-cards.create') }}" style="text-decoration:none">+ Ещё карточка</a>
        <a class="adm-btn adm-btn-sm" href="{{ route('admin.car-cards.index') }}" style="text-decoration:none;background:rgba(138,148,166,.15);color:var(--text)">Список</a>
    </div>
</div>

<div class="car-result-layout">
    <div class="adm-card car-result-card">
        <div class="car-result-main">
            <div class="car-result-list">
                <div>
                    <span>Страница клиента</span>
                    <a href="{{ $card->pageUrl() }}" target="_blank" rel="noopener">{{ $card->pageUrl() }}</a>
                </div>
                <div>
                    <span>QR PNG</span>
                    @if($card->qrUrl())
                        <a href="{{ $card->qrUrl() }}" target="_blank" rel="noopener">{{ $card->qrUrl() }}</a>
                    @else
                        <em>не сгенерирован</em>
                    @endif
                </div>
                <div>
                    <span>Макет PNG</span>
                    @if($card->cardUrl())
                        <a href="{{ $card->cardUrl() }}" target="_blank" rel="noopener">{{ $card->cardUrl() }}</a>
                    @else
                        <em>не сгенерирован</em>
                    @endif
                </div>
            </div>

            <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:18px">
                <a class="adm-btn adm-btn-sm" href="{{ $card->pageUrl() }}" target="_blank" rel="noopener" style="text-decoration:none">Открыть страницу</a>
                @if($card->qrUrl())
                    <a class="adm-btn adm-btn-sm" href="{{ $card->qrUrl() }}" download style="text-decoration:none">Скачать QR</a>
                @endif
                @if($card->cardUrl())
                    <a class="adm-btn adm-btn-sm" href="{{ $card->cardUrl() }}" download style="text-decoration:none">Скачать макет</a>
                @endif
                <form method="post" action="{{ route('admin.car-cards.regenerate', $card) }}">
                    @csrf
                    <button class="adm-btn adm-btn-sm" type="submit" style="background:rgba(138,148,166,.15);color:var(--text)">Пересобрать</button>
                </form>
                <form method="post" action="{{ route('admin.car-cards.destroy', $card) }}" onsubmit="return confirm('Удалить эту запись вместе с QR и макетом?')">
                    @csrf
                    @method('DELETE')
                    <button class="adm-btn adm-btn-sm" type="submit" style="background:rgba(248,113,113,.12);border-color:rgba(248,113,113,.35);color:#fecaca">Удалить</button>
                </form>
            </div>
        </div>

        @if($card->cardUrl())
            <div class="car-card-preview">
                <button class="car-card-preview__button" type="button" onclick="openCarCardPreview()" aria-label="Открыть макет карточки">
                    <img src="{{ $card->cardUrl() }}?v={{ $card->updated_at?->timestamp }}" alt="Макет карточки">
                </button>
            </div>
        @endif
    </div>
</div>

@if($card->cardUrl())
    <div class="car-card-lightbox" id="car-card-lightbox" hidden>
        <button class="car-card-lightbox__backdrop" type="button" onclick="closeCarCardPreview()" aria-label="Закрыть просмотр"></button>
        <div class="car-card-lightbox__panel" role="dialog" aria-modal="true" aria-label="Просмотр макета карточки">
            <button class="car-card-lightbox__close" type="button" onclick="closeCarCardPreview()" aria-label="Закрыть просмотр">×</button>
            <img src="{{ $card->cardUrl() }}?v={{ $card->updated_at?->timestamp }}" alt="Макет карточки">
        </div>
    </div>
@endif

<style>
    .car-result-layout {
        display:grid;
        gap:18px;
    }
    .car-result-card {
        display:grid;
        grid-template-columns:minmax(0, 1fr) minmax(340px, 520px);
        gap:22px;
        align-items:start;
    }
    .car-result-main {
        min-width:0;
    }
    .car-card-preview {
        align-self:start;
    }
    .car-card-preview__button {
        display:block;
        width:100%;
        padding:0;
        border:0;
        border-radius:12px;
        background:transparent;
        cursor:zoom-in;
    }
    .car-card-preview img {
        display:block;
        width:100%;
        border-radius:10px;
        border:1px solid var(--line);
        box-shadow:0 18px 42px rgba(0,0,0,.26);
    }
    .car-result-list {
        display:grid;
        gap:12px;
    }
    .car-result-list div {
        display:grid;
        gap:4px;
        padding:12px;
        border:1px solid var(--line);
        border-radius:12px;
        background:rgba(8,13,22,.5);
    }
    .car-result-list span {
        color:var(--muted);
        font-size:.76rem;
        font-weight:800;
        letter-spacing:.06em;
        text-transform:uppercase;
    }
    .car-result-list a {
        color:var(--accent-2);
        word-break:break-all;
    }
    .car-card-lightbox {
        position:fixed;
        inset:0;
        z-index:1200;
        display:grid;
        place-items:center;
        padding:24px;
    }
    .car-card-lightbox[hidden] {
        display:none;
    }
    .car-card-lightbox__backdrop {
        position:absolute;
        inset:0;
        border:0;
        background:rgba(1,6,14,.86);
        backdrop-filter:blur(10px);
        cursor:zoom-out;
    }
    .car-card-lightbox__panel {
        position:relative;
        z-index:1;
        width:min(96vw, 1280px);
    }
    .car-card-lightbox__panel img {
        display:block;
        width:100%;
        max-height:86vh;
        object-fit:contain;
        border-radius:16px;
        border:1px solid rgba(107,147,192,.34);
        box-shadow:0 26px 80px rgba(0,0,0,.55);
    }
    .car-card-lightbox__close {
        position:absolute;
        top:-14px;
        right:-14px;
        z-index:2;
        width:38px;
        height:38px;
        border-radius:50%;
        border:1px solid rgba(180,210,247,.3);
        background:rgba(8,13,22,.92);
        color:#fff;
        font-size:26px;
        line-height:1;
        cursor:pointer;
    }
    @media (max-width: 700px) {
        .car-result-card {
            grid-template-columns:1fr;
        }
        .car-card-preview {
            width:100%;
        }
        .car-card-lightbox {
            padding:12px;
        }
        .car-card-lightbox__close {
            top:8px;
            right:8px;
        }
    }
</style>
<script>
    function openCarCardPreview() {
        const modal = document.getElementById('car-card-lightbox');
        if (!modal) return;
        modal.hidden = false;
        document.body.style.overflow = 'hidden';
    }

    function closeCarCardPreview() {
        const modal = document.getElementById('car-card-lightbox');
        if (!modal) return;
        modal.hidden = true;
        document.body.style.overflow = '';
    }

    document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape') {
            closeCarCardPreview();
        }
    });
</script>
@endsection
