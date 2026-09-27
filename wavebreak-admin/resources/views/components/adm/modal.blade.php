@props(['id', 'title' => '', 'wide' => false])
<div class="adm-modal-backdrop" id="{{ $id }}" data-modal>
    <div class="adm-modal {{ $wide ? 'adm-modal--wide' : '' }}" role="dialog" aria-modal="true" aria-labelledby="{{ $id }}-title">
        <div class="adm-modal-head">
            <h6 id="{{ $id }}-title" data-modal-title>{{ $title }}</h6>
            <button type="button" class="adm-modal-close" data-modal-close aria-label="Закрыть">
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
            </button>
        </div>
        {{ $slot }}
    </div>
</div>
