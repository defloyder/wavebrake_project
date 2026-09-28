@props(['badge'])
<span {{ $attributes->merge(['class' => 'adm-badge adm-badge--'.$badge->tone]) }}>{{ $badge->label }}</span>
