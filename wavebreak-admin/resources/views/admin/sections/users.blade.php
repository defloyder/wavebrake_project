<x-adm.card id="users-admin">
    <x-slot:actions>
        <button type="button" class="adm-btn adm-btn-primary" data-modal-open="adm-user-create-modal">+ Новый пользователь</button>
    </x-slot:actions>

    <x-adm.table-toolbar placeholder="Email, username или ID…" :filters="['with-sub' => 'С подпиской', 'no-sub' => 'Без подписки', 'blocked' => 'Заблокированные', 'staff' => 'Персонал']" />

    <div class="adm-table-wrap" data-enhance>
        <table class="adm-table adm-table--cards">
            <thead>
                <tr>
                    <th>Пользователь</th>
                    <th>Роль</th>
                    <th>Статус</th>
                    <th>Подписка</th>
                    <th>Последний вход</th>
                    <th>Регистрация</th>
                </tr>
            </thead>
            <tbody>
            @forelse($userRows as $row)
                <tr data-row data-search="{{ $row->search() }}" data-filter-tags="{{ $row->filter }}" data-open-user="{{ $row->id }}" tabindex="0" class="is-clickable">
                    <td class="adm-cell-primary" data-sort="{{ $row->email }}">
                        <span class="adm-cell-title">{{ $row->email }}</span>
                        @if($row->username)<span class="adm-cell-sub">{{ $row->username }}</span>@endif
                    </td>
                    <td data-label="Роль" data-sort="{{ $row->role->label }}"><x-adm.badge :badge="$row->role" /></td>
                    <td data-label="Статус" data-sort="{{ $row->status->label }}"><x-adm.badge :badge="$row->status" /></td>
                    <td data-label="Подписка" data-sort="{{ $row->planName ?? '' }}">
                        @if($row->planName)
                            <div class="adm-cell-stack">
                                <span class="adm-cell-inline"><strong>{{ $row->planName }}</strong> <x-adm.badge :badge="$row->subscription" /></span>
                                <span class="adm-cell-sub">до {{ $row->subscriptionEnds }}</span>
                            </div>
                        @else
                            <span class="adm-muted">Нет подписки</span>
                        @endif
                    </td>
                    <td data-label="Вход" class="date-cell" data-sort="{{ $row->lastLoginSort }}">{{ $row->lastLogin }}</td>
                    <td data-label="Регистрация" class="date-cell" data-sort="{{ $row->createdSort }}">{{ $row->createdAt }}</td>
                </tr>
            @empty
                <tr><td colspan="6" class="adm-empty">Пользователей пока нет.</td></tr>
            @endforelse
            </tbody>
        </table>
    </div>
</x-adm.card>

<x-adm.modal id="adm-user-create-modal" title="Новый пользователь">
    <form method="post" class="adm-form" action="/users" data-ajax-form>
        @csrf
        <label>Email<input name="email" type="email" class="adm-input" required autocomplete="off"></label>
        <label>Username <span class="adm-optional">необязательно</span><input name="username" class="adm-input" autocomplete="off"></label>
        <label>Пароль<input name="password" type="password" class="adm-input" minlength="10" required autocomplete="new-password"><small class="adm-hint">Не короче 10 символов.</small></label>
        <div class="adm-form-row">
            <label>Роль
                <select name="role" class="adm-input">
                    @foreach(\App\View\Admin\StatusBadge::ROLES as $role)<option value="{{ $role }}">{{ \App\View\Admin\StatusBadge::roleLabel($role) }}</option>@endforeach
                </select>
            </label>
            <label>Статус
                <select name="status" class="adm-input"><option value="active">Активен</option><option value="disabled">Заблокирован</option></select>
            </label>
        </div>
        <p class="adm-form-error" data-form-error hidden></p>
        <div class="adm-form-actions">
            <button type="submit" class="adm-btn adm-btn-primary">Создать</button>
            <button type="button" class="adm-btn" data-modal-close>Отмена</button>
        </div>
    </form>
</x-adm.modal>
