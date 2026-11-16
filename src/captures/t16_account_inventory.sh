#!/usr/bin/env bash
# T16 account inventory (2026-11-16; row 20 of "Outstanding actions"). No model call; reads the host,
# a lupin checkout and the old harness's own records, and writes nothing to any of them.
# It sizes the unprivileged account that D59 (the fleet) part 9 puts under the kernel and the engines
# on a production host (T16 spec, Section 12; framework Section 10.6). Three questions:
#   (a) what the account that runs the fleet today may do: its groups, its sudo rules, the Docker socket;
#   (b) how often the fleet really called sudo or docker in the last N days, directly and through
#       which scripts: this is the short sudoers list a dedicated account would need;
#   (c) which repositories the fleet works in, and who owns each .git and in what mode: this is the
#       cost of sharing an object store with a second account (core.sharedRepository=group).
# Two sources answer (b), reported side by side and never summed, since they overlap:
#   the hook logs    <lupin>/io/claude_code_hooks/logs/*tool_use-*.json (one file per hook payload;
#                    hook-events.jsonl beside them carries the tool's name and no command);
#   the transcripts  ~/.claude/projects/**/*.jsonl (every Bash call the engine made).
# Prints program names, subcommands, script paths and counts. Never a command line, an argument,
# an environment value or a file's content.
# A script's "calls" are read from its own text: it cannot say on which host a line runs. A script that also
# opens a remote shell is marked *, and its sudo and docker lines are to be read before they are counted.
# Usage: t16_account_inventory.sh <path to the lupin checkout> [days, default 30] [another repository ...]
#        t16_account_inventory.sh --self-test
set -u
if [ "${1:-}" = "--self-test" ]; then SELF_TEST=1; LUPIN=/nonexistent; DAYS=30
else
    SELF_TEST=0
    LUPIN=${1:?usage: t16_account_inventory.sh <path to the lupin checkout> [days] [another repository ...]}
    DAYS=${2:-30}
    shift; [ $# -gt 0 ] && shift
fi
hr()  { printf '\n== %s ==\n' "$1"; }
val() { printf '%-44s %s\n' "$1" "$2"; }

if [ "$SELF_TEST" -eq 0 ]; then
    hr "host"
    val host "$( hostname )"
    val clock "$( TZ=America/New_York date '+%Y-%m-%d %H:%M:%S %Z' )"
    val lupin_checkout "$LUPIN"
    val lupin_head "$( git -C "$LUPIN" rev-parse --short=9 HEAD 2>/dev/null || echo 'no git' )"
    val window_days "$DAYS"

    hr "(a) the account that runs the fleet today"
    val account "$( id -un )"
    val primary_group "$( id -gn )"
    val groups "$( id -nG )"
    val umask "$( umask )"
    val passwordless_sudo "$( sudo -n true 2>/dev/null && echo yes || echo no )"
    val docker_group "$( id -nG | tr ' ' '\n' | grep -qx docker && echo yes || echo no )"
    val linger "$( loginctl show-user "$( id -un )" --property=Linger 2>/dev/null || echo 'not read' )"
    echo "sudo rules for this account (sudo -n -l; no password is ever offered):"
    sudo -n -l 2>&1 | sed -n '/may run the following/,$p' | sed 's/^/    /' | cut -c1-200 | head -40
    [ "${PIPESTATUS[0]}" -ne 0 ] && echo "    (sudo -n -l refused: a password is required, or sudo is absent)"

    hr "(a) Docker on this host"
    val docker_socket "$( stat -c '%U:%G %a' /var/run/docker.sock 2>/dev/null || echo 'no socket at /var/run/docker.sock' )"
    val members_of_docker "$( getent group docker | cut -d: -f4 )"
    val members_of_sudo "$( getent group sudo | cut -d: -f4 )"
    if command -v docker >/dev/null 2>&1; then
        val docker_rootless "$( docker info --format '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless && echo yes || echo no )"
        val docker_contexts "$( docker context ls --format '{{.Name}}' 2>/dev/null | tr '\n' ' ' )"
        val containers_running "$( docker ps -q 2>/dev/null | wc -l )"
    else
        val docker "not installed, or not on this account's path"
    fi
    echo "accounts with an engine process now (count, account, program):"
    ps -eo user:32,comm --no-headers 2>/dev/null | grep -E ' (claude|agy|jetski|tmux[^ ]*)$' | sort | uniq -c | sed 's/^/    /' | head -20
fi

LUPIN="$LUPIN" DAYS="$DAYS" SELF_TEST="$SELF_TEST" python3 - "$@" <<'PYTHON'
import collections, json, os, re, shlex, subprocess, sys, time

LUPIN      = os.environ["LUPIN"]
DAYS       = int(os.environ["DAYS"])
SELF_TEST  = os.environ["SELF_TEST"] == "1"
HOME       = os.path.expanduser("~")
CUTOFF     = time.time() - DAYS * 86400
WRAPPERS   = {"env", "nohup", "time", "exec", "command", "stdbuf", "nice", "ionice", "setsid", "unbuffer"}
RUNNERS    = {"bash", "sh", "zsh", "dash", "source", ".", "python", "python3", "uv", "run"}
SEPARATOR  = re.compile(r"^[;&|()]+$")
REDIRECT   = re.compile(r"^[<>&|]*[<>][<>&|]*$")
HEREDOC    = re.compile(r"<<-?\s*(['\"]?)(\w+)\1.*?\n\s*\2\b", re.S)
STATIC     = re.compile(r"(^|[\s;&|(\"'\[`])(sudo|docker)([\s\"',\]]|$)")
REMOTE     = re.compile(r"(^|[\s;&|(\"'`])(ssh|scp|gcloud\s+compute\s+(ssh|scp))\s")
WORKTREE   = re.compile(r"^(.*?)/\.claude/worktrees/[^/]+(/.*)?$")

def hr(title): print("\n== %s ==" % title)
def val(name, value): print("%-44s %s" % (name, value))

def segments(command):
    """Split one shell command line into simple commands, each a list of words. Heredoc bodies are dropped."""
    command = HEREDOC.sub(" ", command).replace("\\\n", " ").replace("\n", " ; ")
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        tokens = re.split(r"\s+", re.sub(r"([;&|()]+)", r" \1 ", command))
    out, words, skip = [], [], False
    for token in tokens:
        if skip: skip = False; continue
        if SEPARATOR.match(token):
            if words: out.append(words)
            words = []
        elif REDIRECT.match(token):
            skip = True
            if words and words[-1].isdigit(): words.pop()
        elif token in ("$", "`", "{", "}", "then", "do", "else", "if", "while", "!"):
            if words: out.append(words)
            words = []
        else: words.append(token.strip("`"))
    if words: out.append(words)
    return out

def strip_prefix(words):
    """Drop VAR=value words and harmless wrappers (env, nohup, timeout 30, ...) from the front."""
    words = list(words)
    while words:
        head = os.path.basename(words[0])
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]): words.pop(0)
        elif head == "timeout":
            words.pop(0)
            while words and (words[0].startswith("-") or re.match(r"^[0-9.]+[smhd]?$", words[0])): words.pop(0)
        elif head == "command" and len(words) > 1 and words[1] in ("-v", "-V"): return []
        elif head in WRAPPERS:
            words.pop(0)
            while words and words[0].startswith("-"): words.pop(0)
        else: break
    return words

def after_flags(words, with_argument=()):
    """The first word that is not a flag; a flag listed in with_argument takes the next word too."""
    index = 0
    while index < len(words):
        word = words[index]
        if word in with_argument: index += 2
        elif word.startswith("-"): index += 1
        else: return words[index:]
    return []

def classify(words):
    """('sudo'|'docker', label) for a privileged call, ('script', word) for a script run, ('cd', path), or None."""
    words = strip_prefix(words)
    if not words: return None
    head = os.path.basename(words[0])
    if head == "sudo":
        rest = strip_prefix(after_flags(words[1:], ("-u", "-g", "-C", "-D", "-h", "-p", "-R", "-T", "-U")))
        if not rest: return ("sudo", "sudo (no program)")
        program = os.path.basename(rest[0])
        if program in ("docker", "docker-compose"):
            inner = classify(rest)
            return ("sudo", "sudo " + inner[1])
        if program in ("systemctl", "journalctl", "apt", "apt-get", "snap", "loginctl"):
            verb = after_flags(rest[1:])
            return ("sudo", "sudo %s %s" % (program, verb[0] if verb else ""))
        if re.search(r"\.(sh|py)$", program): return ("sudo", "sudo <script> " + program)
        return ("sudo", "sudo " + program)
    if head in ("docker", "docker-compose"):
        rest = after_flags(words[1:], ("-H", "--host", "-c", "--context", "--config", "-l", "--log-level"))
        verb = rest[0] if rest else "(none)"
        if head == "docker-compose" or verb == "compose":
            inner = after_flags(rest[1:] if head == "docker" else words[1:],
                                ("-f", "--file", "-p", "--project-name", "--env-file", "--profile", "--project-directory"))
            return ("docker", "docker compose " + (inner[0] if inner else "(none)"))
        if verb in ("container", "image", "volume", "network", "system", "buildx", "context"):
            return ("docker", "docker %s %s" % (verb, rest[1] if len(rest) > 1 else ""))
        return ("docker", "docker " + verb)
    if head == "cd" and len(words) > 1: return ("cd", words[1])
    index = 0
    while index < len(words) and (os.path.basename(words[index]) in RUNNERS or words[index].startswith("-")): index += 1
    if index < len(words) and re.search(r"\.(sh|py)$", words[index]): return ("script", words[index])
    return None

def self_test():
    def kinds(command): return [c for c in (classify(w) for w in segments(command)) if c and c[0] != "cd"]
    cases = [
        ("docker ps", [("docker", "docker ps")]),
        ("sudo -n systemctl restart lupin.service", [("sudo", "sudo systemctl restart")]),
        ("cd /x && FOO=1 timeout 30 docker compose -f a.yml up -d", [("docker", "docker compose up")]),
        ("sudo -u postgres psql -c 'select 1; docker'", [("sudo", "sudo psql")]),
        ("echo \"docker; sudo\" | grep docker", []),
        ("x=$(docker inspect -f '{{.State}}' lupin)", [("docker", "docker inspect")]),
        ("cat <<'EOF' > f\nsudo rm -rf /\ndocker ps\nEOF\nls", []),
        ("bash src/scripts/bounce-dev-server.sh --fast 2>&1 | tail -5", [("script", "src/scripts/bounce-dev-server.sh")]),
        ("sudo docker exec -it box sh", [("sudo", "sudo docker exec")]),
        ("docker-compose --env-file .env logs", [("docker", "docker compose logs")]),
        ("docker container ls -a; /usr/bin/docker image prune", [("docker", "docker container ls"), ("docker", "docker image prune")]),
        ("uv run python src/tests/x.py && ./run.sh", [("script", "src/tests/x.py"), ("script", "./run.sh")]),
        ("git commit -m \"stop using docker\"", []),
        ("sudo ./install.sh", [("sudo", "sudo <script> install.sh")]),
        ("command -v docker 2>/dev/null && echo yes", []),
        ("docker ps 2>/dev/null; docker 2>&1 info", [("docker", "docker ps"), ("docker", "docker info")]),
        ("which docker; type sudo", []),
    ]
    failed = 0
    for command, expected in cases:
        got = kinds(command)
        if got != expected:
            failed += 1
            print("FAIL %r\n  expected %r\n  got      %r" % (command, expected, got))
    print("self-test: %d cases, %d failed" % (len(cases), failed))
    sys.exit(1 if failed else 0)

if SELF_TEST: self_test()

# ---------- the two sources ----------
def from_hook_logs(directory):
    """(timestamp, cwd, tool, command or None) from the per-payload files the old harness's hooks write."""
    stats = collections.Counter()
    if not os.path.isdir(directory): return stats
    for entry in os.scandir(directory):
        if not entry.name.endswith(".json"): continue
        stats["payload_files"] += 1
        if "tool_use" not in entry.name: continue
        try:
            when = entry.stat().st_mtime
            if when < CUTOFF: continue
            stats["tool_payload_files_in_window"] += 1
            with open(entry.path, errors="replace") as handle: payload = (json.load(handle).get("payload") or {})
        except Exception:
            stats["unreadable"] += 1; continue
        tool = payload.get("tool_name", "")
        tool_input = payload.get("tool_input") or {}
        yield_rows.append((when, payload.get("cwd") or "", tool, tool_input.get("command") if tool == "Bash" else None,
                           "pre" if entry.name.startswith("pre") else "post"))
    return stats

def from_transcripts(root):
    stats = collections.Counter()
    if not os.path.isdir(root): return stats
    for folder, _, names in os.walk(root):
        for name in names:
            if not name.endswith(".jsonl"): continue
            path = os.path.join(folder, name)
            stats["transcript_files"] += 1
            try:
                if os.path.getmtime(path) < CUTOFF: continue
            except OSError: continue
            stats["transcript_files_in_window"] += 1
            try:
                with open(path, errors="replace") as handle:
                    for line in handle:
                        if '"tool_use"' not in line: continue
                        try: record = json.loads(line)
                        except Exception: continue
                        content = (record.get("message") or {}).get("content")
                        if not isinstance(content, list): continue
                        stamp = record.get("timestamp") or ""
                        try: when = time.mktime(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
                        except Exception: when = os.path.getmtime(path)
                        if when < CUTOFF: continue
                        for item in content:
                            if not isinstance(item, dict) or item.get("type") != "tool_use": continue
                            tool = item.get("name", "")
                            command = (item.get("input") or {}).get("command") if tool == "Bash" else None
                            yield_rows.append((when, record.get("cwd") or "", tool, command, "pre"))
            except OSError:
                stats["unreadable"] += 1
    return stats

# ---------- repositories and scripts ----------
toplevel_cache, static_cache = {}, {}

def main_checkout(path):
    """The main checkout a directory belongs to (a worktree resolves to its repository), or None."""
    if path in toplevel_cache: return toplevel_cache[path]
    result, probe = None, path
    while probe and not os.path.isdir(probe):
        gone = WORKTREE.match(probe)
        probe = gone.group(1) if gone else os.path.dirname(probe) if probe != os.path.dirname(probe) else ""
    if probe:
        try:
            common = subprocess.run(["git", "-C", probe, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                    capture_output=True, text=True, timeout=10).stdout.strip()
            if common: result = os.path.dirname(common) if os.path.basename(common) == ".git" else common
        except Exception: pass
    toplevel_cache[path] = result
    return result

def show(path):
    return "~" + path[len(HOME):] if path.startswith(HOME + "/") else path

def static_calls(path):
    """Which of sudo and docker a script's own text calls or names, comments left out: '', 'sudo', 'docker', 'sudo+docker'.
    A trailing * says the script also opens a remote shell (ssh, scp, gcloud compute ssh), so those lines may run on another host."""
    if path not in static_cache:
        found, remote = set(), False
        try:
            with open(path, errors="replace") as handle:
                for line in handle:
                    if line.lstrip().startswith("#"): continue
                    for match in STATIC.finditer(line): found.add(match.group(2))
                    if REMOTE.search(line): remote = True
        except OSError: found = {"unreadable"}
        static_cache[path] = "+".join(sorted(found, reverse=True)) + ("*" if remote and found and found != {"unreadable"} else "")
    return static_cache[path]

def working_tree(directory):
    """The top of the working tree a directory is in (a worktree's own top, not its repository's), or None."""
    key = ("top", directory)
    if key not in toplevel_cache:
        try: top = subprocess.run(["git", "-C", directory, "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=10).stdout.strip()
        except Exception: top = ""
        toplevel_cache[key] = top or None
    return toplevel_cache[key]

def resolve_script(word, cwd):
    word = word.replace("$HOME", HOME).replace("${HOME}", HOME)
    path = os.path.expanduser(word)
    if not os.path.isabs(path): path = os.path.join(cwd or "/", path)
    path = os.path.normpath(path)
    if not os.path.isfile(path):
        gone = WORKTREE.match(path)
        if gone and gone.group(2) and os.path.isfile(gone.group(1) + gone.group(2)): return gone.group(1) + gone.group(2)
        home = main_checkout(cwd) if cwd and not os.path.isabs(os.path.expanduser(word)) else None
        if home and os.path.isfile(os.path.normpath(os.path.join(home, word))): return os.path.normpath(os.path.join(home, word))
        return None
    return path

def tally(rows):
    result = {"bash": 0, "direct": collections.Counter(), "scripts": collections.Counter(), "missing": collections.Counter(),
              "repositories": collections.defaultdict(collections.Counter), "first": None, "last": None, "with_privilege": 0, "worktree_copies": 0}
    for when, cwd, tool, command, _ in rows:
        repository = main_checkout(cwd) if cwd else None
        key = repository or "(no repository: %s)" % (show(cwd) if cwd else "no directory recorded")
        if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"): result["repositories"][key]["edits"] += 1
        if command is None: continue
        result["bash"] += 1
        result["repositories"][key]["bash"] += 1
        result["first"] = when if result["first"] is None else min(result["first"], when)
        result["last"]  = when if result["last"]  is None else max(result["last"], when)
        here, privileged = cwd, False
        for words in segments(command):
            kind = classify(words)
            if not kind: continue
            if kind[0] == "cd":
                target = os.path.expanduser(kind[1].replace("$HOME", HOME))
                here = target if os.path.isabs(target) else os.path.normpath(os.path.join(here or "/", target))
            elif kind[0] in ("sudo", "docker"):
                result["direct"][kind[1].strip()] += 1; privileged = True
                result["repositories"][key][kind[0]] += 1
            else:
                path = resolve_script(kind[1], here)
                if path is None: result["missing"][os.path.basename(kind[1])] += 1; continue
                calls = static_calls(path)
                home, top = main_checkout(os.path.dirname(path)), working_tree(os.path.dirname(path))
                label = "%s:%s" % (os.path.basename(home), os.path.relpath(path, top)) if home and top else show(path)
                if home and top and os.path.realpath(top) != os.path.realpath(home): result["worktree_copies"] += 1
                result["scripts"][(label, calls)] += 1
                if calls and calls != "unreadable": privileged = True
        if privileged: result["with_privilege"] += 1
    return result

def stamp(when):
    if when is None: return "none"
    os.environ["TZ"] = "America/New_York"; time.tzset()
    return time.strftime("%Y-%m-%d %H:%M %Z", time.localtime(when))

def report(name, stats, result):
    hr("(b) sudo and docker in the last %d days, read from %s" % (DAYS, name))
    for key in sorted(stats): val(key, stats[key])
    val("bash_calls_in_window", result["bash"])
    val("first_and_last_call", "%s to %s" % (stamp(result["first"]), stamp(result["last"])))
    val("bash_calls_touching_sudo_or_docker", result["with_privilege"])
    print("called directly (count, what; the program and its subcommand only):")
    for label, count in sorted(result["direct"].items(), key=lambda item: (-item[1], item[0])): print("    %6d  %s" % (count, label))
    if not result["direct"]: print("    none")
    print("scripts run whose own text calls sudo or docker (count, which, script; a worktree's copy counts with the script;")
    print("  * = the script also opens a remote shell, so its sudo and docker lines may run on another host):")
    listed = [(count, calls, label) for (label, calls), count in result["scripts"].items() if calls and calls != "unreadable"]
    for count, calls, label in sorted(listed, key=lambda item: (-item[0], item[2])): print("    %6d  %-12s %s" % (count, calls, label))
    if not listed: print("    none")
    val("scripts_run_calling_neither", sum(count for (label, calls), count in result["scripts"].items() if not calls))
    val("distinct_scripts_run", len(result["scripts"]))
    val("script_runs_from_a_worktree_copy", result["worktree_copies"])
    val("script_runs_not_found_on_disk", "%d (%d names; a removed worktree, or a path set by a variable)" % (sum(result["missing"].values()), len(result["missing"])))
    return listed

yield_rows = []
hook_directory = os.environ.get("LUPIN_HOOK_LOG_DIR") or os.path.join(LUPIN, "io", "claude_code_hooks", "logs")
hook_stats = from_hook_logs(hook_directory)
hook_rows, yield_rows = yield_rows, []
# A Bash call writes a pre and a post payload; count each call once, from the pre files when there are any.
if any(row[4] == "pre" for row in hook_rows): hook_rows = [row for row in hook_rows if row[4] == "pre"]
transcript_stats = from_transcripts(os.path.join(HOME, ".claude", "projects"))
transcript_rows, yield_rows = yield_rows, []

events = os.path.join(hook_directory, "hook-events.jsonl")
hook_stats["directory"] = show(hook_directory) + ("" if os.path.isdir(hook_directory) else " (ABSENT)")
hook_stats["hook_events_jsonl_bytes"] = os.path.getsize(events) if os.path.isfile(events) else "absent"
hook_result       = tally(hook_rows)
transcript_result = tally(transcript_rows)
hook_listed       = report("the hook logs", hook_stats, hook_result)
transcript_listed = report("the transcripts (~/.claude/projects)", transcript_stats, transcript_result)

# ---------- the candidate sudoers list: scripts in the lupin checkout that drive Docker or sudo ----------
hr("(b) scripts in the lupin checkout whose text calls sudo or docker (the candidate sudoers list)")
runs = collections.Counter()
for listed in (transcript_listed,):
    for count, calls, label in listed: runs[label] += count
hook_runs = collections.Counter()
for count, calls, label in hook_listed: hook_runs[label] += count
static_rows, lupin_name = [], os.path.basename(os.path.normpath(LUPIN))
for folder, directories, names in os.walk(os.path.join(LUPIN, "src")):
    directories[:] = [d for d in directories if d not in ("node_modules", ".venv", "__pycache__", ".git", "rnd", "history")]
    for name in names:
        if not name.endswith(".sh"): continue
        path = os.path.join(folder, name)
        calls = static_calls(path)
        if calls and calls != "unreadable":
            relative = os.path.relpath(path, LUPIN)
            label = "%s:%s" % (lupin_name, relative)
            static_rows.append((relative, calls, runs.get(label, 0), hook_runs.get(label, 0)))
print("(* = the script also opens a remote shell: ssh, scp or gcloud compute ssh)")
print("%-58s %-12s %12s %10s" % ("script", "calls", "transcripts", "hook logs"))
for relative, calls, in_transcripts, in_hooks in sorted(static_rows): print("%-58s %-12s %12d %10d" % (relative[:58], calls, in_transcripts, in_hooks))
if not os.path.isdir(os.path.join(LUPIN, "src")): print("    (no src directory under %s)" % LUPIN)

# ---------- (c) the repositories ----------
hr("(c) repositories the fleet works in, and who owns each .git")
repositories = collections.OrderedDict()
def add(path, why):
    if path and os.path.isdir(path):
        home = main_checkout(path)
        if home: repositories.setdefault(home, set()).add(why)
add(LUPIN, "the lupin checkout")
for extra in sys.argv[1:]: add(os.path.abspath(extra), "named on the command line")
for result, why in ((hook_result, "hook logs"), (transcript_result, "transcripts")):
    for key in result["repositories"]:
        if not key.startswith("(no repository"): add(key, why)
configured = []
try:
    with open(os.path.join(LUPIN, "src", "conf", "lupin-app.ini"), errors="replace") as handle:
        for line in handle:
            match = re.match(r"^external repo (\S+) path\s*=\s*(\S+)", line)
            if match: configured.append((match.group(1), match.group(2)))
except OSError: pass
parent, not_found = os.path.dirname(os.path.normpath(LUPIN)), []
for name, container_path in configured:
    tail = container_path.split("/external-projects/", 1)[-1] if "/external-projects/" in container_path else os.path.basename(container_path)
    candidates = [os.path.join(parent, tail), os.path.join(parent, os.path.basename(tail)), container_path]
    hit = next((c for c in candidates if os.path.isdir(os.path.join(c, ".git")) or os.path.isfile(os.path.join(c, ".git"))), None)
    if hit: add(hit, "configured (external repo %s)" % name)
    else: not_found.append(name)

def git(path, *arguments):
    try: return subprocess.run(["git", "-C", path] + list(arguments), capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception: return ""

import grp, pwd, stat
def owner(status):
    try: user = pwd.getpwuid(status.st_uid).pw_name
    except KeyError: user = str(status.st_uid)
    try: group = grp.getgrgid(status.st_gid).gr_name
    except KeyError: group = str(status.st_gid)
    return user, group

totals = collections.Counter()
for path, reasons in repositories.items():
    git_directory = os.path.join(path, ".git")
    try: status = os.stat(git_directory)
    except OSError:
        print("\n%s\n    .git not readable" % show(path)); continue
    user, group = owner(status)
    counts, owners, groups = collections.Counter(), set(), set()
    for folder, directories, names in os.walk(git_directory):
        for name in directories + names:
            try: item = os.lstat(os.path.join(folder, name))
            except OSError: counts["unreadable"] += 1; continue
            item_user, item_group = owner(item)
            owners.add(item_user); groups.add(item_group)
            if stat.S_ISDIR(item.st_mode):
                counts["directories"] += 1
                if not item.st_mode & stat.S_IWGRP: counts["directories_not_group_writable"] += 1
                if not item.st_mode & stat.S_ISGID: counts["directories_without_setgid"] += 1
            elif stat.S_ISREG(item.st_mode):
                counts["files"] += 1
                if not item.st_mode & stat.S_IRGRP: counts["files_not_group_readable"] += 1
    worktrees = [line for line in git(path, "worktree", "list", "--porcelain").splitlines() if line.startswith("worktree ")]
    shared = git(path, "config", "--get", "core.sharedRepository") or "unset"
    activity = collections.Counter()
    for result in (transcript_result,): activity.update(result["repositories"].get(path, {}))
    print("\n%s" % show(path))
    print("    why listed                     %s" % ", ".join(sorted(reasons)))
    print("    .git owner:group mode          %s:%s %o" % (user, group, stat.S_IMODE(status.st_mode)))
    print("    owners | groups inside .git    %s | %s" % (",".join(sorted(owners)) or "-", ",".join(sorted(groups)) or "-"))
    print("    core.sharedRepository          %s" % shared)
    print("    worktrees (main included)      %d" % len(worktrees))
    print("    directories | not group-writable | without setgid   %d | %d | %d" % (counts["directories"], counts["directories_not_group_writable"], counts["directories_without_setgid"]))
    print("    files | not group-readable     %d | %d" % (counts["files"], counts["files_not_group_readable"]))
    print("    in the transcripts' window     %d bash calls, %d file edits, %d sudo, %d docker" % (activity["bash"], activity["edits"], activity["sudo"], activity["docker"]))
    totals["repositories"] += 1
    totals["worked_in"] += 1 if activity["bash"] or activity["edits"] else 0
    totals["shared_group"] += 1 if shared in ("group", "true", "1", "all", "world", "everybody") else 0
    totals["need_mode_repair"] += 1 if counts["directories_not_group_writable"] or counts["files_not_group_readable"] else 0
    totals["mixed_owners"] += 1 if len(owners) > 1 else 0
    totals["worktrees"] += len(worktrees)
elsewhere = [(key, counter) for key, counter in transcript_result["repositories"].items() if key.startswith("(no repository")]
if elsewhere:
    print("\nwork recorded outside any repository (bash calls, file edits, where):")
    for key, counter in sorted(elsewhere, key=lambda item: -item[1]["bash"])[:15]: print("    %6d %6d  %s" % (counter["bash"], counter["edits"], key))
val("\nconfigured_repositories_not_on_this_host", "%d of %d: %s" % (len(not_found), len(configured), " ".join(not_found) or "-"))

hr("summary")
val("account_privileged", "see (a): passwordless_sudo and docker_group")
for name, result, listed in (("hook_logs", hook_result, hook_listed), ("transcripts", transcript_result, transcript_listed)):
    val(name + "_bash_calls", result["bash"])
    val(name + "_direct_sudo_calls", sum(count for label, count in result["direct"].items() if label.startswith("sudo")))
    val(name + "_direct_docker_calls", sum(count for label, count in result["direct"].items() if label.startswith("docker")))
    val(name + "_distinct_direct_forms", len(result["direct"]))
    val(name + "_privileged_scripts_run", "%d scripts, %d runs" % (len(listed), sum(count for count, _, _ in listed)))
    val(name + "_of_those_with_no_remote_shell", "%d scripts, %d runs" % (sum(1 for _, calls, _ in listed if not calls.endswith("*")), sum(count for count, calls, _ in listed if not calls.endswith("*"))))
val("lupin_scripts_calling_sudo_or_docker", len(static_rows))
val("of_those_run_in_the_window", sum(1 for row in static_rows if row[2] or row[3]))
val("repositories_listed", totals["repositories"])
val("repositories_worked_in_in_the_window", totals["worked_in"])
val("repositories_already_group_shared", totals["shared_group"])
val("repositories_needing_a_mode_repair", totals["need_mode_repair"])
val("repositories_with_more_than_one_owner", totals["mixed_owners"])
val("worktrees_in_all", totals["worktrees"])
PYTHON
