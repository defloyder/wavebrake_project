{{-- Shell of the user card; the body is server-rendered by
     UserDetailsController and swapped in by public/js/admin-user-card.js. --}}
<div class="adm-modal-backdrop" id="adm-user-card" data-modal data-user-card>
    <div class="adm-modal adm-modal--card" role="dialog" aria-modal="true" aria-label="Карточка пользователя">
        <button type="button" class="adm-modal-close adm-modal-close--float" data-modal-close aria-label="Закрыть">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
        </button>
        <div class="adm-alert adm-alert--error adm-uc-error" data-user-card-error role="alert" hidden></div>
        <div data-user-card-body>
            <div class="adm-uc-loading" aria-live="polite"><span class="adm-spinner"></span> Загрузка…</div>
        </div>
    </div>
</div>
