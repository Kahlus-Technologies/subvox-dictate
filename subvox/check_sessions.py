"""Check Subvox Dictate sessions: is each one usable training data?

    python3 subvox/check_sessions.py            # all *-dictation sessions
    python3 subvox/check_sessions.py <dir>...   # specific sessions

Per session: audio length, motion samples and rate, motion coverage of the audio, word count and whether
every word falls inside the audio. Exit code 1 if any session has a problem. Standard library only.
"""
import json, pathlib, sys

root = pathlib.Path.home() / "Documents/Subvox/Sessions"
dirs = [pathlib.Path(a) for a in sys.argv[1:]] or sorted(root.glob("*-dictation"))
bad = 0
for d in dirs:
    problems = []
    try:
        meta = json.loads((d / "meta.json").read_text())
        words = json.loads((d / "words.json").read_text())["words"]
        dur = meta["durationSeconds"]
        rows = (d / "motion.csv").read_text().strip().split("\n")[1:]
        t = [float(r.split(",", 1)[0]) for r in rows]
    except Exception as e:  # missing or corrupt file
        print(f"{d.name}: BROKEN ({e})"); bad += 1; continue
    rate = (len(t) - 1) / (t[-1] - t[0]) if len(t) > 1 and t[-1] > t[0] else 0
    cover = (min(t[-1], dur) - max(t[0], 0)) / dur if t and dur else 0
    if not t: problems.append("no motion (AirPods not connected?)")
    elif rate < 20: problems.append(f"motion rate {rate:.0f} Hz")
    elif cover < 0.9: problems.append(f"motion covers {cover:.0%} of audio")
    if not words: problems.append("no words")
    elif words[0]["start"] < -0.05 or words[-1]["end"] > dur + 0.05: problems.append("word times outside audio")
    print(f"{d.name}: {dur:5.1f}s audio, {len(t):4d} motion @ {rate:4.0f} Hz, {len(words):3d} words"
          + (f"  PROBLEM: {'; '.join(problems)}" if problems else "  ok"))
    bad += bool(problems)
print(f"{len(dirs)} sessions, {bad} with problems")
sys.exit(1 if bad else 0)
