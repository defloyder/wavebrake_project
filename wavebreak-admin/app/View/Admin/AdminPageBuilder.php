<?php

namespace App\View\Admin;

use App\Services\CoreClient;
use App\View\Admin\Rows\AuditRow;
use App\View\Admin\Rows\DeviceRow;
use App\View\Admin\Rows\GrantRow;
use App\View\Admin\Rows\NodeRow;
use App\View\Admin\Rows\PlanRow;
use App\View\Admin\Rows\SubscriptionRow;
use App\View\Admin\Rows\TrafficRow;
use App\View\Admin\Rows\UserRow;

/**
 * Builds the view data of one admin section. Each section declares the
 * Core datasets it needs, so a page only loads what it shows, and every
 * table gets presentation rows (emails, plan names, local dates, ГБ)
 * instead of raw Core ids.
 */
final class AdminPageBuilder
{
    /** @var array<string, array{title: string, subtitle: string, data: list<string>}> */
    private const SECTIONS = [
        'dashboard' => ['title' => 'Обзор', 'subtitle' => 'Состояние сервиса и последние действия.', 'data' => ['dashboard', 'trafficHistory', 'audit', 'users']],
        'users' => ['title' => 'Пользователи', 'subtitle' => 'Нажмите на пользователя, чтобы открыть карточку со всеми действиями.', 'data' => ['users']],
        'subscriptions' => ['title' => 'Подписки', 'subtitle' => 'У пользователя одна подписка. Управление — в карточке пользователя.', 'data' => ['subscriptions', 'users', 'plans', 'grants', 'traffic']],
        'plans' => ['title' => 'Тарифы', 'subtitle' => 'Нажмите на тариф, чтобы изменить его.', 'data' => ['plans']],
        'nodes' => ['title' => 'Ноды', 'subtitle' => 'Heartbeat и применённая ревизия конфигурации.', 'data' => []],
        'grants' => ['title' => 'Ключи доступа', 'subtitle' => 'Выданные учётные данные VPN. Управление — в карточке пользователя.', 'data' => ['grants', 'users']],
        'devices' => ['title' => 'Устройства', 'subtitle' => 'Зарегистрированные устройства пользователей.', 'data' => ['devices', 'users']],
        'traffic' => ['title' => 'Трафик', 'subtitle' => 'Использование по подпискам (1 ГБ = 1024³ байт).', 'data' => ['traffic', 'trafficHistory', 'users', 'subscriptions', 'plans']],
        'audit' => ['title' => 'Аудит', 'subtitle' => 'Кто, что и когда изменил.', 'data' => ['audit', 'users']],
        'enroll' => ['title' => 'Подключить ноду', 'subtitle' => 'Регистрация новой ноды через Core.', 'data' => []],
    ];

    public function __construct(private readonly CoreClient $core) {}

    public static function has(string $section): bool
    {
        return isset(self::SECTIONS[$section]);
    }

    /**
     * @param  array<string, mixed>  $me  the signed-in admin (Core /v1/me)
     * @return array<string, mixed> view data for dashboard.blade.php
     */
    public function build(string $token, string $section, array $me): array
    {
        $meta = self::SECTIONS[$section] ?? self::SECTIONS['dashboard'];
        $data = $this->load($token, $meta['data']);
        // Layout (health bar) needs nodes and health on every page.
        $nodes = $this->core->nodes($token);
        $directory = new AdminDirectory($data['users'] ?? [], $data['plans'] ?? [], $nodes, $data['subscriptions'] ?? []);

        return [
            'section' => $section,
            'title' => $meta['title'],
            'subtitle' => $meta['subtitle'],
            'me' => $me,
            'health' => $this->core->health(),
            'nodes' => $nodes,
            'dashboard' => $data['dashboard'] ?? [],
            'trafficHistory' => $data['trafficHistory'] ?? [],
            'userRows' => array_map(UserRow::fromCore(...), $data['users'] ?? []),
            'planRows' => array_map(PlanRow::fromCore(...), $data['plans'] ?? []),
            'nodeRows' => array_map(NodeRow::fromCore(...), $nodes),
            'subscriptionRows' => $section === 'subscriptions' ? $this->subscriptionRows($data, $directory) : [],
            'grantRows' => array_map(fn ($g) => GrantRow::fromCore($g, $directory), $data['grants'] ?? []),
            'deviceRows' => array_map(fn ($d) => DeviceRow::fromCore($d, $directory), $data['devices'] ?? []),
            'trafficRows' => array_map(fn ($t) => TrafficRow::fromCore($t, $directory), $data['traffic'] ?? []),
            'auditRows' => array_map(fn ($e) => AuditRow::fromCore($e, $directory), $section === 'dashboard' ? array_slice($data['audit'] ?? [], 0, 8) : ($data['audit'] ?? [])),
        ];
    }

    /**
     * @param  array<string, list<array<string, mixed>>>  $data
     * @return list<SubscriptionRow>
     */
    private function subscriptionRows(array $data, AdminDirectory $directory): array
    {
        $usage = [];
        foreach ($data['traffic'] ?? [] as $row) {
            $usage[(string) ($row['subscription_id'] ?? '')] = $row;
        }
        $withAccess = [];
        foreach ($data['grants'] ?? [] as $grant) {
            if (($grant['status'] ?? '') === 'active' && ! empty($grant['subscription_id'])) {
                $withAccess[(string) $grant['subscription_id']] = true;
            }
        }

        return array_map(
            fn ($sub) => SubscriptionRow::fromCore($sub, $usage[(string) $sub['id']] ?? null, isset($withAccess[(string) $sub['id']]), $directory),
            $data['subscriptions'] ?? [],
        );
    }

    /**
     * @param  list<string>  $datasets
     * @return array<string, mixed>
     */
    private function load(string $token, array $datasets): array
    {
        $loaders = [
            'dashboard' => fn () => $this->core->dashboard($token),
            'users' => fn () => $this->core->users($token),
            'plans' => fn () => $this->core->adminPlans($token),
            'subscriptions' => fn () => $this->core->subscriptions($token),
            'grants' => fn () => $this->core->grants($token),
            'devices' => fn () => $this->core->devices($token),
            'traffic' => fn () => $this->core->traffic($token),
            'trafficHistory' => fn () => $this->core->trafficHistory($token, 30),
            'audit' => fn () => $this->core->audit($token),
        ];
        $out = [];
        foreach ($datasets as $name) {
            $out[$name] = $loaders[$name]();
        }

        return $out;
    }
}
