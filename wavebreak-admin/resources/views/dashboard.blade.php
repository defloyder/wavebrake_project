@extends('layout')

@section('title', $title)
@section('body_class', 'adm-page-'.$section)

@section('content')
<div class="adm-page">
    <header class="adm-page-head">
        <p class="adm-kicker">WAVEBREAK Admin</p>
        <h2 class="adm-section-title">{{ $title }}</h2>
        <p class="adm-page-subtitle">{{ $subtitle }}</p>
    </header>

    @include('admin.sections.'.$section)
</div>

{{-- The user card is reachable from every table that shows a user. --}}
@include('admin.partials.user-modal')
@endsection
