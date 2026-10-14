import json

from utils.llm import desktop_llm_stub as stub


def test_llm_stub_flag_truthy_values():
    assert stub.llm_stub_flag_is_truthy('1')
    assert stub.llm_stub_flag_is_truthy('true')
    assert stub.llm_stub_flag_is_truthy('YES')
    assert not stub.llm_stub_flag_is_truthy('0')
    assert not stub.llm_stub_flag_is_truthy('false')
    assert stub.llm_stub_enabled({'OMI_LLM_STUB': '1'})
    assert not stub.llm_stub_enabled({})


def test_gemini_proxy_stub_echoes_marker():
    body = json.dumps(
        {
            'contents': [
                {'role': 'user', 'parts': [{'text': 'hello [[MARKER:gemini-stub]]'}]},
            ]
        }
    )
    payload = stub.stub_gemini_proxy_json(body)
    assert payload['candidates'][0]['content']['parts'][0]['text'] == 'Stub saw marker: gemini-stub'


def test_gemini_proxy_stub_honors_home_suggestion_response_schema():
    body = json.dumps(
        {
            'contents': [{'role': 'user', 'parts': [{'text': 'Write personalized questions'}]}],
            'generationConfig': {
                'responseMimeType': 'application/json',
                'responseSchema': {
                    'type': 'object',
                    'properties': {'questions': {'type': 'array', 'items': {'type': 'string'}}},
                    'required': ['questions'],
                },
            },
        }
    )

    payload = stub.stub_gemini_proxy_json(body)

    assert payload['candidates'][0]['content']['parts'][0]['text'] == '{"questions":[]}'
