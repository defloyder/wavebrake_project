<?php

namespace App\Http\Controllers;

use App\Models\Admin;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\View\View;

class AdminAuthController extends Controller
{
    public function showLogin(Request $request): View|RedirectResponse
    {
        if ($request->session()->has('admin_id')) {
            return redirect()->route('admin.dashboard');
        }

        return view('admin.login');
    }

    public function login(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'username' => ['required', 'string', 'max:120'],
            'password' => ['required', 'string', 'max:255'],
        ]);

        $admin = Admin::query()->where('username', $data['username'])->first();

        if (! $admin || ! Hash::check($data['password'], $admin->password)) {
            // Log failed login attempt
            \App\Models\AdminLog::logFailedLogin(
                $data['username'],
                $admin ? 'wrong_password' : 'user_not_found'
            );

            return back()->withErrors(['username' => 'Неверный логин или пароль.'])->onlyInput('username');
        }

        $request->session()->put('admin_id', $admin->id);
        $request->session()->put('admin_name', $admin->name);
        $request->session()->regenerate();

        // Log successful login
        try {
            \App\Models\AdminLog::query()->create([
                'admin_id'    => $admin->id,
                'action'      => 'login',
                'resource'    => null,
                'resource_id' => null,
                'changes'     => [],
                'ip'          => $request->ip(),
            ]);
        } catch (\Throwable) {}

        return redirect()->route('admin.dashboard');
    }

    public function logout(Request $request): RedirectResponse
    {
        $request->session()->forget(['admin_id', 'admin_name']);
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('admin.login');
    }
}
