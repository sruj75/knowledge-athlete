"""S-14 contract: the obsolete notifications Cloud Run job is unregistered."""

import json
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT.parent


def test_notifications_job_source_and_workflow_are_deleted() -> None:
    for path in (
        ROOT / 'modal/job.py',
        ROOT / 'modal/Dockerfile.notifications_job',
        ROOT / 'utils/other/jobs.py',
        ROOT / 'utils/other/notifications.py',
        REPO / '.github/workflows/gcp_notifications_job.yml',
    ):
        assert not path.exists(), f'{path.relative_to(REPO)} still exists'


def test_notifications_job_is_absent_from_runtime_registries() -> None:
    images = json.loads((ROOT / 'runtime_images.json').read_text(encoding='utf-8'))
    assert 'notifications-job' not in {image['name'] for image in images['images']}

    runtime = yaml.safe_load((ROOT / 'deploy/runtime_env.yaml').read_text(encoding='utf-8'))
    for environment in runtime['environments'].values():
        cloud_run = environment.get('cloud_run', {})
        assert 'notifications-job' not in cloud_run.get('jobs', {})
        assert '.github/workflows/gcp_notifications_job.yml' not in cloud_run.get('workflow_files', [])


def test_listen_imports_without_deleted_cloud_notification_module() -> None:
    subprocess.run(
        [sys.executable, '-c', 'import routers.listen.runtime'],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert not (ROOT / 'utils/notifications.py').exists()
