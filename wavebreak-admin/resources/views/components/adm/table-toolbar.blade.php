@props(['placeholder' => 'Поиск…', 'filters' => []])
<div class="adm-table-toolbar">
    <label class="adm-table-search">
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="11" cy="11" r="6.5" stroke="currentColor" stroke-width="1.8"/><path d="m20 20-4.2-4.2" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
        <input type="search" data-table-search placeholder="{{ $placeholder }}" aria-label="{{ $placeholder }}">
    </label>
    @if($filters)
        <div class="adm-segmented" data-table-filter role="group" aria-label="Фильтр">
            <button type="button" class="is-active" data-filter="">Все</button>
            @foreach($filters as $value => $label)
                <button type="button" data-filter="{{ $value }}">{{ $label }}</button>
            @endforeach
        </div>
    @endif
    <span class="adm-table-count" data-table-count></span>
</div>
