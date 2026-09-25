#!/usr/bin/env bash
# Seeds a local account that looks like three weeks of real use, for the App
# Store screenshots: a streak, sleep and water history, runs and strength
# sessions, goals part-way done, a training plan with a session today, and a
# coach conversation that draws on what it remembers. The coach's words are
# written directly because the local fake model's replies would not show what
# the coach does. Local database only.
#
#   eval "$(scripts/seed-screenshots.sh)"   # exports TEST_RUNNER_SHOTS_*
set -euo pipefail
WEB="${NORTH_WEB_APP:-$(cd "$(dirname "$0")/../../.." && pwd)/north-web-app}"
python3 - "$WEB" <<'PY'
import datetime as dt, json, random, subprocess, sys, time, urllib.request, uuid
web = sys.argv[1]
base = "http://localhost:8090/api/v1"
random.seed(7)

def call(method, path, token=None, body=None):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body or {}).encode(),
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read().decode()
        return json.loads(raw) if raw.strip()[:1] in "{[" else raw

def q(s):
    return "'" + s.replace("'", "''") + "'"

email, password = f"shots+{int(time.time())}@example.com", "Correct-horse-9"
token = call("POST", "/auth/signup", body={"email": email, "password": password, "passwordConfirmation": password,
                                           "displayName": "Alex", "timezone": "Europe/Lisbon"})["token"]
call("POST", "/onboarding", token, {"focusAreas": ["fitness", "sleep", "habits"], "coachingStyle": "supportive",
                                    "nearTermGoal": "Run a 10k under an hour"})
user = call("GET", "/me", token)["user"]["id"]

def goal(title, motivation, success, category, target, milestones, done):
    g = call("POST", "/goals", token, {"title": title, "motivation": motivation, "success": success,
                                       "category": category, "targetDate": target})
    for i, m in enumerate(milestones):
        ms = call("POST", f"/goals/{g['id']}/milestones", token, {"title": m})
        mid = ms.get("id") or ms.get("milestone", {}).get("id") or (ms.get("milestones") or [{}])[-1].get("id")
        if i < done and mid:
            call("PUT", f"/goals/{g['id']}/milestones/{mid}/status", token, {"status": "completed"})
    kept.append(g["id"])
    return g

kept = []
run = goal("Run a 10k under an hour", "Feel fit again after a slow year", "A timed 10k at 59:59 or better",
           "fitness", "2026-12-13", ["Run 5k without stopping", "Three runs a week for a month", "Long run of 8k", "Timed 10k"], 2)
goal("Sleep seven hours on weeknights", "Mornings are easier rested", "Four weeks averaging 7 h",
     "health", "2026-11-01", ["Lights out by 23:00", "No phone in bed for two weeks", "Four-week average of 7 h"], 1)
goal("Read twelve books this year", "Less scrolling, more reading", "Twelve finished books",
     "learning", "2026-12-31", ["Six books by summer", "Nine by October", "Twelve"], 2)

today = dt.date.today()
rows = []
wins = ["Easy 5k before work", "Stretched after the run", "In bed by eleven", "Strength session done",
        "Walked at lunch", "Long run felt good", "Drank my water", "Read 30 pages"]
for d in range(20, -1, -1):
    day = today - dt.timedelta(days=d)
    mood, energy = random.choice([3, 4, 4, 5]), random.choice([3, 3, 4, 4, 5])
    rows.append(f"insert into check_ins (user_id, local_date, mood, energy, wins) values ('{user}', '{day}', {mood}, {energy}, {q(random.choice(wins))}) on conflict do nothing;")
    rows.append(f"insert into sleep_logs (user_id, local_date, duration_minutes, quality) values ('{user}', '{day}', {455 if d == 0 else random.choice([395, 410, 425, 440, 455, 470])}, {random.choice([3, 4, 4, 5])}) on conflict do nothing;")
    for ml in random.sample([250, 330, 500, 500, 250], 4 if d else 3):
        rows.append(f"insert into hydration_logs (user_id, log_date, amount_ml, logged_at) values ('{user}', '{day}', {ml}, '{day} 10:00+01');")
    if d % 7 in (1, 3, 5):
        kind, minutes, dist = random.choice([("running", 38, 6200), ("running", 52, 8100), ("strength_training", 45, None)])
        start = dt.datetime.combine(day, dt.time(7, 15))
        end = start + dt.timedelta(minutes=minutes)
        rows.append("insert into activity_sessions (user_id, activity_code, source, status, weight_kg_snapshot, started_at, ended_at, total_paused_seconds, calories_burned, distance_m, created_at, updated_at) "
                    f"values ('{user}', '{kind}', 'manual', 'completed', 72, '{start}+01', '{end}+01', 0, {minutes * 9}, {dist or 'null'}, now(), now());")

def ex(name, slug, sets, reps, rest, equipment, primary, cue):
    return {"name": name, "catalog_slug": slug, "illustration_slug": slug, "sets": sets, "reps": reps, "rest_seconds": rest,
            "equipment": equipment, "form_cues": cue, "substitute": "", "primary_muscles": primary,
            "secondary_muscles": [], "stabilizer_muscles": []}
weekday = today.strftime("%A")
days = {
    "Monday": ("Upper body", [ex("Push-up", "push-up", 3, "AMRAP", 90, "none", ["chest"], "Body in one line."),
                              ex("Dumbbell Bench Press", "dumbbell-bench-press", 3, "8-10", 120, "dumbbell", ["chest"], "Shoulder blades pinned."),
                              ex("Plank", "plank", 3, "40 s", 60, "none", ["core"], "Ribs down, glutes on.")]),
    "Wednesday": ("Easy run + core", [ex("Dead Bug", "dead-bug", 3, "10", 60, "none", ["core"], "Low back stays down."),
                                      ex("Glute Bridge", "glute-bridge", 3, "12", 60, "none", ["glutes"], "Squeeze at the top.")]),
    weekday: ("Lower body", [ex("Goblet Squat", "goblet-squat", 3, "8-12", 90, "dumbbell", ["quads"], "Knees track over toes."),
                             ex("Romanian Deadlift", "romanian-deadlift", 3, "10", 120, "dumbbell", ["hamstrings"], "Hinge, soft knees, flat back."),
                             ex("Walking Lunge", "walking-lunge", 3, "10 each", 90, "dumbbell", ["quads", "glutes"], "Long step, upright torso."),
                             ex("Glute Bridge", "glute-bridge", 3, "12", 60, "none", ["glutes"], "Squeeze at the top.")]),
}
order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
plan = {"name": "10k and strength", "weeks_total": 8,
        "rationale": "Three strength days around your runs, lighter the day before a long run.",
        "days": [{"weekday": d, "focus": days[d][0], "exercises": days[d][1], **({"start_time": "07:30"} if d == weekday else {})}
                 for d in order if d in days]}
intake, plan_id = str(uuid.uuid4()), str(uuid.uuid4())
rows.append("insert into workout_intakes (id, user_id, goal, experience, days_per_week, session_minutes, equipment, limitations, created_at) "
            f"values ('{intake}', '{user}', 'Run a 10k and build strength', 'beginner', 3, 45, array['dumbbell'], '', now());")
rows.append("insert into workout_plans (id, user_id, intake_id, name, plan, model, provider, created_at, source) "
            f"values ('{plan_id}', '{user}', '{intake}', '10k and strength', $j${json.dumps(plan)}$j$, 'seed', 'seed', now(), 'ai');")

conv = str(uuid.uuid4())
rows.append(f"insert into conversations (id, user_id, title, kind, created_at, updated_at) values ('{conv}', '{user}', 'Knee after the long run', 'chat', now() - interval '20 minutes', now());")
chat = [
    ("user", "Did the long run on Sunday. 9k, slower than planned but I finished it."),
    ("model", "9k is your longest run since you started, well done. Slower is fine on a long run; the point is time on your feet. How did your legs feel afterwards?"),
    ("user", "My knee's a bit sore after Sunday's long run. Should I still do intervals tomorrow?"),
    ("model", "Is it the left one again, on the outside? You mentioned in August that it aches after long downhill stretches, and Sunday's route was mostly downhill.\n\n"
              "I'd swap tomorrow's intervals for an easy 30 minutes on flat ground, and keep Friday's lower-body session but go lighter on the lunges. "
              "If it still hurts when you walk down stairs on Thursday, we'll move the long run."),
    ("user", "Yes, left knee. Easy run it is."),
    ("model", "Good call. I've noted it, so I'll check in on the knee before your next long run. You're still on track for the 10k: two of four milestones done, eight weeks to go."),
]
for i, (role, text) in enumerate(chat):
    rows.append(f"insert into messages (conversation_id, role, content, created_at) values ('{conv}', '{role}', {q(text)}, now() - interval '{40 - i * 4} minutes');")
for cat, text in [("injury", "Left knee aches on long downhill runs."),
                  ("preference", "Prefers running early, before work."),
                  ("goal", "Training for a 10k under an hour by December.")]:
    rows.append(f"insert into user_memories (user_id, category, content, status, source, created_at, updated_at) values ('{user}', '{cat}', {q(text)}, 'approved', 'extraction', now(), now());")

# Onboarding opens its own goal and a first coach thread; the shots show only
# the seeded ones.
rows.append(f"delete from conversations where user_id = '{user}' and id <> '{conv}';")
rows.append(f"delete from goals where user_id = '{user}' and id not in ({', '.join(q(k) for k in kept)});")
proc = subprocess.run(["docker-compose", "exec", "-T", "postgres", "psql", "-U", "north", "-d", "north", "-v", "ON_ERROR_STOP=1"],
               input="begin;\n" + "\n".join(rows) + "\ncommit;\n", text=True, cwd=web, capture_output=True)
if proc.returncode:
    sys.exit(proc.stderr[-600:])
print(f"export TEST_RUNNER_SHOTS_EMAIL='{email}' TEST_RUNNER_SHOTS_PASSWORD='{password}'")
PY
