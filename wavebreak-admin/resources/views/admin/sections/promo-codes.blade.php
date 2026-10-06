<x-adm.card>
    <x-slot:actions>
        @unless($promoUnavailable)
            <button type="button" class="adm-btn adm-btn-primary" data-open-promo="">+ Новый промокод</button>
        @endunless
    </x-slot:actions>

    @if($promoUnavailable)
        <p class="adm-empty">Core ещё не поддерживает промокоды — нужен деплой Core с миграцией 00007.</p>
    @else
        <x-adm.table-toolbar placeholder="Код или описание…" />

        <div class="adm-table-wrap" data-enhance>
            <table class="adm-table adm-table--cards">
                <thead>
                    <tr>
                        <th>Код</th>
                        <th>Скидка</th>
                        <th>Тариф</th>
                        <th>Действует</th>
                        <th>Активаций</th>
                        <th>Статус</th>
                    </tr>
                </thead>
                <tbody>
                @forelse($promoRows as $row)
                    <tr data-row data-search="{{ $row->search() }}" data-open-promo="{{ json_encode($row->editable) }}" tabindex="0" class="is-clickable">
                        <td class="adm-cell-primary" data-sort="{{ $row->code }}">
                            <span class="adm-cell-title">{{ $row->code }}</span>
                            @if($row->description !== '')<span class="adm-cell-sub">{{ $row->description }}</span>@endif
                        </td>
                        <td data-label="Скидка">{{ $row->discount }}</td>
                        <td data-label="Тариф">{{ $row->plan }}</td>
                        <td data-label="Действует">{{ $row->validity }}</td>
                        <td data-label="Активаций" class="num-cell">{{ $row->activations }}</td>
                        <td data-label="Статус"><x-adm.badge :badge="$row->status" /></td>
                    </tr>
                @empty
                    <tr><td colspan="6" class="adm-empty">Промокодов пока нет.</td></tr>
                @endforelse
                </tbody>
            </table>
        </div>
    @endif
</x-adm.card>

<x-adm.modal id="adm-promo-modal" title="Новый промокод">
    <form method="post" id="adm-promo-form" class="adm-form" action="/promo-codes" data-ajax-form>
        @csrf
        <div class="adm-form-row">
            <label>Код<input name="code" data-promo-field="code" class="adm-input" required minlength="3" maxlength="40" pattern="[A-Za-z0-9_-]+" placeholder="SPRING20" style="text-transform: uppercase"><small class="adm-hint">Латиница, цифры, «-» и «_»; регистр не важен.</small></label>
            <label>Тариф
                <select name="plan_id" data-promo-field="plan_id" class="adm-input">
                    <option value="">Все тарифы</option>
                    @foreach($planOptions as $plan)<option value="{{ $plan['id'] }}">{{ $plan['name'] }}</option>@endforeach
                </select>
            </label>
        </div>
        <label>Описание <span class="adm-optional">необязательно, видно пользователю</span><input name="description" data-promo-field="description" class="adm-input" maxlength="200"></label>
        <div class="adm-form-row">
            <label>Тип скидки
                <select name="discount_type" data-promo-field="discount_type" class="adm-input">
                    <option value="percent">Процент</option>
                    <option value="fixed">Сумма</option>
                </select>
            </label>
            <label>Размер<input name="discount_value" data-promo-field="discount_value" type="number" step="0.01" min="0.01" class="adm-input" required><small class="adm-hint">Процент — целое 1–100; сумма — в валюте ниже.</small></label>
            <label>Валюта суммы
                <select name="currency" data-promo-field="currency" class="adm-input">
                    @foreach(['RUB', 'USD', 'EUR', 'TRY'] as $currency)<option value="{{ $currency }}">{{ $currency }}</option>@endforeach
                </select>
            </label>
        </div>
        <div class="adm-form-row">
            <label>Начало <span class="adm-optional">необязательно</span><input name="valid_from" data-promo-field="valid_from" type="date" class="adm-input"></label>
            <label>Конец <span class="adm-optional">включительно</span><input name="valid_until" data-promo-field="valid_until" type="date" class="adm-input"></label>
            <label>Лимит активаций<input name="max_activations" data-promo-field="max_activations" type="number" min="1" class="adm-input" placeholder="без лимита"></label>
        </div>
        <div class="adm-form-checks">
            <label class="adm-form-check"><input type="checkbox" name="is_active" value="1" data-promo-field="is_active" checked> Включён</label>
        </div>
        <p class="adm-form-error" data-form-error hidden></p>
        <div class="adm-form-actions">
            <button type="submit" class="adm-btn adm-btn-primary">Сохранить</button>
            <button type="button" class="adm-btn" data-modal-close>Отмена</button>
            <button type="button" class="adm-btn adm-btn--danger adm-form-actions__end" data-promo-delete hidden>Удалить промокод</button>
        </div>
    </form>
</x-adm.modal>
