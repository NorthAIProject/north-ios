#!/usr/bin/env bash
# Seeds a crew with a chat for CrewChatUITests.testChatRulesReportBlock.
#
# The owner (Owner, crewowner@crew.test) has accepted the community terms,
# started "Iron rats" and posted three messages in its #general. The joiner
# (Joiner, crewjoiner@crew.test) joined through the crew's link and has NOT
# accepted the terms, so their first post asks for the crew rules.
#
# Both accounts are erased and made again on every run: a test run accepts
# the terms, reports and blocks, none of which the API can undo. Local server
# on :8090 only; the password is a local test value.
#
#   eval "$(scripts/seed-crews-uitest.sh)"   # exports TEST_RUNNER_CREW_CHAT_*
set -euo pipefail
python3 - <<'PY'
import json, sys, urllib.error, urllib.request
base = "http://localhost:8090/api/v1"
password = "crew-check-pass-1"

def call(method, path, token=None, body=None, ok=True):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body or {}).encode(),
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw.strip()[:1] in ("{", "[") else raw
    except urllib.error.HTTPError as e:
        if not ok:
            return None
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()[:400]}")

def fresh(email, name):
    """Erases the account if an earlier run left it, then signs it up again."""
    old = call("POST", "/auth/login", body={"email": email, "password": password}, ok=False)
    if old:
        call("POST", "/account/delete", old["token"], {"confirmEmail": email})
    token = call("POST", "/auth/signup", body={"email": email, "password": password, "passwordConfirmation": password,
                                               "displayName": name})["token"]
    call("POST", "/onboarding", token, {"focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"})
    return token

owner = fresh("crewowner@crew.test", "Owner")
call("POST", "/moderation/terms", owner)
crew = call("POST", "/crews", owner, {"name": "Iron rats"})
general = next(c for c in call("GET", f"/crews/{crew['id']}/space", owner)["channels"] if c.get("default"))
for body in ["Welcome to Iron rats!", "Leg day tomorrow at 7.", "Who is in for the 5k on Sunday?"]:
    call("POST", f"/crews/{crew['id']}/channels/{general['id']}/messages", owner, {"body": body})

joiner = fresh("crewjoiner@crew.test", "Joiner")
code = crew["joinUrl"].rstrip("/").rsplit("/", 1)[-1]
call("POST", f"/crews/join/{code}", joiner)

print(f"export TEST_RUNNER_CREW_CHAT_EMAIL='crewjoiner@crew.test' TEST_RUNNER_CREW_CHAT_PASSWORD='{password}' "
      f"TEST_RUNNER_CREW_CHAT_OWNER='crewowner@crew.test' TEST_RUNNER_CREW_CHAT_ID='{crew['id']}' "
      f"TEST_RUNNER_CREW_CHAT_CHANNEL='{general['id']}' TEST_RUNNER_CREW_CHAT_CODE='{code}'")
PY
