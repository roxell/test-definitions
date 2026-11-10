#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Linaro Ltd.
"""Generate markdown documentation from YAML test definitions.

Walks the test directories, reads YAML files with metadata sections,
and generates markdown pages and an index table.
Run this before building the docs.
"""

import argparse
import logging
import os

import yaml

TABLE_DIRS = ["automated/linux", "automated/android", "manual"]
TABLE_FILENAME = "tests_table"
DOCS_DIR = "docs"

log = logging.getLogger(__name__)


def parse_test_definition(filepath):
    """Parse a YAML test definition file.

    Returns a dict with name, description, maintainer and steps. Returns None if the file has no metadata section.
    """
    try:
        with open(filepath, "r") as f:
            content = yaml.safe_load(f)
    except FileNotFoundError:
        return None
    except yaml.YAMLError as e:
        log.warning("%s: invalid YAML: %s", filepath, e)
        return None

    if not isinstance(content, dict) or "metadata" not in content:
        return None

    metadata = content["metadata"]
    if "name" not in metadata:
        log.warning("%s: metadata missing 'name'", filepath)
        return None

    try:
        steps = content["run"]["steps"]
    except (KeyError, TypeError):
        log.warning("%s: missing run.steps", filepath)
        return None

    return {
        "name": metadata["name"],
        "description": metadata.get("description", ""),
        "maintainer": metadata.get("maintainer", []),
        "steps": steps,
    }


def build_frontmatter(name):
    """Build YAML frontmatter for a markdown page."""
    return "\n".join(["---", "title: %s" % name, "---"])


def build_md_list(header, items):
    """Build a markdown section with a header and bullet list."""
    lines = ["\n## %s\n" % header]
    for item in items:
        lines.append(" * %s" % item)
    return "\n".join(lines)


def build_test_page(rel_path, definition):
    """Build the full markdown content for a test page."""
    parts = [build_frontmatter(definition["name"])]
    parts.append("\n# %s\n" % rel_path)

    parts.append("\n## Description\n")
    parts.append(definition["description"])

    if definition["maintainer"]:
        parts.append(build_md_list("Maintainer", definition["maintainer"]))
    else:
        parts.append("\n## Maintainer\n")

    parts.append("\n## Steps to reproduce\n")
    for line in definition["steps"]:
        text = str(line)
        if text.startswith("#"):
            parts.append(" * \\%s" % text)
        else:
            parts.append(" * %s" % text)

    return "\n".join(parts) + "\n"


def write_test_page(filepath, docs_dir, definition):
    """Write a markdown page for a single test definition.

    Returns the relative path (without docs_dir prefix) on success.
    """
    # strip .yaml extension
    rel_path = filepath.rsplit(".", 1)[0]

    out_path = os.path.join(docs_dir, rel_path + ".md")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    content = build_test_page(rel_path, definition)
    with open(out_path, "w") as f:
        f.write(content)

    return rel_path


def collect_table_row(test_tables, table_dirs, definition, rel_path):
    """Add a row to the appropriate index table."""
    for table_name in table_dirs:
        if rel_path.startswith(table_name):
            test_tables[table_name].append(
                {
                    "name": "[%s](%s.md)" % (definition["name"], rel_path),
                    "description": definition["description"],
                }
            )
            break


def generate_index(docs_dir, table_dirs, test_tables, table_filename):
    """Generate the tests index table."""
    path = os.path.join(docs_dir, table_filename + ".md")
    lines = ["# Tests index\n"]
    for table_name in table_dirs:
        test_table = test_tables[table_name]
        lines.append('\n## <span class="tag">%s</span>\n' % table_name)
        lines.append("| Name | Description |")
        lines.append("| --- | --- |")
        for row in sorted(test_table, key=lambda r: r["name"]):
            desc = row["description"].replace("\n", "")
            lines.append("| %s | %s |" % (row["name"], desc))
        lines.append("")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Generate markdown docs from YAML test definitions"
    )
    parser.add_argument(
        "--docs-dir", default=DOCS_DIR, help="Output directory (default: docs)"
    )
    parser.add_argument(
        "--table-dirs",
        nargs="+",
        default=TABLE_DIRS,
        help="Directories to scan for YAML files",
    )
    parser.add_argument(
        "--table-file",
        default=TABLE_FILENAME,
        help="Name of the index table file (without .md)",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Show warnings")
    args = parser.parse_args()

    logging.basicConfig(level=logging.WARNING if args.verbose else logging.ERROR)

    test_tables = {name: [] for name in args.table_dirs}
    generated = 0

    for table_dir in args.table_dirs:
        for root, dirs, filenames in os.walk(table_dir):
            for filename in filenames:
                if not filename.endswith(".yaml"):
                    continue
                filepath = os.path.join(root, filename)
                definition = parse_test_definition(filepath)
                if definition is None:
                    continue
                rel_path = write_test_page(filepath, args.docs_dir, definition)
                collect_table_row(test_tables, args.table_dirs, definition, rel_path)
                generated += 1

    generate_index(args.docs_dir, args.table_dirs, test_tables, args.table_file)
    print("Generated %d test doc(s) + index" % generated)


if __name__ == "__main__":
    main()
