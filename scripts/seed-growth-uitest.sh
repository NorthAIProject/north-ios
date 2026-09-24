#!/usr/bin/env bash
# Seeds a local account with a finished weekly report and a memory the coach
# proposed, for GrowthUITests. Both are normally written by background jobs
# on the AI model, so they are inserted as those jobs would leave them.
# Local database only.
#
#   eval "$(scripts/seed-growth-uitest.sh)"   # exports TEST_RUNNER_GROWTH_*
set -euo pipefail
WEB="${NORTH_WEB_APP:-$(cd "$(dirname "$0")/../../.." && pwd)/north-web-app}"
python3 - "$WEB" <<'PY'
import json, subprocess, sys, time, urllib.request, uuid
web = sys.argv[1]
base = "http://localhost:8090/api/v1"
def call(method, path, token=None, body=None):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body or {}).encode(),
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read().decode()
        return json.loads(raw) if raw.strip().startswith("{") else raw
email, password = f"growth+{int(time.time())}@example.com", "Correct-horse-9"
token = call("POST", "/auth/signup", body={"email": email, "password": password, "passwordConfirmation": password, "displayName": "Ana"})["token"]
call("POST", "/onboarding", token, {"focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"})
req = urllib.request.Request(base + "/me", headers={"Authorization": "Bearer " + token})
user = json.loads(urllib.request.urlopen(req).read())["user"]["id"]
body = "## The week\\n\\nFour sessions, sleep steady at 7.2 h.\\n\\n- Two long runs\\n- One strength day"
sql = f"""
insert into reports (id, user_id, kind, period_start, period_end, title, body, status, last_error, generated_at, created_at, updated_at)
values ('{uuid.uuid4()}', '{user}', 'weekly', '2026-09-14', '2026-09-20', 'Week of 14 September', E'{body}', 'ready', '', now(), now(), now());
insert into user_memories (id, user_id, category, content, status, source, created_at, updated_at)
values ('{uuid.uuid4()}', '{user}', 'injury', 'Left knee aches on long downhill runs.', 'pending', 'extraction', now(), now());
"""
subprocess.run(["docker-compose", "exec", "-T", "postgres", "psql", "-U", "north", "-d", "north", "-v", "ON_ERROR_STOP=1", "-c", sql],
               cwd=web, check=True, capture_output=True)
print(f"export TEST_RUNNER_GROWTH_EMAIL='{email}' TEST_RUNNER_GROWTH_PASSWORD='{password}'")
PY
