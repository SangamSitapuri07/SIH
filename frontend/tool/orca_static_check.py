#!/usr/bin/env python3
"""Static sanity checks for the ORCA Flutter frontend.

These checks exist because this repository is often edited in environments where
no Dart or Flutter SDK is reachable. They are not a substitute for
`flutter analyze` — they only catch the mistakes that are cheap to catch from
source text: unbalanced brackets, references to symbols that are not imported,
references to theme members that do not exist, unused relative imports and
duplicate top-level declarations.

Usage (from the frontend directory):

    python3 tool/orca_static_check.py             # checks lib/ and test/
    python3 tool/orca_static_check.py --root .

Exit code is 1 when a real problem is found, 0 otherwise.
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import sys

# Files that legitimately reference a symbol declared elsewhere without an
# import because the reference sits inside a string or a comment.
SKIP_UNUSED_FOR = {
    # `main.dart` is the entry point; `app.dart` is imported for its side
    # effects by convention in some setups.
    os.path.join("lib", "app.dart"),
}

# Theme member references that come from a class whose members are declared in
# a style the simple parser below cannot see. Kept explicit so a genuine typo
# is never silently ignored.
MEMBER_FALSE_POSITIVES = {
    ("DateFormatter", "parseIso"),
}


def dart_files(root: str) -> list[str]:
    files = glob.glob(os.path.join(root, "lib", "**", "*.dart"), recursive=True)
    files += glob.glob(os.path.join(root, "test", "**", "*.dart"), recursive=True)
    return sorted(files)


def strip_strings_and_comments(line: str) -> str:
    """Return the line with string literals and trailing comments removed."""
    out: list[str] = []
    i = 0
    while i < len(line):
        c = line[i]
        # raw string: r'...' / r"..."
        if c in "rR" and i + 1 < len(line) and line[i + 1] in "\"'":
            quote = line[i + 1]
            i += 2
            while i < len(line) and line[i] != quote:
                i += 1
            i += 1
            out.append("S")
            continue
        if c in "\"'":
            quote = c
            i += 1
            while i < len(line):
                if line[i] == "\\":
                    i += 2
                    continue
                if line[i] == quote:
                    i += 1
                    break
                i += 1
            out.append("S")
            continue
        out.append(c)
        i += 1
    return "".join(out).split("//")[0]


def check_balance(files: list[str]) -> list[str]:
    problems = []
    for path in files:
        depth = {"(": 0, "[": 0, "{": 0}
        for line in open(path, encoding="utf-8"):
            code = strip_strings_and_comments(line.rstrip("\n"))
            depth["("] += code.count("(") - code.count(")")
            depth["["] += code.count("[") - code.count("]")
            depth["{"] += code.count("{") - code.count("}")
        if any(depth.values()):
            problems.append(
                f"UNBALANCED {path} parens={depth['(']} "
                f"brackets={depth['[']} braces={depth['{']}"
            )
    return problems


def collect_declarations(files: list[str]) -> dict[str, set[str]]:
    """Map every top-level class / enum / mixin / typedef / const to its file."""
    decls: dict[str, set[str]] = {}
    patterns = [
        r"^\s*(?:abstract\s+|sealed\s+|base\s+|final\s+)?class\s+(\w+)",
        r"^\s*enum\s+(\w+)",
        r"^\s*mixin\s+(\w+)",
        r"^\s*typedef\s+(\w+)",
        r"^\s*(?:final|const)\s+(\w+(?:Provider|Router|Handler|Notifier))\s*=",
        r"^\s*const\s+String\s+(\w+)\s*=",
    ]
    for path in files:
        src = re.sub(r"^\s*///.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
        for pattern in patterns:
            for name in re.findall(pattern, src, re.M):
                decls.setdefault(name, set()).add(path)
    return decls


def check_missing_imports(files: list[str], decls: dict[str, set[str]]) -> list[str]:
    problems = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        imports = set()
        for target, _ in import_statements(src):
            if target.startswith("package:orca_app/"):
                imports.add(os.path.normpath(
                    os.path.join(ROOT, "lib", target[len("package:orca_app/"):])))
            elif not target.startswith(("package:", "dart:")):
                imports.add(os.path.normpath(os.path.join(os.path.dirname(path), target)))
        body = re.sub(r"^\s*import\s.*$", "", src, flags=re.M)
        body = re.sub(r"^\s*///.*$", "", body, flags=re.M)
        body = re.sub(r"^\s*//.*$", "", body, flags=re.M)
        body = strip_plain_strings(body)
        available = set(declared_in(path))
        for imported in imports:
            if os.path.exists(imported):
                available |= collect_exported_names(imported)
        body = strip_plain_strings(body)
        used = (
            set(re.findall(r"\b([A-Z]\w+)\s*[.(]", body))
            | set(re.findall(r"<([A-Z]\w+)>", body))
            | set(re.findall(r"\b(\w+Provider)\b", body))
        )
        for name in sorted(used):
            owners = decls.get(name)
            if not owners:
                continue  # not ours; an SDK or package symbol
            if name in available:
                continue
            where = ", ".join(sorted(owners))
            problems.append(
                f"MISSING IMPORT {path} uses {name}; declared in {where}, "
                f"none of which is imported"
            )
    return problems


def check_theme_members(files: list[str]) -> list[str]:
    """Verify every `SomeClass.member` reference against the declaring class."""
    problems = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        for class_name, member in re.findall(r"\b(\w+)\.(\w+)\b", src):
            if member.startswith("_"):
                continue
            if (class_name, member) in MEMBER_FALSE_POSITIVES:
                continue
            if class_name not in DECLARED_CLASSES:
                continue
            found = False
            verifiable = False
            for owner in sorted(DECLARED_CLASSES[class_name]):
                body = class_body(open(owner, encoding="utf-8").read(), class_name)
                if body is None:
                    continue  # enum / typedef / provider: verified elsewhere
                verifiable = True
                if re.search(rf"\b{re.escape(member)}\b", body):
                    found = True
                    break
            if verifiable and not found:
                problems.append(
                    f"MISSING MEMBER {path} -> {class_name}.{member} "
                    f"not declared in {', '.join(sorted(DECLARED_CLASSES[class_name]))}"
                )
    return problems


def class_body(src: str, class_name: str) -> str | None:
    match = re.search(rf"^(?:\w+\s+)*class\s+{re.escape(class_name)}\b[^{{]*{{", src, re.M)
    if not match:
        return None
    start = match.end()
    depth = 1
    i = start
    while i < len(src) and depth > 0:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start : i - 1]


def check_duplicates(files: list[str]) -> list[str]:
    problems = []
    for path in files:
        src = re.sub(r"^\s*///.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
        names = re.findall(
            r"^(?:abstract\s+|sealed\s+|base\s+|final\s+)?class\s+(\w+)", src, re.M
        )
        seen: dict[str, int] = {}
        for name in names:
            seen[name] = seen.get(name, 0) + 1
        for name, count in seen.items():
            if count > 1:
                problems.append(f"DUPLICATE CLASS {path} declares {name} {count} times")
    return problems


def check_unused_imports(files: list[str]) -> list[str]:
    problems = []
    for path in files:
        rel = os.path.normpath(path)
        if rel in SKIP_UNUSED_FOR:
            continue
        src = open(path, encoding="utf-8").read()
        body = re.sub(r"^\s*import\s.*$", "", src, flags=re.M)
        body = re.sub(r"^\s*///.*$", "", body, flags=re.M)
        body = re.sub(r"^\s*//.*$", "", body, flags=re.M)
        for target, shown in import_statements(src):
            if target.startswith(("package:", "dart:")):
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not os.path.exists(resolved):
                problems.append(f"BROKEN IMPORT {path} -> {target}")
                continue
            # An explicit `show` clause names exactly what the import provides.
            candidates = shown or collect_exported_names(resolved)
            if candidates and not any(
                re.search(rf"\b{re.escape(name)}\b", body) for name in candidates
            ):
                label = ", ".join(sorted(candidates)[:3])
                problems.append(
                    f"UNUSED IMPORT {path} -> {os.path.basename(target)} "
                    f"({len(candidates)} symbols: {label})"
                )
    return problems


def strip_plain_strings(text: str) -> str:
    """Drop string literals that contain no interpolation.

    A type name inside a plain string (a test description, a label) needs no
    import, so it must not count as a usage. Literals containing `$` are kept
    because they can hold real code, e.g. `'${SomeType.value}'`.
    """
    kept: list[str] = []
    for line in text.split("\n"):
        i = 0
        while i < len(line):
            if line[i] in "\"'":
                quote = line[i]
                j = i + 1
                while j < len(line):
                    if line[j] == "\\":
                        j += 2
                        continue
                    if line[j] == quote:
                        break
                    j += 1
                literal = line[i : j + 1]
                if "$" in literal:
                    kept.append(literal)
                i = j + 1
                continue
            kept.append(line[i])
            i += 1
        kept.append("\n")
    return "".join(kept)


def import_statements(src: str) -> list[tuple[str, set[str]]]:
    """Return (target, shownNames) for every real import.

    Comments are stripped first: the generated localisation file documents an
    import in a `///` line, which a naive scan mistakes for a real one.
    """
    cleaned = re.sub(r"^\s*///.*$", "", src, flags=re.M)
    cleaned = re.sub(r"^\s*//.*$", "", cleaned, flags=re.M)
    found = []
    for line in re.findall(r"^\s*import\s+[^;]+;", cleaned, re.M):
        target = re.search(r"'([^']+)'", line)
        if not target:
            continue
        shown = re.search(r"\bshow\s+([^;]+)", line)
        names = set()
        if shown:
            names = {n.strip() for n in shown.group(1).split(",") if n.strip()}
        found.append((target.group(1), names))
    return found


def declared_in(path: str) -> set[str]:
    """Top-level declaration names owned by a single file."""
    return {name for name, owners in DECLARED_CLASSES.items() if path in owners}


def collect_exported_names(path: str) -> set[str]:
    src = re.sub(r"^\s*///.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
    names = set(
        re.findall(
            r"^(?:abstract\s+|sealed\s+|base\s+|final\s+)?class\s+(\w+)", src, re.M
        )
    )
    names |= set(re.findall(r"^\s*enum\s+(\w+)", src, re.M))
    names |= set(re.findall(r"^\s*mixin\s+(\w+)", src, re.M))
    names |= set(re.findall(r"^\s*typedef\s+(\w+)", src, re.M))
    names |= set(re.findall(r"^\s*const\s+String\s+(\w+)\s*=", src, re.M))
    names |= set(re.findall(r"^\s*(?:final|const)\s+(\w+Provider)\s*=", src, re.M))
    names |= set(re.findall(r"^\s*Future<[^>]*>\s+(\w+)\s*\(", src, re.M))
    names |= set(re.findall(r"^\s*EdgeInsets\s+(\w+)\s*\(", src, re.M))
    return names


DECLARED_CLASSES: dict[str, set[str]] = {}
ROOT = "."


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=".",
        help="directory containing lib/ and test/ (default: the current dir)",
    )
    args = parser.parse_args()

    if not os.path.isdir(os.path.join(args.root, "lib")):
        print(f"error: {args.root}/lib not found — run from the repository root")
        return 2

    global DECLARED_CLASSES, ROOT
    ROOT = args.root
    files = dart_files(args.root)
    DECLARED_CLASSES = collect_declarations(files)

    failing = [
        ("structure", check_balance(files)),
        ("imports (missing/broken)", check_missing_imports(files, DECLARED_CLASSES)
         + [p for p in check_unused_imports(files) if p.startswith("BROKEN")]),
        ("class members", check_theme_members(files)),
        ("duplicate declarations", check_duplicates(files)),
    ]
    advisory = [
        ("unused imports", [p for p in check_unused_imports(files)
                            if p.startswith("UNUSED")]),
    ]

    total = 0
    for name, problems in failing:
        if problems:
            print(f"\n== {name} ==")
            for problem in problems:
                print("  " + problem)
            total += len(problems)

    info = 0
    for name, problems in advisory:
        if problems:
            print(f"\n-- {name} (analyzer infos, safe to ignore) --")
            for problem in problems:
                print("  " + problem)
            info += len(problems)

    print(f"\nchecked {len(files)} Dart files")
    if info:
        print(f"advisory: {info} unused import(s)")
    if total:
        print(f"issues: {total}  — fix these before running flutter analyze")
        return 1
    print("issues: 0  — no structural problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
