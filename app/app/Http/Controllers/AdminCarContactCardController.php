<?php

namespace App\Http\Controllers;

use App\Models\CarContactCard;
use App\Services\CarContactCardService;
use App\Services\NodeMonitorService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\View\View;
use Throwable;

class AdminCarContactCardController extends Controller
{
    public function __construct(
        private readonly CarContactCardService $cards,
        private readonly NodeMonitorService $monitor,
    ) {}

    public function index(): View
    {
        $cards = CarContactCard::query()->latest()->get();

        return view('admin.car-cards.index', [
            'groupedCards' => $cards->groupBy('phone'),
            'resources' => AdminPanelController::resources(),
            'serverHealth' => $this->monitor->health(),
        ]);
    }

    public function create(): View
    {
        return view('admin.car-cards.create', [
            'resources' => AdminPanelController::resources(),
            'serverHealth' => $this->monitor->health(),
        ]);
    }

    public function store(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'phone' => ['required', 'string', 'max:40'],
            'whatsapp_phone' => ['nullable', 'string', 'max:40'],
            'telegram' => ['nullable', 'string', 'max:64'],
            'email' => ['nullable', 'email', 'max:255'],
            'message' => ['nullable', 'string', 'max:180'],
        ]);

        try {
            $card = $this->cards->createFromPayload($data);
        } catch (Throwable $e) {
            return back()
                ->withInput()
                ->withErrors(['generation' => $e->getMessage()]);
        }

        return redirect()
            ->route('admin.car-cards.show', $card)
            ->with('success', 'Карточка создана, QR и макет готовы.');
    }

    public function show(CarContactCard $carCard): View
    {
        return view('admin.car-cards.show', [
            'card' => $carCard,
            'resources' => AdminPanelController::resources(),
            'serverHealth' => $this->monitor->health(),
        ]);
    }

    public function regenerate(CarContactCard $carCard): RedirectResponse
    {
        try {
            $this->cards->generateAssets($carCard);
        } catch (Throwable $e) {
            return back()->withErrors(['generation' => $e->getMessage()]);
        }

        return redirect()
            ->route('admin.car-cards.show', $carCard)
            ->with('success', 'QR и макет пересобраны.');
    }

    public function destroy(CarContactCard $carCard): RedirectResponse
    {
        $this->cards->deleteAssets($carCard);
        $carCard->delete();

        return redirect()
            ->route('admin.car-cards.index')
            ->with('success', 'Карточка и её файлы удалены.');
    }
}
