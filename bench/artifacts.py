#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = "/tmp/pasadena/"
HEREDOC = re.compile(r"cat\s+>\s*(/tmp/pasadena/\S+)\s+<<-?\s*'?(\w+)'?\n(.*?)\n\2(?:\n|$)", re.S)


def newest_job(jobs_dir):
    jobs = []
    for meta_path in jobs_dir.glob("full-pasadena-*/bench-meta.json"):
        jobs.append((json.loads(meta_path.read_text())["createdAt"], meta_path.parent))
    if not jobs:
        sys.exit(f"bench: no full pasadena job in {jobs_dir} — run: npm run bench:pasadena")
    return max(jobs)[1]


def written_files(log):
    files = {}
    for line in log.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        content = (event.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            payload = block.get("input") or {}
            if block.get("name") == "Write" and str(payload.get("file_path", "")).startswith(ROOT):
                files[payload["file_path"]] = payload.get("content", "")
            elif block.get("name") == "Bash":
                for path, _, body in HEREDOC.findall(payload.get("command", "")):
                    files[path] = body
    return files


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs-dir", type=Path, default=REPO / ".bench/jobs")
    parser.add_argument("--job", type=Path)
    parser.add_argument("--out", type=Path, default=REPO / "bench/results/artifacts")
    args = parser.parse_args()

    job = args.job or newest_job(args.jobs_dir)
    count = 0
    for trial_dir in sorted(p for p in job.iterdir() if p.is_dir()):
        logs = [trial_dir / "agent/claude-code.txt"] if (trial_dir / "agent/claude-code.txt").exists() else []
        logs += sorted((trial_dir / "agent/sessions/projects").glob("*/*.jsonl"))
        files = {}
        for log in logs:
            files.update(written_files(log))
        base = (args.out / trial_dir.name).resolve()
        for path, body in files.items():
            target = (base / path[len(ROOT):]).resolve()
            if not target.is_relative_to(base):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body if body.endswith("\n") else body + "\n")
            count += 1
        for plan in sorted((trial_dir / "agent/sessions/plans").glob("*.md")):
            if plan.is_symlink() or not plan.is_file() or not plan.resolve().is_relative_to(trial_dir.resolve()):
                continue
            target = base / "plan-mode" / plan.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(plan.read_text(errors="replace"))
            count += 1
    print(f"bench: {count} files from {job.name} written to {args.out}")


if __name__ == "__main__":
    main()
