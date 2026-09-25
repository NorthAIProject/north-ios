#!/usr/bin/env bash
# Creates and seeds the App Review demo account, through the public API only.
#
#   scripts/seed-review-account.sh <base-url> <email> <password-file>
#
# The password is read from <password-file>, generated there (mode 600) if the
# file does not exist yet, and never printed. Rerunning with the same email
# signs in and tops the account up instead of failing. Each step prints ok or
# the HTTP status, so a partial seed is visible.
set -euo pipefail
BASE="${1:?base url, e.g. https://kheprios.com}"
EMAIL="${2:?email}"
PWFILE="${3:?password file}"
if [ ! -s "$PWFILE" ]; then
  (umask 077; python3 -c 'import secrets; print(secrets.token_urlsafe(18) + "-9a", end="")' > "$PWFILE")
fi
python3 - "$BASE/api/v1" "$EMAIL" "$PWFILE" <<'PY'
import json, sys, urllib.error, urllib.request
base, email, pwfile = sys.argv[1:]
password = open(pwfile).read().strip()

def call(method, path, token=None, body=None, timeout=60):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + path, method=method, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode()
        return json.loads(raw) if raw.strip()[:1] in "{[" else raw

def step(name, fn):
    try:
        fn()
        print(f"ok   {name}")
    except urllib.error.HTTPError as e:
        print(f"{e.code}  {name}: {e.read().decode()[:160]}")
    except Exception as e:
        print(f"err  {name}: {e}")

try:
    token = call("POST", "/auth/signup", body={"email": email, "password": password,
                  "passwordConfirmation": password, "displayName": "Alex", "timezone": "Europe/London"})["token"]
    print("ok   signup")
except urllib.error.HTTPError:
    token = call("POST", "/auth/login", body={"email": email, "password": password})["token"]
    print("ok   login (account existed)")

step("onboarding", lambda: call("POST", "/onboarding", token, {
    "focusAreas": ["fitness", "sleep", "habits"], "coachingStyle": "supportive",
    "nearTermGoal": "Run a 10k in under an hour"}))
goal = {}
step("goal", lambda: goal.update(call("POST", "/goals", token, {
    "title": "Run a 10k in under an hour", "motivation": "Feel fit again after a slow year",
    "success": "A timed 10k at 59:59 or better", "category": "fitness", "targetDate": "2026-12-13"})))
for title in ["Run 5k without stopping", "Three runs a week for a month", "Timed 10k"]:
    step(f"milestone {title}", lambda t=title: call("POST", f"/goals/{goal['id']}/milestones", token, {"title": t}))
step("second goal", lambda: call("POST", "/goals", token, {
    "title": "Sleep seven hours on weeknights", "motivation": "Mornings are easier rested",
    "success": "Four weeks averaging 7 h", "category": "health"}))
step("check-in", lambda: call("PUT", "/check-ins/today", token, {
    "mood": 4, "energy": 3, "wins": "Got out for an easy 5k", "challenges": "Late night before",
    "notes": "Legs a bit heavy"}))
step("water", lambda: [call("POST", "/care/water", token, {"amountMl": ml}) for ml in (500, 250, 500)])
step("sleep", lambda: call("PUT", "/care/sleep", token, {"durationMinutes": 430, "quality": 4}))
step("habit", lambda: call("POST", "/care/habits", token, {"name": "Stretch 10 minutes", "domain": "health",
                                                          "daysOfWeek": [1, 2, 3, 4, 5, 6, 7]}))
step("journal", lambda: call("POST", "/mind/journal", token, {
    "content": "First week back running. Slower than I remember, but it felt good to be outside.", "mood": 4}))
step("decision", lambda: call("POST", "/decisions", token, {
    "title": "Join the Saturday running club", "options": "Join now, or wait until I can run 8k",
    "rationale": "Company makes the long runs happen; the club has a slow group"}))
step("training plan (model)", lambda: call("POST", "/training/plans", token, {
    "goal": "Run a 10k and build general strength", "experience": "beginner", "daysPerWeek": 3,
    "sessionMinutes": 45, "equipment": ["dumbbell", "bodyweight"], "limitations": ""}, timeout=240))

def converse():
    conv = call("POST", "/conversations", token, {"kind": "chat"})
    req = urllib.request.Request(base + f"/conversations/{conv['id']}/reply", method="POST",
        data=json.dumps({"text": "I want to run a 10k by December. Where should I start this week?"}).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=240) as r:
        stream = r.read().decode()
    if "event: done" not in stream and '"done"' not in stream:
        raise RuntimeError("stream ended without done")
step("coach conversation (model)", converse)
PY
