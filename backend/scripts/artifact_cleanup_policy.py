"""Pure dry-run selector for the bounded Artifact Registry cleanup contract."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Mapping, Sequence


def select_cleanup_candidates(
    versions: Iterable[Mapping[str, object]],
    *,
    now: datetime | None = None,
    protected_names: set[str],
) -> list[str]:
    """Return candidate names; this module deliberately has no delete operation."""
    reference_time = now or datetime.now(timezone.utc)
    if reference_time.tzinfo is None:
        raise ValueError('cleanup reference time must be timezone-aware')
    cutoff = reference_time - timedelta(days=30)
    selected: list[str] = []
    for version in versions:
        if version.get('kind') != 'docker-version':
            continue
        name = version.get('name')
        created_at = version.get('created_at')
        tags = version.get('tags')
        if not isinstance(name, str) or not name or not isinstance(created_at, str):
            raise ValueError('artifact inventory entries require name and created_at')
        if not isinstance(tags, Sequence) or isinstance(tags, (str, bytes)):
            raise ValueError(f'artifact {name} tags must be a list')
        if tags or name in protected_names:
            continue
        created = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
        if created < cutoff:
            selected.append(name)
    return sorted(selected)


def normalize_gcloud_inventory(values: object) -> list[dict[str, object]]:
    if not isinstance(values, list):
        raise ValueError('Artifact Registry inventory must be a JSON list')
    normalized: list[dict[str, object]] = []
    for raw_value in values:
        if not isinstance(raw_value, Mapping):
            raise ValueError('Artifact Registry inventory entries must be objects')
        package = raw_value.get('package')
        version = raw_value.get('version')
        created_at = raw_value.get('createTime') or raw_value.get('created_at')
        tags = raw_value.get('tags', [])
        name = raw_value.get('name')
        if not isinstance(name, str) or not name:
            if not isinstance(package, str) or not isinstance(version, str):
                raise ValueError('gcloud Artifact Registry entries require package and version')
            name = f'{package}@{version}'
        normalized.append(
            {
                'name': name,
                'kind': 'docker-version',
                'created_at': created_at,
                'tags': tags,
            }
        )
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--protected-name-file', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        inventory = normalize_gcloud_inventory(json.loads(args.inventory.read_text(encoding='utf-8')))
        protected_names = {
            line.strip() for line in args.protected_name_file.read_text(encoding='utf-8').splitlines() if line.strip()
        }
        candidates = select_cleanup_candidates(inventory, protected_names=protected_names)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f'ERROR: artifact cleanup dry run failed: {exc}')
        return 1
    payload = {
        'schema_version': 1,
        'dry_run': True,
        'delete_enabled': False,
        'protected_count': len(protected_names),
        'candidates': candidates,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
