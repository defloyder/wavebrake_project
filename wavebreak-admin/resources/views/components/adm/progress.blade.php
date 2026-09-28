@props(['percent' => null])
@if($percent !== null)
    @php $tone = $percent >= 100 ? 'bad' : ($percent >= 80 ? 'warn' : 'ok'); @endphp
    <span {{ $attributes->merge(['class' => 'adm-progress adm-progress--'.$tone]) }} role="progressbar" aria-valuenow="{{ $percent }}" aria-valuemin="0" aria-valuemax="100">
        <span style="width: {{ min(100, max(0, $percent)) }}%"></span>
    </span>
@endif
