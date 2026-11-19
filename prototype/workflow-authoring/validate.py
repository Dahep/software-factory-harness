#!/usr/bin/env python3
"""PROTOTYPE validator — the checks a harness would run before accepting a Workflow.

Usage: python3 validate.py [workflow.yaml] [--json]
"""
import json
import sys

import yaml

KNOW = {"retry", "returnTo", "max", "then", "open_issue"}
THEN = {"block", "wait_for_owner"}


def fail(problems, msg):
    problems.append(msg)


def main(argv):
    path = next((a for a in argv if not a.startswith("-")), "default-loop.yaml")
    emit_json = "--json" in argv
    with open(path) as f:
        wf = yaml.safe_load(f)
    problems = []

    # envelope
    env = wf.get("envelope") or {}
    if not env:
        fail(problems, "envelope: missing (a Workflow must declare its Project Envelope)")
    else:
        if env.get("clone") is not True:
            fail(problems, "envelope.clone: must be true (the real repo is never mounted)")
        net = env.get("network") or {}
        if net.get("tier") not in {"open", "internet", "allowlist", "none"}:
            fail(problems, f"envelope.network.tier: invalid {net.get('tier')!r}")
        if net.get("tier") == "allowlist" and not net.get("allow"):
            fail(problems, "envelope.network.allow: allowlist tier needs at least one host")
        if not env.get("secrets"):
            fail(problems, "envelope.secrets: at least one bound secret is required")

    stages = wf.get("stages") or []
    ids = [s.get("id") for s in stages]
    if len(ids) != len(set(ids)):
        fail(problems, f"stages: duplicate ids {ids}")
    known_stages = set(ids)

    # checkpoints
    checkpoints = wf.get("checkpoints") or {}
    for name, cp in checkpoints.items():
        if cp.get("stage") not in known_stages:
            fail(problems, f"checkpoints.{name}.stage: {cp.get('stage')!r} is not a stage")

    # stages
    measured_stages = set()
    for s in stages:
        sid = s.get("id", "?")
        if not s.get("measure"):
            fail(problems, f"stage {sid}: no measure declared (directive #15: unmeasured stage)")
        else:
            measured_stages.add(sid)
        wave = s.get("wave") or {}
        for a in wave.get("agents", []):
            if a.get("role") not in {"triager", "implementer", "reviewer"}:
                fail(problems, f"stage {sid}: agent role {a.get('role')!r} unknown")
        for g in s.get("gates") or []:
            gid = f"{sid}.{g.get('id', '?')}"
            on_fail = g.get("onFail")
            if not on_fail:
                fail(problems, f"gate {gid}: missing onFail (every gate must say what failure does)")
                continue
            unknown = set(on_fail) - KNOW
            if unknown:
                fail(problems, f"gate {gid}: unknown onFail keys {sorted(unknown)}")
            if on_fail.get("then") and on_fail["then"] not in THEN:
                fail(problems, f"gate {gid}: then must be one of {sorted(THEN)}")
            if "returnTo" in on_fail and on_fail["returnTo"] not in known_stages:
                fail(problems, f"gate {gid}: returnTo {on_fail['returnTo']!r} is not a stage")
            if "returnTo" in on_fail and "max" not in on_fail:
                fail(problems, f"gate {gid}: returnTo without max (unbounded loops are banned)")
        if s.get("checkpoint") and s["checkpoint"] not in checkpoints:
            fail(problems, f"stage {sid}: checkpoint {s['checkpoint']!r} is not declared")
        if s.get("action", {}).get("pr", {}).get("merge") not in {None, "squash", "merge", "rebase"}:
            fail(problems, f"stage {sid}: unsupported merge method")

    result = {
        "workflow": wf.get("metadata", {}).get("name"),
        "stages": ids,
        "measured": sorted(measured_stages),
        "checkpoints": sorted(checkpoints),
        "ok": not problems,
        "problems": problems,
    }
    if emit_json:
        print(json.dumps(result, indent=2))
    else:
        print(f"workflow: {result['workflow']}")
        print(f"stages:   {' -> '.join(ids)}")
        print(f"measured: {', '.join(result['measured']) or '(none)'}")
        print(f"checkpoints: {', '.join(result['checkpoints']) or '(none)'}")
        if problems:
            print(f"\nFAIL ({len(problems)} problem(s)):")
            for p in problems:
                print(f"  - {p}")
        else:
            print("\nOK")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
