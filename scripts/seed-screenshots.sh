#!/usr/bin/env bash
# Seeds a local account that looks like three weeks of real use, for the App
# Store screenshots: a streak, sleep and water history, runs and strength
# sessions, goals part-way done, a training plan with a session today, and a
# coach conversation that draws on what it remembers, and four friends with a
# feed of their runs, goals and streaks and a crew on a check-in challenge.
# The coach's words are
# written directly because the local fake model's replies would not show what
# the coach does. Local database only.
#
#   eval "$(scripts/seed-screenshots.sh)"   # exports TEST_RUNNER_SHOTS_*
set -euo pipefail
WEB="${NORTH_WEB_APP:-$(cd "$(dirname "$0")/../../.." && pwd)/north-client}"
python3 - "$WEB" <<'PY'
import datetime as dt, json, random, subprocess, sys, time, urllib.request, uuid
web = sys.argv[1]
base = "http://localhost:8090/api/v1"
random.seed(7)

def call(method, path, token=None, body=None):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body or {}).encode(),
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw.strip()[:1] in ("{", "[") else raw
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:400]}")

def q(s):
    return "'" + s.replace("'", "''") + "'"

def psql(rows):
    proc = subprocess.run(["docker-compose", "exec", "-T", "postgres", "psql", "-U", "north", "-d", "north", "-v", "ON_ERROR_STOP=1"],
                          input="begin;\n" + "\n".join(rows) + "\ncommit;\n", text=True, cwd=web, capture_output=True)
    if proc.returncode:
        sys.exit(proc.stderr[-600:])

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

# Friends, their feed and a crew. Everyone follows everyone through invite
# links and shares every category; feed items come from the real API calls
# that record them, then their times are spread out below.
now = dt.datetime.now(dt.timezone.utc)
psql(["update users set handle = null where email like 'shots+%' and id <> " + q(user) + ";"])  # handles are unique; free earlier runs'
sharing ={"training": True, "streaks": True, "goals": True}
call("PUT", "/social/handle", token, {"handle": "alex_k"})
call("PUT", "/social/sharing", token, sharing)
friends = {}
for name, handle in [("Leo", "leo_runs"), ("Zoe", "zoe_moves"), ("Ana", "ana_swims"), ("Sam", "sam_lifts")]:
    t = call("POST", "/auth/signup", body={"email": f"shots+{handle}+{int(time.time())}@example.com", "password": password,
                                         "passwordConfirmation": password, "displayName": name, "timezone": "Europe/Lisbon"})["token"]
    call("PUT", "/social/handle", t, {"handle": handle})
    call("PUT", "/social/sharing", t, sharing)
    friends[name] = {"token": t, "id": call("GET", "/me", t)["user"]["id"]}
tokens = [token] + [f["token"] for f in friends.values()]
codes = [call("GET", "/invites", t)["code"] for t in tokens]
for t in tokens:
    for c in codes:
        call("POST", f"/invites/{c}/redeem", t)

# This week's earlier check-ins fill the crew challenge; Sam's six days make
# today's check-in his seventh, which records the streak.
monday = today - dt.timedelta(days=today.weekday())
earlier = {"Leo": [monday + dt.timedelta(days=i) for i in range(today.weekday())][-2:],
           "Zoe": [today - dt.timedelta(days=1)] if today > monday else [],
           "Sam": [today - dt.timedelta(days=d) for d in range(6, 0, -1)]}
psql([f"insert into check_ins (user_id, local_date, mood, energy, wins) values ('{friends[n]['id']}', '{day}', 4, 4, 'Showed up') on conflict do nothing;"
      for n, days in earlier.items() for day in days])
for name, wins_today in [("Leo", "Morning run, felt easy"), ("Zoe", "Strength before work"), ("Sam", "Seven days in a row")]:
    call("PUT", "/check-ins/today", friends[name]["token"], {"mood": 4, "energy": 4, "wins": wins_today})

for name, code, minutes, km, ago in [("Leo", "running_9_8kmh", 38, 6.2, 98), ("Zoe", "yoga", 45, None, 225), ("Ana", "hiking", 95, 7.4, 1750)]:
    t = friends[name]["token"]
    call("PUT", "/calculator/biometrics", t, {"weightKg": 64, "heightCm": 170, "dateOfBirth": "1992-03-14", "sex": "female" if name in ("Zoe", "Ana") else "male"})
    call("POST", "/activity/log", t, {"activityCode": code, "durationMinutes": minutes, "distanceKm": km,
                                      "startedAt": (now - dt.timedelta(minutes=ago)).isoformat()})

zoe = friends["Zoe"]["token"]
half = call("POST", "/goals", zoe, {"title": "Run a half marathon", "motivation": "Prove I can", "success": "Cross the line",
                                     "category": "fitness", "targetDate": "2026-10-15"})
call("PUT", f"/goals/{half['id']}/status", zoe, {"status": "achieved"})
ana = friends["Ana"]["token"]
swim = call("POST", "/goals", ana, {"title": "Learn front crawl", "motivation": "Swim with my kids", "success": "400 m without stopping",
                                     "category": "fitness", "targetDate": "2026-12-01"})
ms = call("POST", f"/goals/{swim['id']}/milestones", ana, {"title": "Swim 100 m without stopping"})
mid = ms.get("id") or ms.get("milestone", {}).get("id") or (ms.get("milestones") or [{}])[-1].get("id")
call("PUT", f"/goals/{swim['id']}/milestones/{mid}/status", ana, {"status": "completed"})

# Alex has kudos to give and to take back; the others cheer most moments.
for giver, t in [("Alex", token)] + [(n, f["token"]) for n, f in friends.items()]:
    for item in call("GET", "/feed", t)["items"]:
        if item["mine"]:
            continue
        if giver == "Alex" and item["kind"] == "streak_reached":
            continue
        if giver != "Alex" and item["displayName"] == "Alex" and giver not in ("Leo", "Zoe"):
            continue
        call("POST", f"/achievements/{item['id']}/kudos", t)

for owner, kind, age in [(friends["Sam"]["id"], "streak_reached", "35 minutes"), (friends["Zoe"]["id"], "goal_completed", "5 hours"),
                         (friends["Ana"]["id"], "milestone_reached", "1 day 2 hours")]:
    rows.append(f"update achievements set occurred_at = now() - interval '{age}' where user_id = '{owner}' and kind = '{kind}';")
# One of Alex's own moments is enough; the feed is about the friends.
rows.append(f"delete from achievements where user_id = '{user}' and title <> 'Reached a milestone: Run 5k without stopping';")
rows.append(f"update achievements set occurred_at = now() - interval '2 days' where user_id = '{user}';")

crew = call("POST", "/crews", token, {"name": "Morning runners"})
crew_code = crew["joinUrl"].rstrip("/").rsplit("/", 1)[-1]
for f in friends.values():
    call("POST", f"/crews/join/{crew_code}", f["token"])
call("PUT", f"/crews/{crew['id']}/challenge", token, {"kind": "checkins", "target": 5})
wins = ["Easy 5k before work", "Stretched after the run", "In bed by eleven", "Strength session done",
        "Walked at lunch", "Long run felt good", "Drank my water", "Read 30 pages"]
for d in range(20, -1, -1):
    day = today - dt.timedelta(days=d)
    mood, energy = random.choice([3, 4, 4, 5]), random.choice([3, 3, 4, 4, 5])
    rows.append(f"insert into check_ins (user_id, local_date, mood, energy, wins) values ('{user}', '{day}', {mood}, {energy}, {q(random.choice(wins))}) on conflict do nothing;")
    rows.append(f"insert into sleep_logs (user_id, local_date, duration_minutes, quality) values ('{user}', '{day}', {455 if d == 0 else random.choice([395, 410, 425, 440, 455, 470])}, {random.choice([3, 4, 4, 5])}) on conflict do nothing;")
    for ml in random.sample([250, 330, 500, 500, 250], 4):
        rows.append(f"insert into hydration_logs (user_id, log_date, amount_ml, logged_at) values ('{user}', '{day}', {ml}, '{day} 10:00+01');")
    if d % 7 in (1, 3, 5):
        kind, minutes, dist = random.choice([("running_9_8kmh", 38, 6200), ("running_9_8kmh", 52, 8100), ("strength_training", 45, None)])
        start = dt.datetime.combine(day, dt.time(7, 15))
        end = start + dt.timedelta(minutes=minutes)
        rows.append("insert into activity_sessions (user_id, activity_code, source, status, weight_kg_snapshot, started_at, ended_at, total_paused_seconds, calories_burned, distance_m, created_at, updated_at) "
                    f"values ('{user}', '{kind}', 'manual', 'completed', 72, '{start}+01', '{end}+01', 0, {minutes * 9}, {dist or 'null'}, now(), now());")

# Today's My Day cards: an early run, meals so far, coffee, supplements,
# screen time, and the daylight and stand hours a watch would report.
rows.append("insert into activity_sessions (user_id, activity_code, source, status, weight_kg_snapshot, started_at, ended_at, total_paused_seconds, calories_burned, distance_m, created_at, updated_at) "
            f"values ('{user}', 'running_9_8kmh', 'manual', 'completed', 72, '{today} 07:00+01', '{today} 07:38+01', 0, 430, 6200, now(), now());")
for label, kcal, p, f, c, at in [("Oats, banana and peanut butter", 520, 18, 16, 74, "08:10"),
                                 ("Chicken, rice and greens", 640, 46, 14, 78, "13:05"),
                                 ("Greek yoghurt and berries", 210, 17, 4, 26, "16:30")]:
    rows.append(f"insert into food_logs (user_id, log_date, label, calories, protein_g, fat_g, carbs_g, logged_at) values ('{user}', '{today}', {q(label)}, {kcal}, {p}, {f}, {c}, '{today} {at}+01');")
rows.append(f"insert into caffeine_logs (user_id, log_date, mg, label, logged_at) values ('{user}', '{today}', 95, 'Coffee', '{today} 08:15+01'), ('{user}', '{today}', 65, 'Espresso', '{today} 13:30+01');")
rows.append(f"insert into supplement_logs (user_id, log_date, name, nutrients, logged_at) values ('{user}', '{today}', 'Multivitamin', '{{vitamin_a,vitamin_b12,vitamin_c,vitamin_d,vitamin_e,zinc,iodine,folate}}', '{today} 08:20+01'), ('{user}', '{today}', 'Omega-3', '{{omega3}}', '{today} 08:20+01'), ('{user}', '{today}', 'Magnesium', '{{magnesium}}', '{today} 08:20+01');")
rows.append(f"insert into screen_time_logs (user_id, local_date, minutes) values ('{user}', '{today}', 118) on conflict do nothing;")
rows.append(f"insert into health_metrics (user_id, source, metric, value, unit, started_at) values ('{user}', 'apple_health', 'time_in_daylight', 48, 'min', '{today} 09:00+01'), ('{user}', 'apple_health', 'stand_hours', 9, 'h', '{today} 08:00+01') on conflict do nothing;")

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
psql(rows)
print(f"export TEST_RUNNER_SHOTS_EMAIL='{email}' TEST_RUNNER_SHOTS_PASSWORD='{password}' TEST_RUNNER_SHOTS_CREW='Morning runners'")
PY
