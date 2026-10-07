#!/usr/bin/env python3
"""Read-only task-plan checks. Passing does not certify implementation behavior."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / 'docs/planning/task-cards/cards.json'
STATES = {'locked', 'ready', 'active', 'review', 'verified', 'blocked',
          'accepted-not-applicable'}
DONE = {'verified', 'accepted-not-applicable'}


def validate(manifest, selected=None):
    errors = []
    cards = manifest.get('cards', [])
    by_id = {c['id']: c for c in cards}
    if len(by_id) != len(cards):
        errors.append('Duplicate card ID')
    if manifest.get('branch') != 'codex/feature/self-hosted-byos-byoc':
        errors.append('Unexpected evolution branch')
    source_ids = {c['source_id'] for c in cards}
    if len(source_ids) != manifest.get('source_entries'):
        errors.append('Original task coverage mismatch')
    parents = {c['parent'] for c in cards}
    if parents != set(manifest.get('parent_gates', {})):
        errors.append('Work-package coverage mismatch')
    visited, visiting = set(), set()

    def walk(task_id):
        if task_id in visiting:
            errors.append(f'{task_id}: dependency cycle')
            return
        if task_id in visited or task_id not in by_id:
            return
        visiting.add(task_id)
        for dep in by_id[task_id]['dependencies']:
            if dep not in by_id:
                errors.append(f'{task_id}: unknown dependency {dep}')
            else:
                walk(dep)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in by_id:
        walk(task_id)
    if selected and selected not in by_id:
        errors.append(f'Unknown task: {selected}')
    chosen = [by_id[selected]] if selected in by_id else cards
    for card in chosen:
        tid = card['id']
        if not re.fullmatch(r'G[0-6]-\d{2}\.[1-3][a-z]{0,2}', tid):
            errors.append(f'{tid}: invalid ID')
        if card['status'] not in STATES:
            errors.append(f'{tid}: invalid status')
        if card['model']['tier'] not in manifest['profiles']:
            errors.append(f'{tid}: unknown model tier')
        for field in ('title', 'acceptance', 'steps', 'verification',
                      'allowed_writes', 'evidence_required', 'escalation'):
            if not card.get(field):
                errors.append(f'{tid}: missing {field}')
        for item in card['inputs']:
            if not (ROOT / item['path']).is_file():
                errors.append(f'{tid}: missing baseline input {item["path"]}')
        md = ROOT / f'docs/planning/task-cards/{card["phase"]}/{tid}.md'
        if not md.is_file():
            errors.append(f'{tid}: missing Markdown card')
        else:
            text = md.read_text()
            if f'状态：**{card["status"]}**' not in text:
                errors.append(f'{tid}: Markdown state drift')
            if f'**{card["model"]["example"]}**' not in text:
                errors.append(f'{tid}: Markdown model drift')
            if card['title'] not in text or card['output'] not in text:
                errors.append(f'{tid}: Markdown goal/output drift')
        if card['status'] in DONE:
            completion = card.get('completion', {})
            evidence = completion.get('evidence_path', '')
            if not evidence or not (ROOT / evidence).is_file():
                errors.append(f'{tid}: completed card has no evidence file')
            if not completion.get('reviewed_by'):
                errors.append(f'{tid}: completed card has no reviewer')
            if card['status'] == 'accepted-not-applicable' and not completion.get('adr_path'):
                errors.append(f'{tid}: not-applicable disposition needs an ADR')
        if card['status'] in {'ready', 'active'}:
            for dep in card['dependencies']:
                if dep in by_id and by_id[dep]['status'] not in DONE:
                    errors.append(f'{tid}: unfinished prerequisite {dep}')
            if card['locks']:
                errors.append(f'{tid}: ready card still has locks')
            if card['mode'] in {'implementation', 'acceptance', 'research'}:
                path = ROOT / card['binding']
                if not path.is_file():
                    errors.append(f'{tid}: missing frozen binding')
                    continue
                binding = json.loads(path.read_text())
                if binding.get('task_id') != tid or binding.get('status') != 'frozen':
                    errors.append(f'{tid}: binding not frozen for this task')
                if not binding.get('contract_versions'):
                    errors.append(f'{tid}: missing contract/evidence version')
                commands = binding.get('commands', [])
                if not commands or any(not c.get('command') or not c.get('expected')
                                       for c in commands):
                    errors.append(f'{tid}: no exact behavior verification commands')
                files = binding.get('implementation_files', [])
                tests = binding.get('test_files', [])
                if not files or len(files) > 3 or len(tests) > 2:
                    errors.append(f'{tid}: missing/excessive implementation scope')
                if files + tests != card['implementation_writes']:
                    errors.append(f'{tid}: card/binding write scope drift')
                if not set(files + tests).issubset(card['allowed_writes']):
                    errors.append(f'{tid}: writes outside allowed paths')
                if binding.get('environment') != 'local-fixture' and not binding.get(
                        'side_effect_authorization'):
                    errors.append(f'{tid}: missing external-environment authorization')
                if not binding.get('reviewed_by'):
                    errors.append(f'{tid}: binding has no reviewer')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--card')
    parser.add_argument('--manifest', type=Path, default=DEFAULT)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    errors = validate(manifest, args.card)
    if errors:
        for error in errors:
            print('FAIL:', error)
        return 1
    cards = manifest['cards']
    print(f'OK: {len(cards)} cards; dependencies/coverage/input paths/card metadata checked')
    print('Plan check only; no implementation, model accuracy or live acceptance certified.')
    if args.card:
        card = next(c for c in cards if c['id'] == args.card)
        print(f'{card["id"]}: {card["status"]}; {card["model"]["example"]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
