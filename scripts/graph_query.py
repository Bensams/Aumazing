#!/usr/bin/env python3
"""
graph_query.py — cheap, token-efficient codebase lookups over the Graphify graph.

Answers "what depends on X", "where is Y defined", "what would break if I change Z"
WITHOUT loading source files into an LLM context window. Queries cost ~200 tokens
of output instead of ~80k tokens of file reads.

USAGE
  python scripts/graph_query.py find <term>            # locate symbols/files by name
  python scripts/graph_query.py deps <term>            # files connected to a symbol
  python scripts/graph_query.py impact <path>          # what breaks if this file changes
  python scripts/graph_query.py imports <path>         # what this file imports
  python scripts/graph_query.py rdeps <path>           # reverse deps (who imports this)
  python scripts/graph_query.py defines <path>         # symbols defined in a file
  python scripts/graph_query.py community <name>       # files in a community cluster
  python scripts/graph_query.py communities            # list all community hubs
  python scripts/graph_query.py orphans                # files nothing references
  python scripts/graph_query.py stats                  # graph health + staleness

NOTES
  * The graph is built by `graphify` from a git commit; run `stats` to check staleness.
  * graph.json has been corrupted before by NUL-byte injection (crashed mid-write).
    This script validates and auto-falls-back to the newest clean dated snapshot.
  * `orphans` excludes tests and main.dart entrypoints. A file may still be
    reached via a barrel `export` or used only by tests — treat hits as
    candidates to review, not confirmed dead code.
  * Import specs are resolved relative to the importing file, so the two
    duplicate LocalDbService files are correctly told apart.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GRAPH_DIR = os.path.join(REPO, "graphify-out")

# Edges that mean "A structurally depends on B".
DEP_RELATIONS = {"imports", "references", "calls", "inherits", "mixes_in", "exports"}


# --------------------------------------------------------------------------- load

def _snapshot_dirs() -> list[str]:
    """Dated snapshot dirs, newest first."""
    if not os.path.isdir(GRAPH_DIR):
        return []
    dated = [
        os.path.join(GRAPH_DIR, d)
        for d in os.listdir(GRAPH_DIR)
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d)
        and os.path.exists(os.path.join(GRAPH_DIR, d, "graph.json"))
    ]
    return sorted(dated, reverse=True)


def _try_load(path: str):
    """Load graph.json, rejecting NUL-corrupted files."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        return None, "unreadable"
    if b"\x00" in raw:
        return None, f"CORRUPT ({raw.count(chr(0).encode()):,} NUL bytes)"
    try:
        return json.loads(raw.decode("utf-8", "replace")), None
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON ({exc})"


def load_graph(verbose: bool = True):
    """Load the graph, falling back to the newest clean snapshot if the root is bad."""
    candidates = [os.path.join(GRAPH_DIR, "graph.json")]
    candidates += [os.path.join(d, "graph.json") for d in _snapshot_dirs()]

    for path in candidates:
        if not os.path.exists(path):
            continue
        graph, err = _try_load(path)
        if graph is not None:
            if verbose and path != candidates[0]:
                rel = os.path.relpath(path, REPO)
                print(f"# note: using fallback snapshot {rel}", file=sys.stderr)
            return graph, path
        if verbose:
            rel = os.path.relpath(path, REPO)
            print(f"# skipping {rel}: {err}", file=sys.stderr)

    sys.exit("ERROR: no usable graph.json found. Run `graphify .` to build one.")


class Graph:
    def __init__(self):
        raw, self.path = load_graph()
        self.nodes: list[dict] = raw["nodes"]
        self.edges: list[dict] = raw.get("links") or raw.get("edges") or []
        self.meta: dict = raw.get("graph", {})
        self.by_id = {n["id"]: n for n in self.nodes}

        self.out = defaultdict(list)   # source -> [(target, relation)]
        self.inc = defaultdict(list)   # target -> [(source, relation)]
        for e in self.edges:
            s, t, r = e.get("source"), e.get("target"), e.get("relation")
            self.out[s].append((t, r))
            self.inc[t].append((s, r))

    # -- helpers ----------------------------------------------------------
    def file_of(self, node_id: str) -> str | None:
        return (self.by_id.get(node_id) or {}).get("source_file")

    def nodes_for_file(self, path_frag: str) -> list[dict]:
        frag = path_frag.replace("\\", "/").lower()
        return [
            n for n in self.nodes
            if n.get("source_file") and frag in n["source_file"].lower()
        ]

    def search(self, term: str) -> list[dict]:
        t = term.lower()
        return [
            n for n in self.nodes
            if t in n.get("label", "").lower() or t in n["id"].lower()
        ]

    def neighbour_files(self, node_ids: set[str], direction: str = "both",
                        relations: set[str] | None = None) -> set[str]:
        """Files reachable from a set of nodes in one hop."""
        files: set[str] = set()
        pairs: list[tuple[str, str]] = []
        for nid in node_ids:
            if direction in ("out", "both"):
                pairs += self.out.get(nid, [])
            if direction in ("in", "both"):
                pairs += self.inc.get(nid, [])
        for other, rel in pairs:
            if relations and rel not in relations:
                continue
            f = self.file_of(other)
            if f:
                files.add(f)
        return files

    # -- import resolution -------------------------------------------------
    # Graphify records import TARGETS as raw, unresolved path strings
    # ("../services/local_db_service.dart") with no source_file. To answer
    # "who imports this file" we must resolve them against the importer's
    # directory, exactly like the Dart resolver does. This is what correctly
    # distinguishes the two duplicate LocalDbService files.

    def _build_import_index(self) -> None:
        if hasattr(self, "_imports_by_file"):
            return
        self._imports_by_file: dict[str, set[str]] = defaultdict(set)
        self._importers_of: dict[str, set[str]] = defaultdict(set)

        known = {n["source_file"] for n in self.nodes if n.get("source_file")}

        for e in self.edges:
            if e.get("relation") != "imports":
                continue
            src = self.file_of(e.get("source"))
            tgt_node = self.by_id.get(e.get("target"), {})
            spec = tgt_node.get("source_file") or tgt_node.get("label")
            if not src or not spec:
                continue
            resolved = self._resolve(src, spec, known)
            self._imports_by_file[src].add(resolved)
            if resolved in known:
                self._importers_of[resolved].add(src)

    @staticmethod
    def _resolve(importer: str, spec: str, known: set[str]) -> str:
        """Resolve a Dart import spec relative to the importing file."""
        spec = spec.strip().replace("\\", "/")
        if spec.startswith(("package:", "dart:")):
            return spec  # external / SDK — leave as-is
        cand = os.path.normpath(
            os.path.join(os.path.dirname(importer), spec)
        ).replace("\\", "/")
        if cand in known:
            return cand
        # 'package:aumazing/x.dart' style already handled; try lib-root fallback
        m = re.match(r"(.*/lib)/", importer)
        if m:
            alt = os.path.normpath(f"{m.group(1)}/{spec}").replace("\\", "/")
            if alt in known:
                return alt
        return cand

    def imports_of(self, path: str) -> set[str]:
        self._build_import_index()
        out: set[str] = set()
        for f, specs in self._imports_by_file.items():
            if path.lower() in f.lower():
                out |= specs
        return out

    def importers_of(self, path: str) -> set[str]:
        self._build_import_index()
        out: set[str] = set()
        for f, importers in self._importers_of.items():
            if path.lower() in f.lower():
                out |= importers
        return out


# --------------------------------------------------------------------- output

def show(title: str, items, limit: int = 40) -> None:
    items = sorted(items)
    print(f"\n{title}  ({len(items)})")
    if not items:
        print("  (none)")
        return
    for i in items[:limit]:
        print(f"  {i}")
    if len(items) > limit:
        print(f"  ... +{len(items) - limit} more")


# ------------------------------------------------------------------ commands

def cmd_find(g: Graph, term: str) -> None:
    hits = g.search(term)
    print(f"\nSymbols matching {term!r}  ({len(hits)})")
    seen: set[tuple[str, str]] = set()
    for n in hits[:50]:
        key = (n.get("label", ""), n.get("source_file") or "")
        if key in seen:
            continue
        seen.add(key)
        print(f"  {n.get('label'):<42} {n.get('source_file') or '-'}")
    if len(hits) > 50:
        print(f"  ... +{len(hits) - 50} more")


def cmd_deps(g: Graph, term: str) -> None:
    ids = {n["id"] for n in g.search(term)}
    if not ids:
        return print(f"No nodes match {term!r}")
    show(f"Files connected to {term!r}", g.neighbour_files(ids))


def cmd_impact(g: Graph, path: str) -> None:
    ids = {n["id"] for n in g.nodes_for_file(path)}
    if not ids:
        return print(f"No graph nodes for {path!r}")
    hit = g.importers_of(path) | g.neighbour_files(ids, "in", DEP_RELATIONS)
    hit = {f for f in hit if path.lower() not in f.lower()}
    show(f"Changing {path} may affect", hit)


def cmd_imports(g: Graph, path: str) -> None:
    local = {f for f in g.imports_of(path) if not f.startswith(("package:", "dart:"))}
    ext = {f for f in g.imports_of(path) if f.startswith(("package:", "dart:"))}
    show(f"{path} imports (project)", local)
    show(f"{path} imports (external)", ext, limit=15)


def cmd_rdeps(g: Graph, path: str) -> None:
    show(f"Files importing {path}", g.importers_of(path))


def cmd_defines(g: Graph, path: str) -> None:
    ids = {n["id"] for n in g.nodes_for_file(path)}
    syms = {
        g.by_id[t].get("label")
        for nid in ids
        for t, r in g.out.get(nid, [])
        if r in ("defines", "contains") and t in g.by_id
    }
    show(f"Symbols defined in {path}", {s for s in syms if s})


def cmd_communities(g: Graph) -> None:
    counts = Counter(n.get("community") for n in g.nodes if n.get("community") is not None)
    print(f"\nCommunities ({len(counts)}) — largest first")
    for cid, size in counts.most_common(40):
        members = [n for n in g.nodes if n.get("community") == cid]
        label = next((m.get("label") for m in members if m.get("file_type") == "code"), "?")
        print(f"  [{cid:>3}] {size:>4} nodes   e.g. {label}")


def cmd_community(g: Graph, name: str) -> None:
    hits = g.search(name)
    if not hits:
        return print(f"No node matches {name!r}")
    cid = hits[0].get("community")
    files = {
        n.get("source_file") for n in g.nodes
        if n.get("community") == cid and n.get("source_file")
    }
    show(f"Files in community {cid} (via {hits[0].get('label')})", files)


def cmd_orphans(g: Graph) -> None:
    g._build_import_index()
    # A file is "referenced" if anything imports it (resolved) OR any graph
    # edge points into one of its nodes via a dependency relation.
    referenced = set(g._importers_of.keys())
    for e in g.edges:
        if e.get("relation") in DEP_RELATIONS:
            f = g.file_of(e.get("target"))
            if f:
                referenced.add(f)
    all_files = {n.get("source_file") for n in g.nodes if n.get("source_file")}
    orphans = {
        f for f in all_files - referenced
        if f.endswith(".dart")
        and "/test" not in f
        and not f.endswith("main.dart")     # entrypoints are never imported
    }
    show("Files nothing references (possible dead code)", orphans)


def cmd_stats(g: Graph) -> None:
    print(f"\nGraph      : {os.path.relpath(g.path, REPO)}")
    print(f"Nodes/Edges: {len(g.nodes):,} / {len(g.edges):,}")
    counts = Counter(e.get("relation") for e in g.edges)
    print("Relations  : " + ", ".join(f"{k}={v}" for k, v in counts.most_common(8)))
    files = {n.get("source_file") for n in g.nodes if n.get("source_file")}
    print(f"Files      : {len(files):,}")

    report = os.path.join(GRAPH_DIR, "GRAPH_REPORT.md")
    built = None
    if os.path.exists(report):
        with open(report, encoding="utf-8", errors="replace") as fh:
            m = re.search(r"Built from commit: `([0-9a-f]+)`", fh.read())
            built = m.group(1) if m else None
    try:
        head = subprocess.run(
            ["git", "-C", REPO, "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=15,
        ).stdout.strip()[:8]
    except Exception:
        head = None

    print(f"Built from : {built or '?'}")
    print(f"HEAD       : {head or '?'}")
    if built and head:
        print("Freshness  : " + ("CURRENT" if head.startswith(built[:7])
                                 else "STALE -> run `graphify update .`"))


COMMANDS = {
    "find": cmd_find, "deps": cmd_deps, "impact": cmd_impact,
    "imports": cmd_imports, "rdeps": cmd_rdeps, "defines": cmd_defines,
    "communities": cmd_communities, "community": cmd_community,
    "orphans": cmd_orphans, "stats": cmd_stats,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        return print(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    fn = COMMANDS.get(cmd)
    if not fn:
        return print(f"Unknown command {cmd!r}. Try --help.")
    g = Graph()
    if fn.__code__.co_argcount > 1 and not args:
        return print(f"'{cmd}' needs an argument. Try --help.")
    fn(g, *args[:1]) if fn.__code__.co_argcount > 1 else fn(g)


if __name__ == "__main__":
    main()
