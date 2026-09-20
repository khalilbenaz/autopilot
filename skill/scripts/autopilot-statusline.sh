#!/usr/bin/env bash
# Statusline autopilot : affichée par Claude Code dans TOUTES les sessions
# (voir ~/.claude/settings.json, bloc "statusLine"). Reçoit un objet JSON
# sur son entrée standard, avec des champs souvent absents ou null tant
# qu'aucun appel API n'a eu lieu.
#
# Contrat à respecter à la lettre :
#   - jamais de réseau, jamais d'appel API : lecture de fichiers et git
#     léger seulement ;
#   - un code de sortie non nul casse l'affichage pour toute la session,
#     donc on sort TOUJOURS en 0, quoi qu'il arrive (JSON vide, invalide,
#     champ manquant, exception) ;
#   - chaque ligne imprimée reste sous 150 caractères ;
#   - hors d'un run autopilot (pas de .autopilot/STATE.json dans le
#     répertoire courant de la session), une seule ligne compacte : la
#     statusline s'affiche partout, elle ne doit rien ajouter d'inutile
#     aux sessions qui n'ont rien à voir avec autopilot.
#
# Le code JSON est passé à python3 via -c (argument), jamais via un
# heredoc redirigé sur son entrée standard : sys.stdin doit rester
# branché sur le VRAI JSON reçu par ce script, pas sur le texte du
# programme lui-même.
set -uo pipefail

code_python=$(cat <<'PYEOF'
import sys, os, json, time, re, subprocess, tempfile

VERT = "\033[32m"
JAUNE = "\033[33m"
ROUGE = "\033[31m"
RESET = "\033[0m"
SEUIL_JAUNE = 70
SEUIL_ROUGE = 90
LARGEUR_JAUGE = 10

PHASES = {
    "init": ("0", "amorçage"),
    "conception": ("2", "conception"),
    "plan": ("3", "plan"),
    "execution": ("4", "exécution"),
    "revue": ("6", "revue"),
    "verification": ("8", "vérification"),
    "termine": ("9", "terminé"),
    "bloque": ("—", "bloqué"),
}

RE_TACHE_NOMMEE = re.compile(r"(?:t[aàâ]che|task)\s*#?\s*(\d+)", re.IGNORECASE)
RE_TACHE_NUE = re.compile(r"^\s*(\d+)\b")
RE_TITRE_TACHE = re.compile(r"^###\s*task\b", re.IGNORECASE | re.MULTILINE)


def get(d, *chemin, default=None):
    cur = d
    for c in chemin:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(c)
    return default if cur is None else cur


def nombre(v):
    try:
        if v is None:
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def couleur(pct):
    if pct is None:
        return ""
    if pct > SEUIL_ROUGE:
        return ROUGE
    if pct >= SEUIL_JAUNE:
        return JAUNE
    return VERT


def colore(texte, pct):
    c = couleur(pct)
    return (c + texte + RESET) if c else texte


def duree(secondes):
    if secondes is None:
        return "n/d"
    s = int(secondes)
    if s <= 0:
        return "imminent"
    jours, reste = divmod(s, 86400)
    heures, reste = divmod(reste, 3600)
    minutes = reste // 60
    if jours > 0:
        return "%dj%dh" % (jours, heures)
    if heures > 0:
        return "%dh%02d" % (heures, minutes)
    return "%dmin" % max(minutes, 1)


def jauge(pct):
    if pct is None:
        return "[" + "?" * LARGEUR_JAUGE + "]"
    r = int(round(max(0.0, min(100.0, pct)) / 100.0 * LARGEUR_JAUGE))
    return "[" + "#" * r + "-" * (LARGEUR_JAUGE - r) + "]"


def pourcent(pct):
    return "n/d" if pct is None else "%d%%" % round(pct)


def lire_json(chemin):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def ecrire_json(chemin, contenu):
    try:
        tmp = chemin + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(contenu, f)
        os.replace(tmp, chemin)
    except OSError:
        pass


def sanitize(nom):
    return re.sub(r"[^A-Za-z0-9_-]", "_", nom or "session") or "session"


def numero_tache(tache):
    """Numéro de la tâche courante, extrait du libellé écrit par autopilot
    dans STATE.json (ex. "Task 3: Geometrie", "Tâche 2 : bidule", "5").
    Rend None si aucun numéro n'est reconnaissable — jamais 0 par défaut,
    pour ne jamais fabriquer un dénominateur ou un numérateur inventés."""
    if not tache:
        return None
    m = RE_TACHE_NOMMEE.search(tache)
    if m:
        return int(m.group(1))
    m = RE_TACHE_NUE.match(tache)
    if m:
        return int(m.group(1))
    return None


def total_taches(chemin_plan):
    """Nombre de titres "### Task" dans le fichier de plan, ou None si le
    fichier est introuvable/illisible ou n'en contient aucun."""
    if not chemin_plan:
        return None
    try:
        with open(chemin_plan, encoding="utf-8") as f:
            contenu = f.read()
    except OSError:
        return None
    n = len(RE_TITRE_TACHE.findall(contenu))
    return n if n > 0 else None


def resoudre_plan(repo_dir, plan_chemin):
    if not plan_chemin:
        return None
    if os.path.isabs(plan_chemin):
        return plan_chemin
    return os.path.join(repo_dir, plan_chemin)


def main():
    brut = sys.stdin.read()
    try:
        entree = json.loads(brut) if brut.strip() else {}
        if not isinstance(entree, dict):
            entree = {}
    except ValueError:
        entree = {}

    repo_dir = (get(entree, "workspace", "current_dir")
                or get(entree, "cwd")
                or os.getcwd())
    session_id = sanitize(get(entree, "session_id"))
    modele = get(entree, "model", "display_name", default="?")

    rl = entree.get("rate_limits")
    rl = rl if isinstance(rl, dict) else {}
    cinq_h = nombre(get(rl, "five_hour", "used_percentage"))
    cinq_h_reset = nombre(get(rl, "five_hour", "resets_at"))
    sept_j = nombre(get(rl, "seven_day", "used_percentage"))
    sept_j_reset = nombre(get(rl, "seven_day", "resets_at"))

    ctx = entree.get("context_window")
    ctx = ctx if isinstance(ctx, dict) else {}
    ctx_pct = nombre(ctx.get("used_percentage"))

    cout = entree.get("cost")
    cout = cout if isinstance(cout, dict) else {}
    cout_usd = nombre(cout.get("total_cost_usd"))

    maintenant = time.time()

    def reset_dans(reset_epoch):
        return None if reset_epoch is None else reset_epoch - maintenant

    autopilot_dir = os.path.join(repo_dir, ".autopilot")
    state_path = os.path.join(autopilot_dir, "STATE.json")
    en_run = os.path.isfile(state_path)

    # --- projection d'épuisement : relevé précédent vs relevé courant ---
    if en_run:
        cache_path = os.path.join(autopilot_dir, ".statusline-cache.json")
    else:
        cache_path = os.path.join(
            tempfile.gettempdir(), "autopilot-statusline-%s.json" % session_id)
    precedent = lire_json(cache_path)
    precedent = precedent if isinstance(precedent, dict) else {}
    projections = []
    for cle, pct in (("5h", cinq_h), ("7j", sept_j)):
        prev = precedent.get(cle)
        if isinstance(prev, dict) and pct is not None and prev.get("pct") is not None:
            ecoule = maintenant - float(prev.get("ts", maintenant))
            delta = pct - float(prev["pct"])
            if ecoule > 0 and delta > 0:
                rythme = delta / ecoule
                restant = max(0.0, 100.0 - pct)
                if restant <= 0:
                    projections.append("%s déjà épuisée" % cle)
                else:
                    projections.append(
                        "%s épuisée dans %s" % (cle, duree(restant / rythme)))
    nouveau_cache = dict(precedent)
    if cinq_h is not None:
        nouveau_cache["5h"] = {"ts": maintenant, "pct": cinq_h}
    if sept_j is not None:
        nouveau_cache["7j"] = {"ts": maintenant, "pct": sept_j}
    ecrire_json(cache_path, nouveau_cache)

    lignes = []

    # --- ligne de base : partout, dans toutes les sessions ---
    base = "%s · 5h %s (reset %s) · 7j %s (reset %s) · ctx %s · %s" % (
        modele,
        colore(pourcent(cinq_h), cinq_h), duree(reset_dans(cinq_h_reset)),
        colore(pourcent(sept_j), sept_j), duree(reset_dans(sept_j_reset)),
        pourcent(ctx_pct),
        ("$%.2f" % cout_usd) if cout_usd is not None else "n/d",
    )
    lignes.append(base)

    if en_run:
        etat_data = lire_json(state_path)
        etat_data = etat_data if isinstance(etat_data, dict) else {}
        phase = etat_data.get("phase") or "?"
        tache = etat_data.get("tache") or ""
        branche = etat_data.get("branche") or "—"
        worktree = etat_data.get("worktree") or ""
        cycles = etat_data.get("cycles")
        plan_chemin = etat_data.get("plan") or ""

        etape, libelle = PHASES.get(phase, ("?", phase))

        if phase == "termine":
            etat = "terminé"
        elif phase == "bloque":
            etat = "bloqué"
        elif os.path.isfile(os.path.join(autopilot_dir, "QUOTA_ALERTE")):
            etat = "en attente de reset"
        else:
            etat = "en cours"

        # N/M : numéro de la tâche courante sur nombre de tâches du plan.
        # Jamais de fraction inventée : sans numéro reconnaissable ou sans
        # plan exploitable, on retombe sur le libellé brut, ou rien.
        num = numero_tache(tache)
        chemin_plan = resoudre_plan(repo_dir, plan_chemin)
        total = total_taches(chemin_plan) if chemin_plan else None
        if num is not None and total is not None:
            tache_txt = "tâche %d/%d" % (num, total)
        elif tache:
            tache_txt = "tâche : %s" % tache
        else:
            tache_txt = "tâche : —"

        lignes.append(
            "phase %s (étape %s) · %s · état : %s"
            % (libelle, etape, tache_txt, etat))

        commits = "?"
        git_dir = worktree if worktree and os.path.isdir(worktree) else repo_dir
        try:
            r = subprocess.run(
                ["git", "-C", git_dir, "rev-list", "--count", branche],
                capture_output=True, text=True, timeout=1)
            if r.returncode == 0:
                sortie_git = r.stdout.strip()
                commits = sortie_git if sortie_git else "?"
        except (OSError, subprocess.SubprocessError):
            pass

        ligne3 = "branche %s" % branche
        if worktree:
            ligne3 += " · worktree %s" % worktree
        ligne3 += " · cycles %s · commits %s" % (
            cycles if cycles is not None else "—", commits)
        lignes.append(ligne3)

        lignes.append("5h %s %s  7j %s %s" % (
            jauge(cinq_h), colore(pourcent(cinq_h), cinq_h),
            jauge(sept_j), colore(pourcent(sept_j), sept_j)))

        if projections:
            lignes.append("à ce rythme, " + " · ".join(projections))

    sys.stdout.write("\n".join(lignes) + "\n")


try:
    main()
except Exception:
    # Une statusline qui plante ne doit jamais casser la session : on
    # avale l'exception, le code de sortie global reste 0 (voir plus bas).
    pass
PYEOF
)

python3 -c "$code_python"
exit 0
