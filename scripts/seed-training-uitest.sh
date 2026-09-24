#!/usr/bin/env bash
# Seeds a local account with a training plan, recorded biometrics and a few
# days of synced steps, for TrainingUITests, WorkoutUITests and ProgressUITests.
#
# The fake model cannot generate a plan (it answers in prose, not the plan
# schema), so the intake and plan rows are inserted as the repository would
# write them, with real catalog slugs that carry artwork. Biometrics are there
# because an activity session needs a weight to compute calories. Local
# database only.
#
#   eval "$(scripts/seed-training-uitest.sh)"   # exports TEST_RUNNER_TRAINING_*
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
email, password = f"train+{int(time.time())}@example.com", "Correct-horse-9"
token = call("POST", "/auth/signup", body={"email": email, "password": password, "passwordConfirmation": password, "displayName": "Ana"})["token"]
call("POST", "/onboarding", token, {"focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"})
req = urllib.request.Request(base + "/me", headers={"Authorization": "Bearer " + token})
user = json.loads(urllib.request.urlopen(req).read())["user"]["id"]

def ex(name, slug, sets, reps, rest, equipment, primary, cue):
    return {"name": name, "catalog_slug": slug, "illustration_slug": slug, "sets": sets, "reps": reps, "rest_seconds": rest,
            "equipment": equipment, "form_cues": cue, "substitute": "", "primary_muscles": primary,
            "secondary_muscles": [], "stabilizer_muscles": []}
plan = {"name": "Strength base", "rationale": "Two full-body days to build the habit before adding volume.", "weeks_total": 6,
        "days": [
            {"weekday": "Monday", "start_time": "07:00", "focus": "Lower body", "exercises": [
                ex("Goblet Squat", "goblet-squat", 3, "8-12", 90, "dumbbell", ["quads"], "Knees track over toes."),
                ex("Glute bridge", "glute-bridge", 3, "12", 60, "none", ["glutes"], "Squeeze at the top."),
            ]},
            {"weekday": "Thursday", "focus": "Upper body", "exercises": [
                ex("Push-up", "push-up", 3, "AMRAP", 90, "none", ["chest"], "Body in one line."),
                ex("Dumbbell Bench Press", "dumbbell-bench-press", 3, "8-10", 120, "dumbbell", ["chest"], "Shoulder blades pinned."),
            ]},
        ]}
intake, plan_id = str(uuid.uuid4()), str(uuid.uuid4())
sql = f"""
insert into workout_intakes (id, user_id, goal, experience, days_per_week, session_minutes, equipment, limitations, created_at)
values ('{intake}', '{user}', 'Get stronger', 'beginner', 2, 45, array['dumbbell'], '', now());
insert into workout_plans (id, user_id, intake_id, name, plan, model, provider, created_at, source)
values ('{plan_id}', '{user}', '{intake}', 'Strength base', $j${json.dumps(plan)}$j$, 'seed', 'seed', now(), 'ai');
insert into user_biometrics (id, user_id, weight_kg, height_cm, date_of_birth, sex, is_current, created_at)
values ('{uuid.uuid4()}', '{user}', 72, 175, '1990-05-01', 'female', true, now());
"""
subprocess.run(["docker-compose", "exec", "-T", "postgres", "psql", "-U", "north", "-d", "north", "-v", "ON_ERROR_STOP=1", "-c", sql],
               cwd=web, check=True, capture_output=True)
# Five days of steps, sent the way the phone sends them: one reading per day
# starting at midnight UTC, through the health sync API.
import datetime
today = datetime.datetime.now(datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
readings = []
for back in range(1, 6):
    start = today - datetime.timedelta(days=back)
    readings.append({"metric": "steps", "value": 6000 + back * 700, "unit": "count",
                     "startedAt": start.isoformat().replace("+00:00", "Z"),
                     "endedAt": (start + datetime.timedelta(days=1)).isoformat().replace("+00:00", "Z")})
call("POST", "/health/samples", token, {"readings": readings})
print(f"export TEST_RUNNER_TRAINING_EMAIL='{email}' TEST_RUNNER_TRAINING_PASSWORD='{password}'")
PY
