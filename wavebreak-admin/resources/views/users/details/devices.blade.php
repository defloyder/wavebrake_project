@php $deviceRows = $details->deviceRows(); @endphp
<section class="adm-uc-section">
    <h4 class="adm-uc-title">Устройства <span class="adm-muted">{{ $details->devicesLabel() }}</span></h4>
    @if($deviceRows)
        <ul class="adm-uc-list">
            @foreach($deviceRows as $device)
                <li class="{{ $device->isActive() ? '' : 'is-muted' }}">
                    <div class="adm-uc-list-main">
                        <strong>{{ $device->name }}</strong>
                        <span>{{ $device->platform }} · в сети {{ $device->lastSeenAgo }}</span>
                    </div>
                    <x-adm.badge :badge="$device->status" />
                    @if($device->isActive())
                        <button type="button" class="adm-btn adm-btn--xs adm-btn--danger" data-action="{{ $base }}/devices/{{ $device->id }}/revoke" data-confirm="Отозвать устройство «{{ $device->name }}»? Ему придётся войти заново.">Отозвать</button>
                    @endif
                </li>
            @endforeach
        </ul>
    @else
        <p class="adm-empty">Устройств нет.</p>
    @endif
</section>
