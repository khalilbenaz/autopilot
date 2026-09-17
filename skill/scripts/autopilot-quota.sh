#!/usr/bin/env bash
# Sonde le quota Claude annoncé par Anthropic.
# verdict [fichier]      -> "<épuisé:0|1> <epoch|-> <fenêtre> <pourcentage>"
# reset-epoch [fichier]  -> epoch de la fenêtre la plus consommée, ou "-"
# Sans fichier, interroge l'API ; avec, lit le fichier (tests).
set -uo pipefail

USAGE_URL="https://api.anthropic.com/api/oauth/usage"
USAGE_BETA="oauth-2025-04-20"
KEYCHAIN_SERVICE="Claude Code-credentials"
SEUIL=95

jeton() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    sys.exit(1)
o=d.get("claudeAiOauth") or d
t=o.get("accessToken","")
if not t: sys.exit(1)
print(t)' 2>/dev/null
}

releve() {
  if [ $# -ge 1 ] && [ -n "$1" ]; then cat "$1"; return; fi
  tok=$(jeton) || return 1
  [ -n "$tok" ] || return 1
  curl -s --max-time 15 "$USAGE_URL" \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: $USAGE_BETA" \
    -H "User-Agent: autopilot (local)"
}

# Lit le relevé sur stdin, écrit "épuisé epoch fenêtre pourcentage".
analyse() {
  SEUIL="$SEUIL" python3 -c '
import sys, json, os, datetime

def epoch(v):
    if isinstance(v, (int, float)):
        return float(v) if v > 1e9 else None
    if not isinstance(v, str) or not v:
        return None
    try:
        return datetime.datetime.fromisoformat(
            v.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)

fenetres = []
for k in ("five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"):
    w = d.get(k)
    if isinstance(w, dict) and w.get("utilization") is not None:
        fenetres.append((k, w["utilization"], epoch(w.get("resets_at"))))
for lim in d.get("limits") or []:
    if isinstance(lim, dict) and lim.get("percent") is not None:
        fenetres.append((lim.get("kind") or "limite", lim["percent"],
                         epoch(lim.get("resets_at"))))

pire = (-1.0, None, "aucune")
for nom, pct, quand in fenetres:
    try:
        pct = float(pct)
    except (TypeError, ValueError):
        continue
    if pct > pire[0]:
        pire = (pct, quand, nom)

pct, quand, nom = pire
if pct < 0:
    print("0 - aucune 0")
    sys.exit(0)
seuil = float(os.environ["SEUIL"])
print("%d %s %s %g" % (1 if pct >= seuil else 0,
                       "%d" % quand if quand else "-", nom, pct))
'
}

cmd="${1:-verdict}"
src="${2:-}"

case "$cmd" in
  verdict)
    releve "$src" | analyse
    ;;
  reset-epoch)
    out=$(releve "$src" | analyse) || exit 1
    printf '%s\n' "$out" | awk '{print $2}'
    ;;
  *)
    printf 'usage: %s {verdict|reset-epoch} [fichier.json]\n' "$0" >&2
    exit 2
    ;;
esac
