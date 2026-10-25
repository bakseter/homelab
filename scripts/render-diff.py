#!/usr/bin/env python3
"""Rendered-manifest diff for the Argo CD apps changed by a branch/PR.

For every Argo CD Application whose rendered output can be affected by the
changes between the merge-base of --base-ref and the current working tree,
render the manifests the same way Argo CD does and emit a unified diff:

  * source dir with Chart.yaml        -> helm dependency update + helm template
                                         (release name = app name, namespace =
                                         spec.destination.namespace, i.e. the
                                         same defaults Argo CD uses when the
                                         Application has no `helm:` block)
  * source dir with kustomization.yaml -> kustomize build --enable-helm
  * anything else                      -> plain directory render (top-level
                                         YAML/JSON files, like Argo CD's
                                         non-recursive directory source)

No cluster and no Argo CD installation is needed: both sides are rendered
with the same local tools, so the diff shows exactly the effect of the
change. Apps are discovered by scanning manifests/ for Application CRs
(ApplicationSet git directory generators are expanded as well), and only the
apps whose source path contains changed files are rendered.

Usage (CI):
  scripts/render-diff.py --base-ref origin/master \
      --out full.md --comment-out comment.md

Usage (local):
  scripts/render-diff.py                    # working tree vs origin/master
  scripts/render-diff.py --base-ref HEAD~1  # working tree vs HEAD~1
"""

from __future__ import annotations

import argparse
import difflib
import io
import os
import posixpath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass, field

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("error: PyYAML is required (pip install pyyaml)")

SCAN_ROOT = "manifests"
CMD_TIMEOUT = 300  # seconds per helm/kustomize invocation
DEFAULT_IGNORES = [r"checksum/.+"]  # same noise filter the old workflow used


@dataclass
class App:
    """An Argo CD Application (or one expanded from an ApplicationSet)."""

    name: str
    path: str  # source path, relative to the repo root
    namespace: str
    release: str
    kind: str  # helm | kustomize | plain
    def_file: str  # file (relative) that defines this app
    synthetic: bool = False  # expanded from an ApplicationSet template


@dataclass
class Render:
    status: str  # ok | missing | error
    text: str = ""
    error: str = ""


@dataclass
class AppResult:
    app: App
    base: Render
    head: Render
    diff: list = field(default_factory=list)
    adds: int = 0
    dels: int = 0


# --- small helpers -----------------------------------------------------------


def run(cmd, cwd=None, timeout=CMD_TIMEOUT):
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return 127, "", f"command not found: {cmd[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {timeout}s: {' '.join(cmd)}"


def git(root, args):
    rc, out, err = run(["git", "-C", root] + args)
    if rc != 0:
        raise RuntimeError(f"git {' '.join(args)} failed:\n{err.strip()}")
    return out.strip()


def tail(text, lines=15):
    stripped = [l for l in text.strip().splitlines() if l.strip()]
    return "\n".join(stripped[-lines:]) if stripped else "(no output)"


def normalize_repo_url(url):
    u = url.strip().lower()
    u = re.sub(r"^(https?|ssh)://", "", u)
    u = re.sub(r"^git@", "", u)
    u = u.replace(":", "/")
    u = re.sub(r"\.git$", "", u)
    return u.lstrip("/")


def classify_dir(path):
    if os.path.isfile(os.path.join(path, "Chart.yaml")):
        return "helm"
    if os.path.isfile(os.path.join(path, "kustomization.yaml")) or \
            os.path.isfile(os.path.join(path, "kustomization.yml")):
        return "kustomize"
    return "plain"


# --- app discovery -----------------------------------------------------------


def iter_yaml_files(tree):
    root = os.path.join(tree, SCAN_ROOT)
    if not os.path.isdir(root):
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", "charts")]
        for fn in sorted(filenames):
            if fn.endswith((".yaml", ".yml")):
                yield os.path.join(dirpath, fn)


def glob_to_regex(pattern):
    """Match ApplicationSet git directory globs ('manifests/*', 'a/**')."""
    out = []
    for part in pattern.split("**"):
        out.append(re.escape(part).replace(r"\*", "[^/]*"))
    return re.compile("^" + ".*".join(out) + "$")


def list_dirs(tree):
    root = os.path.join(tree, SCAN_ROOT)
    dirs = []
    if not os.path.isdir(root):
        return dirs
    for dirpath, dirnames, _ in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for d in dirnames:
            dirs.append(os.path.relpath(os.path.join(dirpath, d), tree))
    return sorted(dirs)


def expand_applicationset(doc, tree, def_file):
    """Expand git directory generators into synthetic plain apps."""
    spec = doc.get("spec") or {}
    tmpl = spec.get("template") or {}
    tmeta = tmpl.get("metadata") or {}
    tspec = tmpl.get("spec") or {}
    tsource = tspec.get("source") or {}
    tname = tmeta.get("name") or ""
    tpath = tsource.get("path") or ""
    tns = (tspec.get("destination") or {}).get("namespace") or "default"

    def substitute(template, matched):
        return template.replace("{{.path.basename}}", posixpath.basename(matched)) \
                       .replace("{{.path.path}}", matched)

    dirs = list_dirs(tree)
    apps = []
    for gen in spec.get("generators") or []:
        if not isinstance(gen, dict):
            continue
        for directory in (gen.get("git") or {}).get("directories") or []:
            pattern = directory.get("path") or ""
            if not pattern:
                continue
            regex = glob_to_regex(pattern)
            for matched in dirs:
                if not regex.match(matched):
                    continue
                name, path = substitute(tname, matched), substitute(tpath, matched)
                if not name or not path or "{{" in name or "{{" in path:
                    continue
                if path.startswith(("/", "..")):
                    continue
                namespace = tns if "{{" not in tns else "default"
                apps.append(App(
                    name=name, path=path.rstrip("/"), namespace=namespace,
                    release=name, kind=classify_dir(os.path.join(tree, path)),
                    def_file=def_file, synthetic=True,
                ))
    return apps


def scan_apps(tree, own_repo):
    """Return {app name: App} for all Applications found in <tree>/manifests."""
    found = {}
    for path in iter_yaml_files(tree):
        rel = os.path.relpath(path, tree)
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                docs = list(yaml.safe_load_all(fh))
        except (yaml.YAMLError, OSError):
            continue  # most likely a helm template file, not plain YAML
        for doc in docs or []:
            if not isinstance(doc, dict):
                continue
            kind = doc.get("kind")
            if kind == "ApplicationSet":
                for app in expand_applicationset(doc, tree, rel):
                    found.setdefault(app.name, app)
                continue
            if kind != "Application":
                continue
            meta = doc.get("metadata") or {}
            spec = doc.get("spec") or {}
            source = spec.get("source") or {}
            name = meta.get("name")
            src_path = (source.get("path") or "").rstrip("/")
            if not name or not src_path or src_path.startswith(("/", "..")):
                continue
            repo_url = source.get("repoURL") or ""
            if repo_url and normalize_repo_url(repo_url) != own_repo:
                continue  # app sources its manifests from another repository
            helm = source.get("helm") or {}
            app = App(
                name=name, path=src_path,
                namespace=(spec.get("destination") or {}).get("namespace") or "default",
                release=helm.get("releaseName") or name,
                kind=classify_dir(os.path.join(tree, src_path)),
                def_file=rel,
            )
            found[name] = app  # real apps win over synthetic ones
    return found


# --- changed files & affected apps -------------------------------------------


def changed_files(root, merge_base):
    files = set(git(root, ["diff", "--name-only", merge_base]).splitlines())
    files |= set(git(root, ["ls-files", "--others", "--exclude-standard"]).splitlines())
    return {f for f in files if f}


def is_affected(sides, changed):
    """True if any changed file can influence this app's rendered output."""
    for app in sides.values():
        if app is None:
            continue
        if app.def_file in changed:
            return True
        if not app.path:
            continue
        if app.kind == "plain":
            # Argo CD directory sources are non-recursive by default
            if any(posixpath.dirname(f) == app.path for f in changed):
                return True
        elif any(f.startswith(app.path + "/") for f in changed):
            return True
    return False


# --- rendering ---------------------------------------------------------------


def render_app(app, tree, tmp_root, kube_version):
    src = os.path.join(tree, app.path)
    if not os.path.isdir(src):
        return Render("missing", error=f"source directory '{app.path}' does not exist on this side")

    # Render from a copy: helm/kustomize write charts/ and lock files into the
    # chart directory, and we must not mutate the working tree.
    work = tempfile.mkdtemp(prefix=f"{app.name}-", dir=tmp_root)
    dst = os.path.join(work, "app")
    shutil.copytree(src, dst, symlinks=True)

    if app.kind == "helm":
        rc, _, err = run(["helm", "dependency", "update", "."], cwd=dst)
        if rc != 0:
            return Render("error", error=f"helm dependency update failed:\n{tail(err)}")
        cmd = ["helm", "template", app.release, ".", "--namespace", app.namespace,
               "--kube-version", kube_version, "--include-crds"]
        rc, out, err = run(cmd, cwd=dst)
    elif app.kind == "kustomize":
        if shutil.which("kustomize"):
            cmd = ["kustomize", "build", "--enable-helm", dst]
        else:
            cmd = ["kubectl", "kustomize", "--enable-helm", dst]
        rc, out, err = run(cmd)
        if rc != 0 and "unknown flag" in (err + out):
            # older kubectl builds do not know --enable-helm
            rc, out, err = run(cmd[:-2] + cmd[-1:])
    else:  # plain directory, mirrors Argo CD's non-recursive directory source
        parts = []
        for fn in sorted(os.listdir(src)):
            if not fn.endswith((".yaml", ".yml", ".json")):
                continue
            full = os.path.join(src, fn)
            if not os.path.isfile(full):
                continue
            with open(full, encoding="utf-8", errors="replace") as fh:
                parts.append(f"# Source: {fn}\n" + fh.read().rstrip("\n"))
        return Render("ok", text="\n".join(parts))

    if rc != 0:
        return Render("error", error=f"{' '.join(cmd[:2])} failed:\n{tail(err)}")
    return Render("ok", text=out)


def to_lines(text, ignore_patterns):
    lines = text.replace("\r\n", "\n").splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    if ignore_patterns:
        lines = [l for l in lines if not any(p.search(l) for p in ignore_patterns)]
    return lines


def diff_app(name, base_render, head_render, ignore_patterns):
    base_lines = to_lines(base_render.text, ignore_patterns) if base_render.status == "ok" else []
    head_lines = to_lines(head_render.text, ignore_patterns) if head_render.status == "ok" else []
    diff = list(difflib.unified_diff(
        base_lines, head_lines,
        fromfile=f"{name} (base)", tofile=f"{name} (HEAD)", lineterm="",
    ))
    adds = sum(1 for l in diff if l.startswith("+") and not l.startswith("+++"))
    dels = sum(1 for l in diff if l.startswith("-") and not l.startswith("---"))
    return diff, adds, dels


# --- markdown output ---------------------------------------------------------


def fenced(block, language="diff"):
    return f"````{language}\n{block}\n````"


def render_section(result, max_lines):
    app = result.app
    if result.base.status == "error" or result.head.status == "error":
        failed = result.base if result.base.status == "error" else result.head
        return [f"### `{app.name}` — render failed", "",
                fenced(failed.error, language="text"), ""]
    if result.base.status == "missing" or result.head.status == "missing":
        missing = result.base if result.base.status == "missing" else result.head
        return [f"### `{app.name}` — app {'added' if result.base.status == 'missing' else 'removed'}", "",
                fenced(missing.error, language="text"), ""]

    if not result.diff:
        return None  # unchanged; collected separately

    lines = [f"### `{app.name}` — +{result.adds} −{result.dels}", ""]
    body = result.diff[2:]  # drop the +++/--- header lines
    if len(body) > max_lines:
        lines.append(f"_{len(body) - max_lines} more lines truncated — full diff in the job summary_")
        body = body[:max_lines]
    lines += [fenced("\n".join(body)), ""]
    return lines


def build_markdown(results, base_label, head_label, changed, max_lines, max_chars):
    out = ["## Rendered manifest diff", ""]
    if not results:
        out += ["No Argo CD Applications are affected by this change.", ""]
    else:
        names = ", ".join(f"`{r.app.name}`" for r in results)
        out += [f"Rendered-manifest preview of the affected app(s): {names}.",
                f"Both sides rendered locally with `helm template` / `kustomize build` "
                f"(same defaults Argo CD uses) and diffed: `{base_label}` → `{head_label}`.", ""]

    changed_section, unchanged, truncated_total = [], [], 0
    for r in results:
        section = render_section(r, max_lines)
        if section is None:
            unchanged.append(r.app.name)
        else:
            changed_section += section

    out += changed_section

    if unchanged:
        out += ["<details>", f"<summary>No rendered changes: {', '.join(f'`{u}`' for u in unchanged)}</summary>", "",
                "These apps were touched by the change but render identically on both sides.", "</details>", ""]

    if not results and changed:
        listed = sorted(changed)[:20]
        out += ["<details>", f"<summary>Changed files ({len(changed)})</summary>", ""]
        out += [f"- `{f}`" for f in listed]
        if len(changed) > len(listed):
            out.append(f"- … and {len(changed) - len(listed)} more")
        out += ["</details>", ""]

    out.append(f"<sub>Generated by scripts/render-diff.py · base {base_label} → head {head_label}</sub>")

    doc = "\n".join(out)
    if max_chars and len(doc) > max_chars:
        doc = doc[:max_chars].rsplit("\n", 1)[0] + "\n\n… truncated (full diff in the job summary)\n"
    return doc


# --- main --------------------------------------------------------------------


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-ref", default=None,
                        help="git ref to diff against (default: auto-detect origin/master or origin/main)")
    parser.add_argument("--out", default=None, help="write the full markdown report to this file")
    parser.add_argument("--comment-out", default=None,
                        help="write a size-capped markdown report suitable for a PR comment")
    parser.add_argument("--kube-version", default="1.35.0",
                        help="kubeVersion passed to helm template (default: 1.35.0, matches the cluster)")
    parser.add_argument("--ignore", action="append", default=[],
                        help="extra regex; matching lines are dropped from both sides before diffing")
    parser.add_argument("--max-lines", type=int, default=300,
                        help="per-app diff truncation in the comment output (default: 300)")
    parser.add_argument("--max-chars", type=int, default=55000,
                        help="hard character cap for the comment output (default: 55000)")
    parser.add_argument("--only", action="append", default=[],
                        help="only diff these app names (repeatable, for debugging)")
    parser.add_argument("--debug", action="store_true", help="log app discovery and changed files to stderr")
    return parser.parse_args(argv)


def resolve_base_ref(root, requested):
    candidates = [requested] if requested else ["origin/master", "origin/main", "master", "main"]
    for ref in candidates:
        rc, out, _ = run(["git", "-C", root, "rev-parse", "--verify", "--quiet", ref])
        if rc == 0:
            return ref, out.strip()
    raise RuntimeError(f"could not resolve a base ref (tried: {', '.join(candidates)})")


def export_tree(root, sha, dest):
    # capture as bytes: git archive output is a binary tarball
    proc = subprocess.run(["git", "-C", root, "archive", sha],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=CMD_TIMEOUT)
    if proc.returncode != 0:
        raise RuntimeError(f"git archive {sha} failed:\n{proc.stderr.decode(errors='replace')}")
    with tarfile.open(fileobj=io.BytesIO(proc.stdout)) as tf:
        try:
            tf.extractall(dest, filter="data")
        except TypeError:  # python < 3.12
            tf.extractall(dest)


def main(argv):
    args = parse_args(argv)
    root = git(".", ["rev-parse", "--show-toplevel"])
    base_ref, base_sha = resolve_base_ref(root, args.base_ref)
    merge_base = git(root, ["merge-base", base_sha, "HEAD"])
    head_sha = git(root, ["rev-parse", "HEAD"])
    own_repo = normalize_repo_url(git(root, ["remote", "get-url", "origin"]))

    changed = changed_files(root, merge_base)

    with tempfile.TemporaryDirectory(prefix="render-diff-") as tmp:
        base_tree = os.path.join(tmp, "base")
        os.makedirs(base_tree)
        export_tree(root, merge_base, base_tree)

        apps = {}
        for side, tree in (("head", root), ("base", base_tree)):
            for name, app in scan_apps(tree, own_repo).items():
                apps.setdefault(name, {"head": None, "base": None})[side] = app

        if args.debug:
            print(f"base ref: {base_ref} ({merge_base[:9]}), head: {head_sha[:9]}", file=sys.stderr)
            print(f"changed files ({len(changed)}):", file=sys.stderr)
            for f in sorted(changed):
                print(f"  {f}", file=sys.stderr)
            print(f"discovered apps ({len(apps)}):", file=sys.stderr)
            for name, sides in sorted(apps.items()):
                a = sides["head"] or sides["base"]
                print(f"  {name:30} {a.kind:10} {a.path}", file=sys.stderr)

        affected = {name: sides for name, sides in apps.items()
                    if is_affected(sides, changed) and (not args.only or name in args.only)}

        if args.debug:
            print(f"affected apps ({len(affected)}): {', '.join(sorted(affected)) or 'none'}", file=sys.stderr)

        ignore_patterns = [re.compile(p) for p in (DEFAULT_IGNORES + args.ignore)]

        needed = {(sides["head"] or sides["base"]).kind for sides in affected.values()}
        if "helm" in needed and not shutil.which("helm"):
            sys.exit("error: helm is required but not installed")
        if "kustomize" in needed and not (shutil.which("kustomize") or shutil.which("kubectl")):
            sys.exit("error: kustomize (or kubectl) is required but not installed")

        results = []
        for name in sorted(affected):
            sides = affected[name]
            app = sides["head"] or sides["base"]
            renders = {}
            for side, tree in (("base", base_tree), ("head", root)):
                render_with = sides[side] or app  # use this side's own definition if it exists
                renders[side] = render_app(render_with, tree, tmp, args.kube_version)
            diff, adds, dels = diff_app(name, renders["base"], renders["head"], ignore_patterns)
            results.append(AppResult(app=app, base=renders["base"], head=renders["head"],
                                     diff=diff, adds=adds, dels=dels))

        base_label = merge_base[:9]
        head_label = head_sha[:9]
        full_md = build_markdown(results, base_label, head_label, changed,
                                 max_lines=10**9, max_chars=None)
        comment_md = build_markdown(results, base_label, head_label, changed,
                                    max_lines=args.max_lines, max_chars=args.max_chars)

        if args.out:
            with open(args.out, "w", encoding="utf-8") as fh:
                fh.write(full_md)
        if args.comment_out:
            with open(args.comment_out, "w", encoding="utf-8") as fh:
                fh.write(comment_md)

    for r in results:
        icon = {"ok": "•", "missing": "＋", "error": "✗"}[r.base.status if r.base.status != "ok" else r.head.status]
        if r.base.status == "error" or r.head.status == "error":
            icon = "✗"
        summary = f"+{r.adds} −{r.dels}" if r.diff else "no rendered changes"
        print(f"{icon} {r.app.name:30} {summary}")
    for r in results:
        if r.base.status == "error":
            print(f"\nerror rendering {r.app.name} (base):\n{r.base.error}", file=sys.stderr)
        if r.head.status == "error":
            print(f"\nerror rendering {r.app.name} (head):\n{r.head.error}", file=sys.stderr)
    if not results:
        print("• no Argo CD apps affected by this change")
    if args.out:
        print(f"\nfull report:    {args.out}")
    if args.comment_out:
        print(f"comment report: {args.comment_out}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(2)
