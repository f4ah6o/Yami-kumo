"""Validate planning artifacts without treating them as product-test evidence."""
from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


def validate(root: Path) -> list[str]:
    repository_root = root.parents[2]
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
    packets = manifest['packets']
    ids = [p['id'] for p in packets]
    if len(ids) != len(set(ids)) or len(ids) != 16:
        raise ValueError('Packet IDs are duplicated or the expected packet count differs.')
    paths = [p['path'] for p in packets]
    if len(paths) != len(set(paths)):
        raise ValueError('Two packets refer to the same file.')
    for p in packets:
        path = (root / p['path']).resolve()
        expected_parent = (repository_root / 'issues/open') if p['repo'] == 'f4ah6o/Yami-kumo' else (root / 'repos/gpui-mbt/gpui.mbt/issues/open')
        if path.parent != expected_parent.resolve() or not path.is_file():
            raise ValueError(f"Invalid packet path: {p['id']}")
        for dependency in p['dependencies']:
            if dependency not in ids or dependency == p['id']:
                raise ValueError(f"Invalid dependency: {p['id']} -> {dependency}")
        if p['status'] != 'proposed' or p['implementation'] != 'not_started' or p['test_status'] != 'not_run':
            raise ValueError(f"Unexpected implementation/test claim: {p['id']}")
        content = path.read_text(encoding='utf-8')
        for section in ('## 1. 目的・範囲', '## 2. 実装手順', '## 3. テスト対象と反例', '## 4. 受入条件', '## 5. 非対象'):
            if section not in content:
                raise ValueError(f"Missing section in {p['id']}: {section}")
        for dep in p['dependencies']:
            if dep not in content:
                raise ValueError(f"Missing dependency in packet text: {p['id']} -> {dep}")
    by_id = {p['id']: p for p in packets}
    visited: set[str] = set()
    active: set[str] = set()

    def visit(item: str) -> None:
        if item in active:
            raise ValueError(f'Dependency cycle at {item}')
        if item in visited:
            return
        active.add(item)
        for dep in by_id[item]['dependencies']:
            visit(dep)
        active.remove(item)
        visited.add(item)

    for item in ids:
        visit(item)
    checked_links = 0
    md_files = sorted(root.rglob('*.md')) + sorted((repository_root / 'issues/open').glob('20261017-ui4-yk-*.md'))
    for file in md_files:
        text = file.read_text(encoding='utf-8')
        if text.count('```') % 2:
            raise ValueError(f'Unbalanced code fences: {file.relative_to(root)}')
        if '{{PACKET_TABLE}}' in text:
            raise ValueError(f'Unresolved template token: {file.relative_to(root)}')
        for target in re.findall(r'\]\(([^)]+)\)', text):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                continue
            destination = (file.parent / unquote(parsed.path)).resolve() if parsed.path else file
            if not destination.is_relative_to(repository_root.resolve()) or not destination.exists():
                raise ValueError(f'Missing local link: {file.relative_to(root)} -> {target}')
            if parsed.fragment and destination.suffix == '.md':
                headings = re.findall(r'^#{1,6}\s+(.+)$', destination.read_text(encoding='utf-8'), re.M)
                anchors = [re.sub(r'[^\w\- ]', '', h.lower()).replace(' ', '-') for h in headings]
                if unquote(parsed.fragment) not in anchors:
                    raise ValueError(f'Missing heading: {file.relative_to(root)} -> {target}')
            checked_links += 1
    for repo, sha in manifest['baselines'].items():
        if re.fullmatch(r'[0-9a-f]{40}', sha) is None:
            raise ValueError(f'Invalid baseline SHA: {repo}')
    return [
        f'PASS packet files / required sections / unique IDs: {len(packets)}',
        f'PASS dependency graph: {len(visited)} nodes, no missing dependencies or cycles',
        'PASS all implementation states: proposed / not_started / not_run',
        f'PASS Markdown local links / anchors / code fences: {len(md_files)} files, {checked_links} links',
        'PASS baseline SHA format: 2 repositories',
        'NOT RUN product builds, MoonBit tests, DOM/Native E2E, IME and accessibility tests',
    ]


def main() -> int:
    try:
        for line in validate(Path(__file__).resolve().parent):
            print(line)
    except (OSError, KeyError, ValueError, TypeError) as exc:
        print(f'FAIL plan validation: {exc}')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
