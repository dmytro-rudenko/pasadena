#!/usr/bin/env python3
import argparse
import json
import math
import os
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
INFRA_TYPES = {"PasadenaPluginMissingError", "TuiStartError", "TuiApiError"}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 0.0
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0.0, c - h), min(1.0, c + h)


def model_usage(trial_dir):
    log = trial_dir / "agent" / "claude-code.txt"
    if not log.is_file():
        return {}
    usage = Counter()
    with log.open(encoding="utf-8", errors="replace") as lines:
        for line in lines:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict) or event.get("type") != "result":
                continue
            models = event.get("modelUsage")
            if isinstance(models, dict):
                for model, tokens in models.items():
                    inputs = tokens.get("inputTokens") or 0
                    outputs = tokens.get("outputTokens") or 0
                    usage[model] += inputs + outputs
    return usage


def parse_timestamp(timestamp):
    if timestamp.endswith("Z"):
        timestamp = timestamp[:-1] + "+00:00"
    return datetime.fromisoformat(timestamp)


def load_trials(job):
    trials = []
    for path in sorted(job.glob("*/result.json")):
        result = read_json(path)
        exception = (result.get("exception_info") or {}).get("exception_type")
        infra = exception in INFRA_TYPES
        valid = bool(result.get("reward_valid")) and not infra
        rewards = (result.get("verifier_result") or {}).get("rewards") or {}
        reward = rewards.get("reward", next(iter(rewards.values()), 0))
        agent = result.get("agent_result") or {}
        execution = result.get("agent_execution") or {}
        started = execution.get("started_at")
        finished = execution.get("finished_at")
        seconds = None
        if started and finished:
            seconds = (parse_timestamp(finished) - parse_timestamp(started)).total_seconds()
        trials.append({
            "task": result["task_name"],
            "valid": valid,
            "passed": valid and float(reward) >= 1.0,
            "plugin_missing": exception == "PasadenaPluginMissingError",
            "in": agent.get("n_input_tokens") or 0,
            "out": agent.get("n_output_tokens") or 0,
            "cost": agent.get("cost_usd"),
            "secs": seconds,
            "models": model_usage(path.parent),
        })
    return trials


def pick(jobs_dir, arm):
    jobs = []
    for job in jobs_dir.glob(f"full-{arm}-*"):
        meta = job / "bench-meta.json"
        if meta.is_file():
            jobs.append((read_json(meta), job))
    if not jobs:
        sys.exit(f"bench: no full {arm} job in {jobs_dir} — run: npm run bench:{arm}")
    return max(jobs, key=lambda job: job[0]["createdAt"])


def task_counts(trials):
    counts = defaultdict(lambda: [0, 0])
    for trial in trials:
        if trial["valid"]:
            task = counts[trial["task"]]
            task[0] += trial["passed"]
            task[1] += 1
    return counts


def fraction(passed, total):
    return passed / total if total else 0.0


def arm_summary(arm, trials, task_total):
    counts = task_counts(trials)
    passed = sum(k for k, _ in counts.values())
    valid = sum(n for _, n in counts.values())
    rate = fraction(passed, valid)
    lower, upper = wilson(passed, valid)
    pass_at_one = statistics.mean(k / n for k, n in counts.values()) if counts else 0.0
    pass_at_k = fraction(sum(k > 0 for k, _ in counts.values()), task_total)
    inputs = sum(trial["in"] for trial in trials)
    outputs = sum(trial["out"] for trial in trials)
    costs = [trial["cost"] for trial in trials if trial["cost"] is not None]
    durations = [trial["secs"] for trial in trials if trial["secs"] is not None]
    cost = f"{sum(costs):.2f}" if costs else "—"
    median = f"{statistics.median(durations):.1f}" if durations else "—"
    row = (
        f"| {arm} | {passed}/{valid} ({rate:.1%}) | {lower * 100:.1f}–{upper:.1%} | "
        f"{pass_at_one:.1%} | {pass_at_k:.1%} | {len(trials) - valid} | "
        f"{inputs}/{outputs} | {cost} | {median} |"
    )
    return {"row": row, "counts": counts, "valid": valid, "rate": rate, "interval": (lower, upper)}


def build_report(jobs):
    config_path = Path(os.getenv("BENCH_CONFIG") or REPO / "bench" / "config.json")
    plugin_root = Path(os.getenv("BENCH_PLUGIN_ROOT") or REPO)
    config = read_json(config_path)
    version = read_json(plugin_root / ".claude-plugin" / "plugin.json")["version"]
    pasadena_meta = jobs[1][0]
    tasks = set(pasadena_meta["tasks"])
    if tasks == {"*"}:
        tasks = {trial["task"] for _, _, trials in jobs for trial in trials}
    dirty = ", dirty" if pasadena_meta["gitDirty"] else ""
    lines = [
        "# Pasadena vs baseline",
        "",
        f"- дата: {datetime.now(timezone.utc).isoformat()}",
        f"- dataset: {config['dataset']}, model: {config['model']}, attempts: {pasadena_meta['attempts']}, "
        f"claude code: {config['claudeCodeVersion']}",
        f"- плагін: pasadena {version} (git {pasadena_meta['gitSha'][:7]}{dirty})",
        f"- задач: {len(tasks)}",
    ]

    warnings = []
    summaries = []
    model_rows = []
    plugin_missing = 0
    for meta, job, trials in jobs:
        arm = meta["arm"]
        summaries.append(arm_summary(arm, trials, len(tasks)))
        expected = len(tasks) * meta["attempts"]
        if meta["gitDirty"]:
            warnings.append(f"job {job.name}: git dirty")
        if len(trials) < expected:
            warnings.append(f"job {job.name} незавершений ({len(trials)} з {expected} trial)")
        plugin_missing += sum(trial["plugin_missing"] for trial in trials)
        usage = Counter()
        for trial in trials:
            usage.update(trial["models"])
        models = ", ".join(f"{model}={tokens}" for model, tokens in sorted(usage.items()))
        model_rows.append(f"- {arm}: {models or 'недоступно'}")

    baseline, pasadena = summaries
    baseline_valid, pasadena_valid = baseline["valid"], pasadena["valid"]
    largest_count = max(baseline_valid, pasadena_valid)
    if plugin_missing:
        warnings.append(f"плагін pasadena не встановився в {plugin_missing} trial")
    if largest_count and abs(baseline_valid - pasadena_valid) / largest_count > 0.10:
        warnings.append(f"кількість валідних trial різниться ({baseline_valid} проти {pasadena_valid})")
    for warning in warnings:
        lines.extend(["", f"УВАГА: {warning}"])

    delta = f"{100 * (pasadena['rate'] - baseline['rate']):+.1f}".replace("-", "−")
    lines.extend([
        "",
        "## Arms",
        "",
        "| arm | pass rate | 95% Wilson | pass@1 | pass@k | infra error | токени in/out | "
        "вартість, $ | медіана trial, с |",
        "|" + " --- |" * 9,
        baseline["row"],
        pasadena["row"],
        "",
        f"Δ pass rate (pasadena − baseline): {delta} п.п.",
        "",
        "## Задачі",
        "",
        "| задача | baseline x/k | pasadena x/k | Δ |",
        "| --- | --- | --- | --- |",
    ])
    outcomes = Counter()
    for task in sorted(tasks):
        b_passed, b_valid = baseline["counts"].get(task, (0, 0))
        p_passed, p_valid = pasadena["counts"].get(task, (0, 0))
        b_rate = fraction(b_passed, b_valid)
        p_rate = fraction(p_passed, p_valid)
        if p_rate > b_rate:
            outcome = "+"
        elif p_rate < b_rate:
            outcome = "−"
        else:
            outcome = "="
        outcomes[outcome] += 1
        lines.append(f"| {task} | {b_passed}/{b_valid} | {p_passed}/{p_valid} | {outcome} |")
    lines.extend([
        "",
        f"Виграші: {outcomes['+']}, програші: {outcomes['−']}, нічиї: {outcomes['=']}",
        "",
        "## Моделі",
        "",
        *model_rows,
        "",
    ])

    b_low, b_high = baseline["interval"]
    p_low, p_high = pasadena["interval"]
    if baseline_valid and pasadena_valid and (b_high < p_low or p_high < b_low):
        verdict = "різниця значуща (інтервали Wilson не перетинаються)."
    else:
        verdict = f"різниця в межах шуму при N={baseline_valid + pasadena_valid} валідних trial."
    lines.append(f"**Вердикт:** {verdict}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    bench_dir = Path(os.getenv("BENCH_DIR") or REPO / ".bench")
    parser.add_argument("--jobs-dir", type=Path, default=bench_dir / "jobs")
    parser.add_argument("--out", type=Path, default=REPO / "bench" / "results" / "summary.md")
    parser.add_argument("--failed", type=Path)
    parser.add_argument("--max", type=int)
    args = parser.parse_args()

    if args.failed is not None:
        if args.max is None or args.max < 0:
            parser.error("--failed requires a non-negative --max")
        trials = load_trials(args.failed)
        if not trials:
            sys.exit(f"bench: no trials in {args.failed}")
        failed = sorted(task for task, (passed, _) in task_counts(trials).items() if not passed)
        for task in failed[:args.max]:
            print(task)
        return

    baseline, baseline_job = pick(args.jobs_dir, "baseline")
    pasadena, pasadena_job = pick(args.jobs_dir, "pasadena")
    if set(baseline["tasks"]) != set(pasadena["tasks"]):
        sys.exit("bench: baseline and pasadena differ in tasks")
    if baseline.get("agent", "headless") != pasadena.get("agent", "headless"):
        sys.exit("bench: baseline and pasadena differ in agent")
    for field in ("attempts", "claudeCodeVersion"):
        if baseline[field] != pasadena[field]:
            sys.exit(f"bench: baseline and pasadena differ in {field}")

    report = build_report([
        (baseline, baseline_job, load_trials(baseline_job)),
        (pasadena, pasadena_job, load_trials(pasadena_job)),
    ])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report, encoding="utf-8")
    print(args.out)


if __name__ == "__main__":
    main()
