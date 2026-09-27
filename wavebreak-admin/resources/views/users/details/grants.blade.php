@php $grantRows = $details->grants(); @endphp
@if($grantRows)
    <section class="adm-uc-section">
        <h4 class="adm-uc-title">Ключи доступа <span class="adm-muted">активных: <span data-active-grants>{{ $details->access()['active_grants'] ?? 0 }}</span></span></h4>
        <ul class="adm-uc-list">
            @foreach($grantRows as $grant)
                <li class="{{ $grant->status->tone === 'ok' ? '' : 'is-muted' }}">
                    <div class="adm-uc-list-main">
                        <strong><code>{{ $grant->label }}</code>@if($grant->id === $details->credentialId()) <span class="adm-tag">ссылка подписки</span>@endif</strong>
                        <span>{{ $grant->node }} · {{ $grant->protocol }} · {{ $grant->kind }} · до {{ $grant->expiresAt }}</span>
                    </div>
                    <x-adm.badge :badge="$grant->status" />
                    @if($grant->status->tone === 'ok')
                        <button type="button" class="adm-btn adm-btn--xs adm-btn--danger" data-action="{{ $base }}/grants/{{ $grant->id }}/revoke" data-confirm="Отозвать ключ {{ $grant->label }}? Подключения по нему сразу перестанут работать.">Отозвать</button>
                    @endif
                </li>
            @endforeach
        </ul>
    </section>
@endif
