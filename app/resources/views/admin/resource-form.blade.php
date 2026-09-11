@extends('admin.layout')

@section('title', (($row && empty($isCreate)) ? 'Редактирование' : 'Создание') . ' - ' . $config['title'])

@section('content')
@php
    $fieldLabels = [
        'receives_payment_notifications' => 'Получать уведомления по всем заказам',
        'starts_at' => 'Начало действия',
        'expires_at' => 'Истекает',
        'value' => $resource === 'promo_codes' ? 'Значение: процент, рубли или дни' : 'value',
        'max_uses' => 'Лимит использований',
        'used_count' => 'Использовано',
        'is_active' => 'Активен',
        'hidden_on_dashboard' => 'Скрыть на дашборде и карте',
        'country' => 'Страна',
        'city' => 'Город',
        'lat' => 'Широта',
        'lng' => 'Долгота',
        'name' => $resource === 'plans' ? 'Название тарифа' : 'Название',
        'duration_months' => 'Срок, месяцев',
        'price_rub' => 'Цена, ₽',
        'headline' => 'Короткое описание',
        'features' => 'Преимущества тарифа',
        'is_highlighted' => 'Рекомендуемый тариф',
    ];
@endphp
<div style="margin-bottom:20px">
    <p style="margin:0;font-size:.72rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase">{{ $config['title'] }}</p>
    <h2 style="margin:4px 0 0;font-family:'Montserrat',sans-serif;font-size:1.5rem">
        {{ ($row && empty($isCreate)) ? 'Редактирование #'.$row->id : 'Создание записи' }}
    </h2>
</div>

@if ($errors->any())
    <div style="border-radius:12px;padding:12px 16px;margin-bottom:16px;font-size:.88rem;border:1px solid rgba(248,113,113,.35);background:rgba(248,113,113,.08);color:#fecaca">
        {{ $errors->first() }}
    </div>
@endif

<div class="adm-card">
    <form method="post" action="{{ ($row && empty($isCreate)) ? route('admin.resource.update', [$resource, $row->id]) : route('admin.resource.store', $resource) }}">
        @csrf
        @if($row && empty($isCreate)) @method('PUT') @endif

        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px">
            @foreach($config['fields'] as $field)
                <div>
                    <label style="display:block;font-size:.78rem;color:var(--muted);margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em">
                        {{ $fieldLabels[$field] ?? $field }}
                    </label>
                    @if(in_array($field, ['is_highlighted', 'is_active', 'trial_used', 'receives_payment_notifications', 'hidden_on_dashboard'], true))
                        <label style="display:flex;align-items:center;gap:8px;border:1px solid var(--line);border-radius:9px;padding:10px 12px;background:rgba(8,13,22,.6);text-transform:none;letter-spacing:0;color:var(--text);font-size:.88rem">
                            <input type="checkbox" name="{{ $field }}" value="1" @checked(old($field, $row?->{$field}))>
                            Включено
                        </label>
                    @elseif(isset($config['selects'][$field]))
                        <select class="adm-input" name="{{ $field }}">
                            @foreach($config['selects'][$field] as $optionValue => $optionLabel)
                                <option value="{{ $optionValue }}" @selected(old($field, $row?->{$field}) == $optionValue)>
                                    {{ $optionLabel }}
                                </option>
                            @endforeach
                        </select>
                    @elseif($resource === 'subscriptions' && $field === 'plan_id')
                        @php
                            $selectedPlanId = old($field, $row?->{$field});
                            $plans = \App\Models\Plan::query()->orderBy('duration_months')->get();
                        @endphp
                        <select class="adm-input" name="{{ $field }}" required>
                            <option value="">Выберите тариф</option>
                            @foreach($plans as $plan)
                                <option
                                    value="{{ $plan->id }}"
                                    data-months="{{ $plan->duration_months }}"
                                    @selected((string) $selectedPlanId === (string) $plan->id)
                                >
                                    {{ $plan->name }} · {{ $plan->duration_months }} мес · {{ number_format($plan->price_rub, 0, '.', ' ') }} ₽
                                </option>
                            @endforeach
                        </select>
                    @elseif(str_ends_with($field, '_at'))
                        @php
                            $dateValue = old($field, $row?->{$field});
                            if ($dateValue) {
                                try { $dateValue = \Carbon\Carbon::parse($dateValue)->format('Y-m-d\TH:i'); } catch (\Throwable $e) {}
                            }
                        @endphp
                        <input class="adm-input adm-datetime-picker" type="datetime-local" name="{{ $field }}" value="{{ $dateValue }}">
                    @elseif($resource === 'promo_codes' && $field === 'value')
                        <input class="adm-input" type="number" step="0.01" min="0" name="{{ $field }}"
                               value="{{ old($field, $row?->{$field}) }}"
                               placeholder="Процент, сумма скидки или количество дней">
                    @elseif($resource === 'promo_codes' && in_array($field, ['max_uses', 'used_count'], true))
                        <input class="adm-input" type="number" min="0" name="{{ $field }}"
                               value="{{ old($field, $row?->{$field}) }}">
                    @elseif($resource === 'plans' && $field === 'features')
                        @php
                            $featuresValue = old($field);
                            if ($featuresValue === null && $row?->{$field}) {
                                $featuresValue = is_array($row->{$field})
                                    ? implode("\n", $row->{$field})
                                    : (string) $row->{$field};
                            }
                        @endphp
                        <textarea class="adm-input" name="{{ $field }}" rows="5"
                                  placeholder="Одна возможность на строку">{{ $featuresValue }}</textarea>
                    @else
                        <input class="adm-input" name="{{ $field }}"
                               value="{{ old($field, $row ? (is_array($row->{$field}) ? json_encode($row->{$field}) : $row->{$field}) : '') }}">
                    @endif
                </div>
            @endforeach
        </div>

        <div style="margin-top:24px;display:flex;gap:10px;flex-wrap:wrap">
            <button type="submit" class="adm-btn">Сохранить</button>
            <a href="{{ route('admin.resource.index', $resource) }}" class="adm-btn" style="text-decoration:none;background:rgba(138,148,166,.15);color:var(--text)">
                ← Назад
            </a>
        </div>
    </form>
</div>
@endsection

@push('scripts')
<script>
document.querySelectorAll('.adm-datetime-picker').forEach(function(input) {
    function openPicker() {
        if (typeof input.showPicker !== 'function') {
            return;
        }

        try {
            input.showPicker();
        } catch (e) {}
    }

    input.addEventListener('click', openPicker);
    input.addEventListener('focus', openPicker);
});

(function() {
    var planSelect = document.querySelector('select[name="plan_id"]');
    var startsInput = document.querySelector('input[name="starts_at"]');
    var endsInput = document.querySelector('input[name="ends_at"]');

    if (!planSelect || !startsInput || !endsInput) {
        return;
    }

    var isEdit = @json((bool) $row && empty($isCreate));

    function pad(value) {
        return String(value).padStart(2, '0');
    }

    function toDatetimeLocal(date) {
        return date.getFullYear()
            + '-' + pad(date.getMonth() + 1)
            + '-' + pad(date.getDate())
            + 'T' + pad(date.getHours())
            + ':' + pad(date.getMinutes());
    }

    function addMonths(date, months) {
        var result = new Date(date.getTime());
        var day = result.getDate();
        result.setMonth(result.getMonth() + months);

        if (result.getDate() !== day) {
            result.setDate(0);
        }

        return result;
    }

    function applyPlanDates(force) {
        var option = planSelect.options[planSelect.selectedIndex];
        var months = parseInt(option ? option.dataset.months : '', 10);

        if (!months) {
            return;
        }

        if (!force && isEdit && (startsInput.value || endsInput.value)) {
            return;
        }

        var start = startsInput.value ? new Date(startsInput.value) : new Date();
        startsInput.value = toDatetimeLocal(start);
        endsInput.value = toDatetimeLocal(addMonths(start, months));
    }

    planSelect.addEventListener('change', function() {
        applyPlanDates(true);
    });

    startsInput.addEventListener('change', function() {
        if (planSelect.value) {
            applyPlanDates(true);
        }
    });

    applyPlanDates(false);
})();
</script>
@endpush
