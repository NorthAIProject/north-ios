#!/usr/bin/env bash
# Seeds a local account whose conversation has a coach reply that looked up
# the push-up, for CoachUITests.testExerciseCardOpensTheExercise.
#
# The fake model never calls tools, so the reply is written through the API
# (a real turn) and then given the evidence ref a get_exercise call leaves:
# the same column a real lookup writes, set by hand. Local database only.
#
#   eval "$(scripts/seed-coach-uitest.sh)"   # exports TEST_RUNNER_COACH_*
set -euo pipefail
WEB="${NORTH_WEB_APP:-$(cd "$(dirname "$0")/../../.." && pwd)/north-web-app}"
python3 - "$WEB" <<'PY'
import json, subprocess, sys, time, urllib.request
web = sys.argv[1]
base = "http://localhost:8090/api/v1"
def call(method, path, token=None, body=None, timeout=120):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body or {}).encode(),
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode()
        return json.loads(raw) if raw.strip().startswith("{") else raw
email, password = f"card+{int(time.time())}@example.com", "Correct-horse-9"
token = call("POST", "/auth/signup", body={"email": email, "password": password, "passwordConfirmation": password, "displayName": "Ana"})["token"]
call("POST", "/onboarding", token, {"focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"})
conversation = call("POST", "/conversations", token, {})["id"]
call("POST", f"/conversations/{conversation}/reply", token, {"text": "How do I do a push-up?"})
sql = ("update messages set evidence_refs = array['exercise:push-up'] where id = ("
       f"select id from messages where conversation_id = '{conversation}' and role = 'model' order by created_at desc limit 1)")
subprocess.run(["docker-compose", "exec", "-T", "postgres", "psql", "-U", "north", "-d", "north", "-c", sql],
               cwd=web, check=True, capture_output=True)
print(f"export TEST_RUNNER_COACH_EMAIL='{email}' TEST_RUNNER_COACH_PASSWORD='{password}'")
PY
