#!/usr/bin/env bash
# Sonde le quota Claude annoncé par Anthropic.
# verdict [fichier]      -> "<épuisé:0|1> <epoch|-> <fenêtre> <pourcentage>"
# reset-epoch [fichier]  -> epoch auquel se réveiller, ou "-"
# Sans fichier, interroge l'API ; avec, lit le fichier (tests).
#
# Deux questions distinctes, et jamais confondues :
#   « épuisé ? »          -> au moins une fenêtre atteint le seuil (SEUIL %) ;
#   « quand se réveiller ? » -> le resets_at le PLUS PROCHE parmi les seules
#                            fenêtres bloquantes — pas celui de la fenêtre la
#                            plus consommée, qui peut être à six jours alors
#                            qu'une fenêtre bloquante rouvre dans une heure.
# Un relevé sans aucune fenêtre exploitable (réponse 401, endpoint modifié,
# toutes les fenêtres nulles) est une sonde EN PANNE : code de sortie non nul,
# jamais « compte sain ».
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
    sys.stderr.write("sonde de quota : relevé illisible (JSON invalide)\n")
    sys.exit(1)
if not isinstance(d, dict):
    sys.stderr.write("sonde de quota : relevé illisible (objet JSON attendu)\n")
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

exploitables = []
for nom, pct, quand in fenetres:
    try:
        exploitables.append((nom, float(pct), quand))
    except (TypeError, ValueError):
        continue

if not exploitables:
    sys.stderr.write(
        "sonde de quota : aucune fenêtre exploitable dans le relevé "
        "(jeton expiré, endpoint modifié, ou réponse en erreur) — "
        "sonde traitée comme EN PANNE, pas comme un compte sain\n")
    sys.exit(1)

seuil = float(os.environ["SEUIL"])
bloquantes = [f for f in exploitables if f[1] >= seuil]

if bloquantes:
    # Quand se réveiller : le reset le plus proche parmi les fenêtres
    # bloquantes. Une bloquante sans resets_at ne peut pas servir de
    # réveil ; on se rabat alors sur la plus consommée des bloquantes.
    datees = [f for f in bloquantes if f[2] is not None]
    if datees:
        nom, pct, quand = min(datees, key=lambda f: f[2])
    else:
        nom, pct, quand = max(bloquantes, key=lambda f: f[1])
    epuise = 1
else:
    # Compte utilisable : on rapporte la fenêtre la plus consommée, à titre
    # indicatif. Son epoch ne sert alors de réveil à personne.
    nom, pct, quand = max(exploitables, key=lambda f: f[1])
    epuise = 0

print("%d %s %s %g" % (epuise, "%d" % quand if quand else "-", nom, pct))
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
