{{-- One source for the visible FAQ and its FAQPage markup. $faq: list of [question, answer HTML]. --}}
<div class="faq-list">
    @foreach ($faq as [$question, $answer])
        <details><summary>{{ $question }}</summary><p>{!! $answer !!}</p></details>
    @endforeach
</div>
@push('schema')
<script type="application/ld+json">{!! json_encode([
    '@context' => 'https://schema.org',
    '@type' => 'FAQPage',
    'mainEntity' => array_map(fn (array $item) => [
        '@type' => 'Question',
        'name' => $item[0],
        'acceptedAnswer' => ['@type' => 'Answer', 'text' => trim(preg_replace('/\s+/u', ' ', strip_tags($item[1])))],
    ], $faq),
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG) !!}</script>
@endpush
