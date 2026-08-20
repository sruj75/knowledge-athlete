from __future__ import annotations

from tests.unit.translation_test_support import (
    DictTranslationStore,
    FakeProvider,
    build_service,
    profile,
    translations,
)
from utils.translation import TranslationStatus
from utils.translation_core.cache import CachedTranslation
from utils.translation_core.planner import fingerprint_text


def test_duplicate_sentences_are_sent_to_provider_once_and_reassembled():
    provider = FakeProvider(
        responses=[translations(('Bonjour.', 'en'), ('Partagé.', 'en'), ('Au revoir.', 'en'))],
    )
    service, _cache = build_service(provider)

    results = service.translate_outcomes(
        'fr',
        [('first', 'Hello. Shared.'), ('second', 'Shared. Bye.')],
    )

    assert [result.text for result in results] == ['Bonjour. Partagé.', 'Partagé. Au revoir.']
    assert provider.calls[0]['contents'] == ['Hello.', 'Shared.', 'Bye.']


def test_duplicate_unit_ids_preserve_order_and_identity():
    provider = FakeProvider(
        responses=[translations(('Uno.', 'en'), ('Dos.', 'en'))],
    )
    service, _cache = build_service(provider)

    results = service.translate_outcomes('es', [('same-id', 'One.'), ('same-id', 'Two.')])

    assert len(results) == 2
    assert [result.ordinal for result in results] == [0, 1]
    assert [result.unit_id for result in results] == ['same-id', 'same-id']
    assert [result.text for result in results] == ['Uno.', 'Dos.']


def test_output_cardinality_always_equals_input_cardinality_including_empty_text():
    provider = FakeProvider(responses=[translations(('Hola', 'en'))])
    service, _cache = build_service(provider)

    results = service.translate_outcomes('es', [('empty', ''), ('full', 'Hello')])

    assert len(results) == 2
    assert results[0].status == TranslationStatus.unchanged
    assert results[0].text == ''
    assert results[1].text == 'Hola'


def test_source_language_reaches_the_provider():
    provider = FakeProvider(responses=[translations(('Hola', 'en'))])
    service, _cache = build_service(provider)

    service.translate_units_batch('es', [('segment', 'Hello')], source_language='en')

    assert provider.calls[0]['source_language'] == 'en'


def test_max_batch_size_chunks_provider_calls_without_changing_output_order():
    provider = FakeProvider(
        responses=[
            translations(('Uno.', 'en'), ('Dos.', 'en')),
            translations(('Tres.', 'en'), ('Cuatro.', 'en')),
            translations(('Cinco.', 'en')),
        ],
    )
    service, _cache = build_service(
        provider,
        selected_profile=profile(max_batch_size=2),
    )

    outcomes = service.translate_outcomes('es', [('unit', 'One. Two. Three. Four. Five.')])

    assert outcomes[0].text == 'Uno. Dos. Tres. Cuatro. Cinco.'
    assert [call['contents'] for call in provider.calls] == [
        ['One.', 'Two.'],
        ['Three.', 'Four.'],
        ['Five.'],
    ]


def test_dominant_detected_language_is_reconstructed_from_sentence_results():
    provider = FakeProvider(
        responses=[translations(('Un.', 'en'), ('Deux.', 'fr'), ('Trois.', 'en'))],
    )
    service, _cache = build_service(provider)

    outcome = service.translate_outcomes('fr', [('unit', 'One. Two. Three.')])[0]

    assert outcome.detected_language == 'en'
    assert outcome.text == 'Un. Deux. Trois.'


def test_full_text_cache_hit_skips_provider_even_with_duplicate_unit_ids():
    store = DictTranslationStore()
    provider = FakeProvider(responses=[translations(('Deux.', 'en'))])
    service, cache = build_service(provider, store=store)
    cache.put(fingerprint_text('One.'), 'fr', CachedTranslation('Un.', 'en'), profile())

    outcomes = service.translate_outcomes('fr', [('same', 'One.'), ('same', 'Two.')])

    assert [outcome.text for outcome in outcomes] == ['Un.', 'Deux.']
    assert provider.calls[0]['contents'] == ['Two.']


def test_negative_sentence_cache_and_provider_result_reconstruct_one_complete_unit():
    store = DictTranslationStore()
    store.negative.add((fingerprint_text('Already.'), 'en'))
    provider = FakeProvider(responses=[translations(('Hello.', 'es'))])
    service, _cache = build_service(provider, store=store)

    outcome = service.translate_outcomes('en', [('unit', 'Already. Hola.')])[0]

    assert outcome.status == TranslationStatus.translated
    assert outcome.text == 'Already. Hello.'
    assert provider.calls[0]['contents'] == ['Hola.']
