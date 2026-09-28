@props(['value', 'label' => 'Копировать'])
<button type="button" {{ $attributes->merge(['class' => 'adm-copy']) }} data-copy="{{ $value }}" title="{{ $label }}" aria-label="{{ $label }}">
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2.5" stroke="currentColor" stroke-width="1.8"/><path d="M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8" stroke="currentColor" stroke-width="1.8"/></svg>
</button>
