@extends('admin.layout')

@section('title', 'Авто QR')

@section('content')
<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px;gap:12px;flex-wrap:wrap">
    <div>
        <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">Auralith Auto</p>
        <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">Авто QR-карточки</h2>
    </div>
    <a class="adm-btn adm-btn-sm" href="{{ route('admin.car-cards.create') }}" style="text-decoration:none">+ Создать карточку</a>
</div>

<div class="car-card-groups">
    @forelse($groupedCards as $phone => $cards)
        @php
            $latest = $cards->first();
        @endphp
        <section class="adm-card car-card-group">
            <div class="car-card-group__head">
                <div>
                    <strong>{{ $latest->phone_pretty }}</strong>
                </div>
            </div>

            <div class="car-card-group__rows">
                @foreach($cards as $card)
                    <article class="car-card-row">
                        <div>
                            <strong>{{ $card->slug }}</strong>
                            <span>
                                WhatsApp: {{ $card->whatsapp_phone ?: $card->phone }}
                                @if($card->telegram)
                                    · Telegram: {{ '@'.$card->telegram }}
                                @endif
                                @if($card->email)
                                    · {{ $card->email }}
                                @endif
                            </span>
                        </div>
                        <div class="car-card-row__meta">
                            <span>{{ $card->created_at?->format('d.m.Y H:i') }}</span>
                        </div>
                        <div class="car-card-row__actions">
                            <a class="adm-btn adm-btn-sm" href="{{ route('admin.car-cards.show', $card) }}" style="text-decoration:none">Открыть</a>
                            <form method="post" action="{{ route('admin.car-cards.destroy', $card) }}" onsubmit="return confirm('Удалить эту запись вместе с QR и макетом?')">
                                @csrf
                                @method('DELETE')
                                <button class="adm-btn adm-btn-sm car-card-delete" type="submit">Удалить</button>
                            </form>
                        </div>
                    </article>
                @endforeach
            </div>
        </section>
    @empty
        <div class="adm-card adm-empty-table">Карточек пока нет</div>
    @endforelse
</div>

<style>
    .car-card-groups {
        display:grid;
        gap:14px;
    }
    .car-card-group {
        padding:18px;
    }
    .car-card-group__head,
    .car-card-row {
        display:grid;
        grid-template-columns:minmax(0, 1fr) auto;
        gap:12px;
        align-items:center;
    }
    .car-card-group__head {
        margin-bottom:12px;
    }
    .car-card-group__head strong {
        display:block;
        font-size:1.05rem;
    }
    .car-card-group__head span,
    .car-card-row span {
        color:var(--muted);
        font-size:.82rem;
    }
    .car-card-group__rows {
        display:grid;
        gap:8px;
    }
    .car-card-row {
        grid-template-columns:minmax(240px, 1fr) auto auto;
        padding:12px;
        border:1px solid var(--line);
        border-radius:12px;
        background:rgba(8,13,22,.46);
    }
    .car-card-row strong {
        display:block;
        margin-bottom:4px;
        font-size:.9rem;
    }
    .car-card-row__meta,
    .car-card-row__actions {
        display:flex;
        align-items:center;
        gap:8px;
        flex-wrap:wrap;
        justify-content:flex-end;
    }
    .car-card-delete {
        background:rgba(248,113,113,.12) !important;
        border-color:rgba(248,113,113,.35) !important;
        color:#fecaca !important;
    }
    @media (max-width: 900px) {
        .car-card-group__head,
        .car-card-row {
            grid-template-columns:1fr;
        }
        .car-card-row__meta,
        .car-card-row__actions {
            justify-content:flex-start;
        }
    }
</style>
@endsection
