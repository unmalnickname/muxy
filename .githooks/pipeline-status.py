import json, sys, os

status_file = sys.argv[1]; history_file = sys.argv[2]
hook_type = sys.argv[3]; step_id = sys.argv[4]
step_name = sys.argv[5]; status = sys.argv[6]
duration = sys.argv[7] if len(sys.argv) > 7 else None
timestamp = sys.argv[8] if len(sys.argv) > 8 else ""

os.makedirs(os.path.dirname(status_file), exist_ok=True)

data = {}
if os.path.exists(status_file):
    try:
        with open(status_file) as f: data = json.load(f)
    except: data = {}

data['hookType'] = hook_type

if status == 'started':
    data['overallStatus'] = 'running'
    data['startedAt'] = timestamp
    data['finishedAt'] = None
    data.setdefault('steps', [])
    if step_id and not any(s['id'] == step_id for s in data['steps']):
        data['steps'].append({
            'id': step_id, 'name': step_name,
            'status': 'running', 'duration': None
        })
elif status in ('passed', 'failed', 'skipped'):
    for s in data.setdefault('steps', []):
        if s['id'] == step_id:
            s['status'] = status
            if duration not in (None, 'None'):
                try: s['duration'] = float(duration)
                except: s['duration'] = 0.0
            break

    if data['steps'] and all(s['status'] in ('passed', 'failed', 'skipped') for s in data['steps']):
        failed = any(s['status'] == 'failed' for s in data['steps'])
        data['overallStatus'] = 'failed' if failed else 'passed'
        data['finishedAt'] = timestamp

        history = []
        if os.path.exists(history_file):
            try:
                with open(history_file) as f: history = json.load(f)
            except: history = []
        history.append({
            'id': hook_type + '-' + str(len(history)),
            'hookType': hook_type,
            'result': 'failed' if failed else 'passed',
            'timestamp': timestamp,
            'stepCount': len(data['steps']),
            'passedCount': len([s for s in data['steps'] if s['status'] == 'passed']),
            'duration': None
        })
        with open(history_file, 'w') as f:
            json.dump(history[-20:], f, indent=2)

with open(status_file, 'w') as f:
    json.dump(data, f, indent=2)
