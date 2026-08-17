from models.other import Person
from routers import users as users_router
from routers.users import UserProfileResponse


def test_user_profile_response_schema_models_desktop_fields():
    schema = UserProfileResponse.model_json_schema()
    properties = schema['properties']

    assert schema['title'] == 'UserProfileResponse'
    assert schema['required'] == ['uid']
    assert properties['uid']['type'] == 'string'
    assert properties['email']['anyOf'][0]['type'] == 'string'
    assert 'name' not in properties
    assert properties['time_zone']['anyOf'][0]['type'] == 'string'
    assert properties['created_at']['anyOf'][0]['format'] == 'date-time'
    assert properties['motivation']['anyOf'][0]['type'] == 'string'
    assert properties['use_case']['anyOf'][0]['type'] == 'string'
    assert properties['job']['anyOf'][0]['type'] == 'string'
    assert properties['company']['anyOf'][0]['type'] == 'string'


def test_user_profile_response_requires_uid_and_ignores_unowned_profile_fields():
    response = UserProfileResponse.model_validate(
        {
            'uid': 'user-123',
            'name': 'Desktop User',
            'future_profile_field': {'enabled': True},
        }
    )

    assert response.uid == 'user-123'
    assert 'name' not in response.model_dump()
    assert 'future_profile_field' not in response.model_dump()


def test_user_profile_endpoint_injects_uid_and_filters_legacy_name(monkeypatch):
    monkeypatch.setattr(
        users_router,
        'get_user_profile',
        lambda uid: {'name': 'Legacy User', 'email': 'user@example.com', 'data_protection_level': 'standard'},
    )

    response = users_router.get_user_profile_endpoint(uid='user-123')

    assert response == {
        'uid': 'user-123',
        'email': 'user@example.com',
        'data_protection_level': 'standard',
    }


def test_person_response_model_keeps_people_timestamps_optional():
    person = Person.model_validate({'id': 'person-123', 'name': 'Alice'})

    assert person.id == 'person-123'
    assert person.name == 'Alice'
    assert person.created_at is None
    assert person.updated_at is None
    assert person.speech_samples == []
    assert person.speech_sample_transcripts is None
    assert person.speech_samples_version == 3
