#!/bin/bash
set -eu
export HOME=/root
SOURCE_DIR=$(mktemp -d /tmp/azurelab-validation-XXXXXX)
GIT_TERMINAL_PROMPT=0 git clone --depth 1 https://github.com/duongdinhphong251-dev/AzureLab.git "$SOURCE_DIR" >/dev/null 2>&1
kubectl -n azurelab get pods -o json > "$SOURCE_DIR/pods.json"
python3 - "$SOURCE_DIR/pods.json" <<'PY'
import json, sys
pods = json.load(open(sys.argv[1]))['items']
for app in ('frontend','backend'):
    selected = [p for p in pods if p['metadata'].get('labels',{}).get('app') == app and not p['metadata'].get('deletionTimestamp')]
    assert len(selected) == 2, f'{app}: expected 2 Pods'
    assert len({p['spec']['nodeName'] for p in selected}) == 2, f'{app}: Pods share a node'
    assert all(any(c['type']=='Ready' and c['status']=='True' for c in p['status'].get('conditions',[])) for p in selected)
    print(f'PASS: {app} has 2 Ready replicas on separate nodes')
PY
FRONTEND_IP=$(kubectl -n azurelab get pod -l app=frontend -o jsonpath='{.items[0].status.podIP}')
echo 'INTERNAL_APPLICATION_SMOKE'
python3 "$SOURCE_DIR/app/scripts/smoke_test.py" --url "http://$FRONTEND_IP:8080"
echo INTERNAL_VERIFICATION_COMPLETE
