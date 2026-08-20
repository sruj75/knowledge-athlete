from testing.parity_pack_v0.export import resolve_export_target


def test_parity_pack_export_target_supports_uri_and_split_configuration():
    assert resolve_export_target({"OMI_PARITY_PACK_GCS_URI": "gs://dev-packs/parity/v0/"}) == (
        "dev-packs",
        "parity/v0",
    )
    assert resolve_export_target(
        {
            "OMI_PARITY_PACK_GCS_BUCKET": "dev-packs",
            "OMI_PARITY_PACK_GCS_PREFIX": "surface/v1",
        }
    ) == ("dev-packs", "surface/v1")


def test_parity_pack_export_target_fails_closed_without_bucket():
    assert resolve_export_target({}) is None
    assert resolve_export_target({"OMI_PARITY_PACK_GCS_URI": "https://example.com/not-gcs"}) is None
