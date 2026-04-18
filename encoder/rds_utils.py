import os
import json

def recreate_rds_json():
    """Delete and recreate RDS JSON files for both programs with default/empty values."""
    base_paths = [
        "/home/ompx/rds/prog1/rds-info.json",
        "/home/ompx/rds/prog2/rds-info.json"
    ]
    default_rds = {
        "ps": "",
        "pi": "",
        "pty": 0,
        "tp": False,
        "ta": False,
        "ms": False,
        "ct": "",
        "rt": ""
    }
    for path in base_paths:
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.path.exists(path):
                os.remove(path)
            with open(path, "w") as f:
                json.dump(default_rds, f)
        except Exception as e:
            print(f"[RDS] Failed to recreate {path}: {e}")
