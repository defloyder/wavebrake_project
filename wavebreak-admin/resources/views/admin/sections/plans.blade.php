<x-adm.card>
    <x-slot:actions>
        <button type="button" class="adm-btn adm-btn-primary" data-open-plan="">+ Новый тариф</button>
    </x-slot:actions>

    <x-adm.table-toolbar placeholder="Название или код…" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Тариф</th>
                    <th>Цена</th>
                    <th>Период</th>
                    <th>Трафик</th>
                    <th>Кол-во клиентов</th>
                    <th>Статус</th>
                </tr>
            </thead>
            <tbody>
            @forelse($planRows as $row)
                <tr data-row data-search="{{ $row->search() }}" data-open-plan="{{ json_encode($row->editable) }}" tabindex="0" class="is-clickable">
                    <td class="adm-cell-primary" data-sort="{{ $row->name }}">
                        <span class="adm-cell-title">{{ $row->name }}</span>
                        <span class="adm-cell-sub">{{ $row->description ?: $row->code }}</span>
                    </td>
                    <td data-label="Цена" class="num-cell" data-sort="{{ $row->priceSort }}">{{ $row->price }}</td>
                    <td data-label="Период">{{ $row->term }}</td>
                    <td data-label="Трафик">{{ $row->traffic }}</td>
                    <td data-label="Кол-во клиентов" class="num-cell">{{ $row->devices }}</td>
                    <td data-label="Статус">
                        <div class="adm-cell-stack">
                            @if($row->status->tone !== 'ok')<x-adm.badge :badge="$row->status" />@endif
                            @unless($row->public)<span class="adm-cell-sub">не показывается в приложении</span>@endunless
                        </div>
                    </td>
                </tr>
            @empty
                <tr><td colspan="6" class="adm-empty">Тарифов пока нет.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>

<x-adm.modal id="adm-plan-modal" title="Новый тариф">
    <form method="post" id="adm-plan-form" class="adm-form" action="/plans" data-ajax-form>
        @csrf
        <label>Название<input name="name" data-plan-field="name" class="adm-input" required maxlength="120"></label>
        <div class="adm-form-row">
            <label>Код <input name="code" data-plan-field="code" class="adm-input" required maxlength="60" pattern="[A-Za-z0-9][A-Za-z0-9_-]*" placeholder="plus-monthly"><small class="adm-hint">Латиница, цифры, «-» и «_».</small></label>
            <label>Период
                <select name="interval" data-plan-field="interval" class="adm-input">
                    <option value="month">Месяц</option>
                    <option value="year">Год</option>
                </select>
            </label>
        </div>
        <label>Описание <span class="adm-optional">необязательно</span><input name="description" data-plan-field="description" class="adm-input" maxlength="500"></label>
        <div class="adm-form-row">
            <label>Цена<input name="price" data-plan-field="price" type="number" step="0.01" min="0" class="adm-input" required></label>
            <label>Валюта
                <select name="currency" data-plan-field="currency" class="adm-input">
                    @foreach(['USD', 'EUR', 'RUB', 'TRY'] as $currency)<option value="{{ $currency }}">{{ $currency }}</option>@endforeach
                </select>
            </label>
        </div>
        <div class="adm-form-row">
            <label>Трафик, ГБ<input name="traffic_limit_gb" data-plan-field="traffic_limit_gb" type="number" step="0.01" min="0.01" class="adm-input" placeholder="безлимит"><small class="adm-hint">Пусто — без лимита. 1 ГБ = 1024³ байт.</small></label>
            <label>Кол-во клиентов<input name="device_limit" data-plan-field="device_limit" type="number" min="1" max="100" class="adm-input" required></label>
        </div>
        <label>Срок, дней <span class="adm-optional">необязательно</span><input name="duration_days" data-plan-field="duration_days" type="number" min="1" max="3650" class="adm-input" placeholder="по периоду"></label>
        <div class="adm-form-checks">
            <label class="adm-form-check"><input type="checkbox" name="is_active" value="1" data-plan-field="is_active" checked> Доступен для выдачи</label>
            <label class="adm-form-check"><input type="checkbox" name="is_public" value="1" data-plan-field="is_public" checked> Показывать в приложении</label>
        </div>
        <p class="adm-form-error" data-form-error hidden></p>
        <div class="adm-form-actions">
            <button type="submit" class="adm-btn adm-btn-primary">Сохранить</button>
            <button type="button" class="adm-btn" data-modal-close>Отмена</button>
            <button type="button" class="adm-btn adm-btn--danger adm-form-actions__end" data-plan-delete hidden>Удалить тариф</button>
        </div>
    </form>
</x-adm.modal>
