<?php

namespace App\Services;

use Illuminate\Support\Str;

class AdminAssistant
{
    public function __construct(private readonly CoreClient $core)
    {
    }

    public function reply(string $token, string $message): array
    {
        $query = Str::lower(trim($message));

        if ($query === '' || $this->contains($query, ['сводка', 'статистика', 'что происходит', 'состояние системы'])) {
            return $this->overview($token);
        }

        if ($this->contains($query, ['помощь', 'что умеешь', 'команды'])) {
            return [
                'text' => 'Могу показать сводку, состояние узлов и трафика, найти пользователя или запись, а также подготовить изменение статуса подписки, блокировку пользователя или отзыв подключения. Изменения выполняются только после подтверждения.',
                'suggestions' => ['Сводка', 'Подписки', 'Узлы', 'Трафик', 'Найти пользователя'],
            ];
        }

        if ($action = $this->parseAction($token, $query)) {
            return $action;
        }

        if ($this->contains($query, ['подписк'])) {
            return $this->subscriptionSummary($token);
        }

        if ($this->contains($query, ['узел', 'узлы', 'ноды', 'сервер'])) {
            return $this->nodeSummary($token);
        }

        if ($this->contains($query, ['трафик', 'нагрузк'])) {
            return $this->trafficSummary($token);
        }

        if ($this->contains($query, ['найди', 'поиск', 'пользовател', 'email', '@'])) {
            return $this->search($token, $this->searchTerm($message));
        }

        return [
            'text' => 'Не понял запрос. Напишите, например: «сводка», «подписки», «трафик», «найди user@example.com» или «приостанови подписку UUID».',
            'suggestions' => ['Сводка', 'Подписки', 'Узлы', 'Трафик'],
        ];
    }

    public function execute(string $token, array $action): array
    {
        return match ($action['type'] ?? '') {
            'subscription_status' => $this->executeSubscriptionStatus($token, $action),
            'user_disable' => $this->executeUserState($token, $action, false),
            'user_enable' => $this->executeUserState($token, $action, true),
            'grant_revoke' => $this->executeGrantRevoke($token, $action),
            'device_revoke' => $this->executeDeviceRevoke($token, $action),
            default => ['text' => 'Команда устарела или не поддерживается.', 'level' => 'error'],
        };
    }

    private function overview(string $token): array
    {
        $dashboard = $this->core->dashboard($token);
        $nodes = $this->core->nodes($token);
        $subscriptions = $this->core->subscriptions($token);
        $users = $this->core->users($token);
        $traffic = $this->core->traffic($token);
        $online = count(array_filter($nodes, fn ($node) => ($node['status'] ?? '') === 'online'));
        $active = count(array_filter($subscriptions, fn ($subscription) => ($subscription['status'] ?? '') === 'active'));
        $bytes = array_sum(array_map(fn ($row) => (int) ($row['bytes_total'] ?? 0), $traffic));

        return [
            'text' => sprintf(
                'Система работает. Узлы: %d из %d онлайн. Активных подписок: %d из %d. Пользователей: %d. Учтённый трафик: %s.',
                $online,
                count($nodes),
                $active,
                count($subscriptions),
                count($users),
                $this->bytes($bytes),
            ),
            'facts' => [
                ['label' => 'Core', 'value' => (string) ($dashboard['status'] ?? 'ok')],
                ['label' => 'Узлы', 'value' => "{$online}/".count($nodes)],
                ['label' => 'Подписки', 'value' => (string) $active],
                ['label' => 'Трафик', 'value' => $this->bytes($bytes)],
            ],
            'suggestions' => ['Подписки', 'Узлы', 'Трафик', 'Найти пользователя'],
        ];
    }

    private function subscriptionSummary(string $token): array
    {
        $rows = $this->core->subscriptions($token);
        $counts = array_count_values(array_map(fn ($row) => $row['status'] ?? 'unknown', $rows));
        $parts = [];
        foreach (['active' => 'активных', 'pending' => 'ожидают', 'suspended' => 'приостановлено', 'expired' => 'истекло', 'cancelled' => 'отменено'] as $status => $label) {
            if (($counts[$status] ?? 0) > 0) {
                $parts[] = "{$label}: {$counts[$status]}";
            }
        }

        return [
            'text' => 'Всего подписок: '.count($rows).'. '.($parts ? implode(', ', $parts).'.' : 'Записей пока нет.'),
            'link' => ['label' => 'Открыть подписки', 'href' => '/subscriptions'],
            'suggestions' => ['Сводка', 'Найти пользователя', 'Трафик'],
        ];
    }

    private function nodeSummary(string $token): array
    {
        $nodes = $this->core->nodes($token);
        $online = array_values(array_filter($nodes, fn ($node) => ($node['status'] ?? '') === 'online'));
        $offline = array_values(array_filter($nodes, fn ($node) => ($node['status'] ?? '') !== 'online'));
        $offlineNames = array_map(fn ($node) => $node['code'] ?? $node['id'] ?? 'unknown', $offline);

        return [
            'text' => sprintf(
                'Онлайн %d из %d узлов.%s',
                count($online),
                count($nodes),
                $offlineNames ? ' Требуют внимания: '.implode(', ', array_slice($offlineNames, 0, 5)).'.' : ' Отключённых узлов нет.',
            ),
            'link' => ['label' => 'Открыть узлы', 'href' => '/nodes'],
            'suggestions' => ['Сводка', 'Трафик', 'Подписки'],
        ];
    }

    private function trafficSummary(string $token): array
    {
        $rows = $this->core->traffic($token);
        $health = $this->core->trafficHealth($token);
        $bytes = array_sum(array_map(fn ($row) => (int) ($row['bytes_total'] ?? 0), $rows));
        $stale = (bool) ($health['stale'] ?? true);

        return [
            'text' => sprintf(
                'Учтено %s по %d подпискам. Данные %s.',
                $this->bytes($bytes),
                count($rows),
                $stale ? 'давно не обновлялись — проверьте node-agent' : 'поступают штатно',
            ),
            'level' => $stale ? 'warning' : 'default',
            'link' => ['label' => 'Открыть трафик', 'href' => '/traffic'],
            'suggestions' => ['Сводка', 'Узлы', 'Подписки'],
        ];
    }

    private function search(string $token, string $term): array
    {
        if (mb_strlen($term) < 3) {
            return ['text' => 'Укажите email, UUID или не менее трёх символов имени.', 'level' => 'warning'];
        }

        $needle = Str::lower($term);
        $users = array_values(array_filter($this->core->users($token), function ($row) use ($needle) {
            return Str::contains(Str::lower(implode(' ', array_filter([
                $row['id'] ?? null, $row['email'] ?? null, $row['name'] ?? null, $row['role'] ?? null,
            ]))), $needle);
        }));
        $userIds = array_column($users, 'id');
        $subscriptions = array_values(array_filter($this->core->subscriptions($token), fn ($row) =>
            Str::contains(Str::lower(implode(' ', [$row['id'] ?? '', $row['user_id'] ?? '', $row['status'] ?? ''])), $needle)
            || in_array($row['user_id'] ?? null, $userIds, true)
        ));
        $lines = [];
        foreach (array_slice($users, 0, 4) as $user) {
            $lines[] = sprintf('Пользователь: %s · %s · %s', $user['email'] ?? $user['id'], $user['role'] ?? 'user', empty($user['disabled_at']) ? 'активен' : 'заблокирован');
        }
        foreach (array_slice($subscriptions, 0, 4) as $subscription) {
            $lines[] = sprintf('Подписка: %s · %s', $subscription['id'] ?? '—', $subscription['status'] ?? 'unknown');
        }

        return [
            'text' => $lines ? implode("\n", $lines) : "По запросу «{$term}» ничего не найдено.",
            'link' => $users ? ['label' => 'Открыть пользователей', 'href' => '/users'] : ['label' => 'Открыть подписки', 'href' => '/subscriptions'],
            'suggestions' => ['Сводка', 'Подписки'],
        ];
    }

    private function parseAction(string $token, string $query): ?array
    {
        if (preg_match('/(?:активир|возобнов).*подписк.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('subscription_status', $match[1], 'active', "Активировать подписку {$match[1]}?");
        }
        if (preg_match('/(?:приостанов|замороз).*подписк.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('subscription_status', $match[1], 'suspended', "Приостановить подписку {$match[1]}?");
        }
        if (preg_match('/(?:отмен|закры).*подписк.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('subscription_status', $match[1], 'cancelled', "Отменить подписку {$match[1]}?");
        }
        if (preg_match('/(?:заблокир|отключ).*пользовател.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('user_disable', $match[1], null, "Заблокировать пользователя {$match[1]}?");
        }
        if (preg_match('/(?:разблокир|включ).*пользовател.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('user_enable', $match[1], null, "Разблокировать пользователя {$match[1]}?");
        }
        if (preg_match('/(?:отзов|отмен).*подключени.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('grant_revoke', $match[1], null, "Отозвать подключение {$match[1]}?");
        }
        if (preg_match('/(?:отзов|отключ).*устройств.*?([0-9a-f-]{36})/iu', $query, $match)) {
            return $this->confirm('device_revoke', $match[1], null, "Отозвать устройство {$match[1]}?");
        }

        return null;
    }

    private function confirm(string $type, string $id, ?string $value, string $label): array
    {
        return [
            'text' => 'Команда распознана. Проверьте действие перед выполнением.',
            'confirmation' => [
                'label' => $label,
                'action' => array_filter(['type' => $type, 'id' => $id, 'value' => $value], fn ($item) => $item !== null),
            ],
        ];
    }

    private function executeSubscriptionStatus(string $token, array $action): array
    {
        $this->core->updateSubscriptionStatus($token, $action['id'], $action['value']);
        return ['text' => "Статус подписки изменён на {$action['value']}.", 'link' => ['label' => 'Открыть подписки', 'href' => '/subscriptions']];
    }

    private function executeUserState(string $token, array $action, bool $enabled): array
    {
        $enabled ? $this->core->enableUser($token, $action['id']) : $this->core->disableUser($token, $action['id']);
        return ['text' => $enabled ? 'Пользователь разблокирован.' : 'Пользователь заблокирован.', 'link' => ['label' => 'Открыть пользователей', 'href' => '/users']];
    }

    private function executeGrantRevoke(string $token, array $action): array
    {
        $this->core->revokeGrant($token, $action['id'], 'admin-assistant');
        return ['text' => 'Подключение отозвано.', 'link' => ['label' => 'Открыть подключения', 'href' => '/grants']];
    }

    private function executeDeviceRevoke(string $token, array $action): array
    {
        $this->core->revokeDevice($token, $action['id']);
        return ['text' => 'Устройство отозвано.', 'link' => ['label' => 'Открыть устройства', 'href' => '/devices']];
    }

    private function searchTerm(string $message): string
    {
        $term = preg_replace('/^(найди|поиск|покажи|пользователь|пользователя)\s*/iu', '', trim($message));
        return trim((string) $term, " \t\n\r\0\x0B\"'«»");
    }

    private function contains(string $query, array $needles): bool
    {
        return Str::contains($query, $needles);
    }

    private function bytes(int $bytes): string
    {
        if ($bytes >= 1073741824) {
            return number_format($bytes / 1073741824, 2, ',', ' ').' ГБ';
        }
        if ($bytes >= 1048576) {
            return number_format($bytes / 1048576, 1, ',', ' ').' МБ';
        }
        return number_format($bytes / 1024, 1, ',', ' ').' КБ';
    }
}
