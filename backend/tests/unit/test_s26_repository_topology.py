"""S-26 static topology contract for the canonical backend plane.

Behavioral route, launcher, and workflow tests prove the retained paths.  This
small static guard makes physical deletion part of the contract so a second
entrypoint, image, or deploy authority cannot silently return.
"""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]

RETIRED_PATHS = (
    'backend/desktop_backend.py',
    'backend/routers/desktop_deprecated.py',
    'backend/Dockerfile.desktop_backend',
    '.github/workflows/desktop_backend_auto_dev.yml',
    '.github/workflows/desktop_backend_prod.yml',
    '.github/workflows/desktop_backend_recover_prod.yml',
    '.github/scripts/check-desktop-backend-release-policy.py',
    '.github/scripts/test_check_desktop_backend_release_policy.py',
    '.github/scripts/verify_desktop_backend_image_lineage.py',
)


def test_repository_has_one_backend_entrypoint_image_and_deploy_plane() -> None:
    runtime_images = json.loads((ROOT / 'backend/runtime_images.json').read_text(encoding='utf-8'))

    assert [image['name'] for image in runtime_images['images']] == ['backend']
    assert runtime_images['images'][0]['entrypoints'] == ['main']
    assert runtime_images['images'][0]['deployment_workflows'] == [
        '.github/workflows/gcp_backend_auto_dev.yml',
        '.github/workflows/gcp_backend.yml',
    ]

    remaining = [path for path in RETIRED_PATHS if (ROOT / path).exists()]
    assert remaining == [], f'retired duplicate backend topology remains: {remaining}'
