<x-adm.card title="Новая нода" subtitle="Core создаёт запись ноды; агент на сервере затем синхронизирует конфигурацию.">
    <form method="post" action="/nodes/enroll" class="adm-form">
        @csrf
        <div class="adm-form-row">
            <label>Код ноды<input name="code" class="adm-input" placeholder="TR-IST-01" required maxlength="40"></label>
            <label>Регион<input name="region" class="adm-input" placeholder="TR" required maxlength="20"></label>
        </div>
        <div class="adm-form-actions">
            <button type="submit" class="adm-btn adm-btn-primary">Зарегистрировать</button>
        </div>
    </form>
</x-adm.card>
