@props(['title' => null, 'subtitle' => null])
<section {{ $attributes->merge(['class' => 'adm-card']) }}>
    @if($title || isset($actions))
        <header class="adm-card-head adm-card-head--row">
            <div>
                @if($title)<h6>{{ $title }}</h6>@endif
                @if($subtitle)<p>{{ $subtitle }}</p>@endif
            </div>
            @isset($actions)<div class="adm-card-actions">{{ $actions }}</div>@endisset
        </header>
    @endif
    {{ $slot }}
</section>
