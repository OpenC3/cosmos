#!/usr/bin/env python3
"""Inventory Ruby vs Python scripting-API methods and compare their signatures.

Usage: python3 inventory.py <repo-root> <out-dir> [area ...]
  area: api, script (default: both)

Writes <out-dir>/inventory.json and prints a markdown summary. Stdlib only.
"""

import ast
import json
import re
import sys
from pathlib import Path

RUBY_DEF = re.compile(r"^(\s*)def\s+(self\.)?([A-Za-z_]\w*[?!=]?)\s*(\(|$|\s)")
NORMALIZE = {"nil": "None", "true": "True", "false": "False", "$openc3_scope": "OPENC3_SCOPE",
             "[]": "[]", "{}": "{}"}


def split_params(text):
    out, depth, cur, quote = [], 0, "", None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
            continue
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def norm_default(v):
    if v is None:
        return None
    v = v.strip()
    v = NORMALIZE.get(v, v)
    if re.fullmatch(r":\w+", v):
        v = '"' + v[1:] + '"'
    v = v.replace("'", '"')
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        v = '"' + v[1:-1] + '"'
    return v


def ruby_params(lines, i, line):
    """Return the raw parameter text of a def starting at lines[i]."""
    start = line.find("(", line.find("def"))
    if start == -1 or not re.match(r"^\s*def\s+(self\.)?[\w?!=]+\s*\(", line):
        m = re.match(r"^\s*def\s+(self\.)?[\w?!=]+\s+(.*)$", line)
        return (m.group(2).strip() if m and m.group(2).strip() else "")
    text, depth, j, pos = "", 0, i, start
    while j < len(lines):
        seg = lines[j][pos:]
        for ch in seg:
            if ch == "(":
                depth += 1
                if depth == 1:
                    continue
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return text
            text += ch
        text += " "
        j += 1
        pos = 0
    return text


def parse_ruby_param(p):
    p = p.strip()
    if p.startswith("&"):
        return None
    if p.startswith("**"):
        return {"name": p[2:] or "kwargs", "kind": "varkw", "default": None}
    if p.startswith("*"):
        return {"name": p[1:] or "args", "kind": "var", "default": None}
    m = re.match(r"^(\w+):\s*(.*)$", p)
    if m:
        return {"name": m.group(1), "kind": "kw", "default": norm_default(m.group(2)) if m.group(2) else "REQUIRED"}
    m = re.match(r"^(\w+)\s*=\s*(.*)$", p)
    if m:
        return {"name": m.group(1), "kind": "pos", "default": norm_default(m.group(2))}
    return {"name": p, "kind": "pos", "default": "REQUIRED"}


def ruby_methods(path, repo):
    lines = path.read_text().splitlines()
    out = []
    stack = []  # (indent, class name or None for module, private)
    for i, line in enumerate(lines):
        indent = len(line) - len(line.lstrip())
        cm = re.match(r"^(\s*)(class|module)\s+([\w:]+)", line)
        if cm and not line.rstrip().endswith(" end"):
            name = cm.group(3).split("::")[-1]
            stack.append([indent, name if cm.group(2) == "class" else None, False])
            continue
        if re.match(r"^\s*end\b", line) and stack and stack[-1][0] == indent:
            stack.pop()
            continue
        if re.match(r"^\s*private\s*$", line) and stack:
            stack[-1][2] = True
        m = RUBY_DEF.match(line)
        if not m:
            continue
        name = m.group(3)
        if name.endswith("="):
            continue
        cls = next((c[1] for c in reversed(stack) if c[1]), None)
        private = bool(stack and stack[-1][2])
        if name == "initialize":
            name = "__init__"
        if cls:
            name = f"{CLASS_ALIASES.get(cls, cls)}#{name}"
        raw = ruby_params(lines, i, line)
        params = [x for x in (parse_ruby_param(p) for p in split_params(raw)) if x]
        out.append({"name": name, "file": f"{path.relative_to(repo)}:{i + 1}", "params": params,
                    "private": private or name.startswith("_")})
    return out


def ruby_whitelist(path):
    text = path.read_text()
    names = []
    for block in re.findall(r"WHITELIST\.concat\(\[(.*?)\]\)", text, flags=re.S):
        block = re.sub(r"#.*", "", block)
        names += re.findall(r"['\"]([\w?!]+)['\"]", block)
    return names


def py_methods(path, repo):
    tree = ast.parse(path.read_text())
    out = []
    nodes = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            nodes.append((None, node))
        elif isinstance(node, ast.ClassDef):
            nodes += [(node.name, n) for n in node.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
    for cls, node in nodes:
        a = node.args
        params = []
        pos = a.posonlyargs + a.args
        defaults = [None] * (len(pos) - len(a.defaults)) + list(a.defaults)
        for arg, d in zip(pos, defaults):
            params.append({"name": arg.arg, "kind": "pos",
                           "default": norm_default(ast.unparse(d)) if d is not None else "REQUIRED"})
        if a.vararg:
            params.append({"name": a.vararg.arg, "kind": "var", "default": None})
        for arg, d in zip(a.kwonlyargs, a.kw_defaults):
            params.append({"name": arg.arg, "kind": "kw",
                           "default": norm_default(ast.unparse(d)) if d is not None else "REQUIRED"})
        if a.kwarg:
            params.append({"name": a.kwarg.arg, "kind": "varkw", "default": None})
        params = [x for x in params if x["name"] not in ("self", "cls")]
        if any(isinstance(d, ast.Name) and d.id == "property" for d in node.decorator_list) or any(
                isinstance(d, ast.Attribute) and d.attr == "setter" for d in node.decorator_list):
            continue
        private = node.name.startswith("_") and node.name != "__init__"
        name = f"{cls}#{node.name}" if cls else node.name
        out.append({"name": name, "file": f"{path.relative_to(repo)}:{node.lineno}", "params": params,
                    "private": private})
    return out


def py_whitelist(path):
    tree = ast.parse(path.read_text())
    names = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "extend" and getattr(node.func.value, "id", None) == "WHITELIST"):
            for arg in node.args:
                if isinstance(arg, (ast.List, ast.Tuple)):
                    names += [e.value for e in arg.elts if isinstance(e, ast.Constant)]
    return names


def py_name(ruby_name):
    return ruby_name.rstrip("?!")


# Ruby class name -> Python class name where they differ.
CLASS_ALIASES = {"ServerProxy": "ApiServerProxy", "Puts": "Print"}


# Ruby JSON-RPC API methods take manual:/token: for authorization; Python's api runs in-process.
RUBY_ONLY_PARAMS = {"manual", "token"}


def compare(r, p):
    """Return a list of signature differences between a Ruby and a Python method."""
    diffs = []
    rmap = {x["name"]: x for x in r["params"] if x["kind"] in ("pos", "kw") and x["name"] not in RUBY_ONLY_PARAMS}
    pmap = {x["name"]: x for x in p["params"] if x["kind"] in ("pos", "kw")}
    r_var = any(x["kind"] == "var" for x in r["params"])
    p_var = any(x["kind"] == "var" for x in p["params"])
    r_varkw = any(x["kind"] == "varkw" for x in r["params"])
    p_varkw = any(x["kind"] == "varkw" for x in p["params"])
    for name, rp in rmap.items():
        if name not in pmap:
            if not p_varkw:
                diffs.append(f"Ruby param `{name}` missing in Python")
            continue
        pp = pmap[name]
        if rp["default"] != pp["default"]:
            diffs.append(f"`{name}` default: Ruby `{rp['default']}` vs Python `{pp['default']}`")
        if rp["kind"] == "kw" and pp["kind"] == "pos" and pp["default"] == "REQUIRED":
            diffs.append(f"`{name}` is a keyword in Ruby, a required positional in Python")
    for name in pmap:
        if name not in rmap and not r_varkw and name not in ("self", "cls") and name not in RUBY_ONLY_PARAMS:
            diffs.append(f"Python param `{name}` missing in Ruby")
    if r_var != p_var:
        diffs.append(f"*args: Ruby {r_var} vs Python {p_var}")
    return diffs


# Ruby module -> Python module(s) when the file names differ.
MODULE_ALIASES = {
    "script/calendar": ["script/cosmos_calendar"],
    "script/script": ["script/__init__", "script/server_proxy"],
    "script/api_shared": ["script/api_shared", "api/api_shared"],
}


def module_of(file_ref):
    path = file_ref.rsplit(":", 1)[0]
    parts = Path(path).parts
    return f"{parts[-2]}/{Path(path).stem}"


def pairs(r_defs, p_defs):
    """Pair each Ruby definition with the Python definitions in the matching module."""
    out = []
    for rm in r_defs:
        rmod = module_of(rm["file"])
        targets = MODULE_ALIASES.get(rmod, [rmod])
        matched = [pm for pm in p_defs if module_of(pm["file"]) in targets]
        out += [(rm, pm) for pm in (matched or p_defs)]
    return out


def main():
    repo = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2])
    areas = sys.argv[3:] or ["api", "script"]
    out_dir.mkdir(parents=True, exist_ok=True)
    rb_root, py_root = repo / "openc3/lib/openc3", repo / "openc3/python/openc3"

    r_defs, p_defs, r_wl, p_wl = {}, {}, set(), set()
    for area in areas:
        for f in sorted((rb_root / area).glob("*.rb")):
            for m in ruby_methods(f, repo):
                r_defs.setdefault(py_name(m["name"]), []).append(m)
            r_wl.update(py_name(n) for n in ruby_whitelist(f))
        for f in sorted((py_root / area).glob("*.py")):
            for m in py_methods(f, repo):
                p_defs.setdefault(m["name"], []).append(m)
            p_wl.update(py_whitelist(f))

    rows = []
    for name in sorted(set(r_defs) | set(p_defs)):
        r, p = r_defs.get(name, []), p_defs.get(name, [])
        private = all(m["private"] for m in r + p)
        row = {"name": name, "private": private,
               "ruby": [m["file"] for m in r], "python": [m["file"] for m in p],
               "ruby_whitelist": name in r_wl, "python_whitelist": name in p_wl, "diffs": []}
        if r and p:
            seen = set()
            for rm, pm in pairs(r, p):
                for d in compare(rm, pm):
                    d = f"{d} ({module_of(rm['file'])} · {module_of(pm['file'])})" if len(r) + len(p) > 2 else d
                    if d not in seen:
                        seen.add(d)
                        row["diffs"].append(d)
        rows.append(row)

    (out_dir / "inventory.json").write_text(json.dumps(rows, indent=1))

    public = [x for x in rows if not x["private"]]
    only_r = [x for x in public if x["ruby"] and not x["python"]]
    only_p = [x for x in public if x["python"] and not x["ruby"]]
    wl_gap = sorted((r_wl - p_wl) | (p_wl - r_wl))
    sig = [x for x in public if x["diffs"]]
    print(f"# Parity inventory ({', '.join(areas)})\n")
    print(f"Public names: {len(public)} · Ruby only: {len(only_r)} · Python only: {len(only_p)} · "
          f"signature diffs: {len(sig)} · WHITELIST gaps: {len(wl_gap)}\n")
    print("## WHITELIST gaps\n")
    for n in wl_gap:
        print(f"- `{n}`: Ruby {'yes' if n in r_wl else 'no'}, Python {'yes' if n in p_wl else 'no'}")
    print("\n## Ruby only\n")
    for x in only_r:
        print(f"- `{x['name']}` {', '.join(x['ruby'])}")
    print("\n## Python only\n")
    for x in only_p:
        print(f"- `{x['name']}` {', '.join(x['python'])}")
    print("\n## Signature differences\n")
    for x in sig:
        print(f"- `{x['name']}` ({x['ruby'][0]} · {x['python'][0]})")
        for d in x["diffs"]:
            print(f"  - {d}")


if __name__ == "__main__":
    main()
