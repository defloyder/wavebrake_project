<?php

namespace App\Console\Commands;

use App\Models\AdminSystemDigestSchedule;
use App\Services\AdminAlertService;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Log;

class SendAdminSystemDigest extends Command
{
    protected $signature = 'admin:system-digest {--force : Send immediately, ignoring saved schedule}';
    protected $description = 'Send system state digest to subscribed admins';

    public function handle(AdminAlertService $alerts): int
    {
        if ($this->option('force')) {
            $sent = $alerts->sendSystemDigest();
            $this->info("Admin system digest sent to {$sent} admin(s).");

            return self::SUCCESS;
        }

        $timezone = config('app.admin_digest_timezone', 'Europe/Moscow');
        $now = Carbon::now($timezone);
        $dueTimes = collect(range(0, 2))
            ->map(fn (int $minutes): string => $now->copy()->subMinutes($minutes)->format('H:i'))
            ->all();

        $sentSchedules = 0;
        $sentAdmins = 0;

        AdminSystemDigestSchedule::query()
            ->where('is_enabled', true)
            ->whereIn('send_time', $dueTimes)
            ->get()
            ->each(function (AdminSystemDigestSchedule $schedule) use ($alerts, $now, &$sentSchedules, &$sentAdmins): void {
                if ($schedule->last_sent_at?->timezone($now->timezone)->isSameDay($now)) {
                    return;
                }

                $sentAdmins += $alerts->sendSystemDigest();
                $schedule->forceFill(['last_sent_at' => now()])->save();
                $sentSchedules++;
            });

        Log::info('Admin system digest checked', [
            'timezone' => $timezone,
            'now' => $now->format('Y-m-d H:i:s'),
            'due_times' => $dueTimes,
            'sent_schedules' => $sentSchedules,
            'sent_admins' => $sentAdmins,
        ]);

        $this->info($sentSchedules > 0
            ? "Admin system digest sent: schedules={$sentSchedules}, admins={$sentAdmins}."
            : 'No digest due now.');

        return self::SUCCESS;
    }
}
