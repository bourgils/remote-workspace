#!/usr/bin/env python3
from pathlib import Path
import sys
try:
    import yaml
except ImportError:
    print("PyYAML is required for validation: pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)

root = Path(__file__).resolve().parents[1]
files = [root / "compose.yaml", *sorted((root / "dist").glob("*.yaml")), *sorted((root / "storage").glob("*.yaml")), root / "examples/obsidian/compose.yaml"]
for f in files:
    with f.open() as h:
        yaml.safe_load(h)
    print(f"ok {f.relative_to(root)}")
