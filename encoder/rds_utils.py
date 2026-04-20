# rds_utils.py
# Utility functions for managing RDS (Radio Data System) JSON files for oMPX.
# These files store metadata such as Program Service (PS), Program Identification (PI),
import os
import json

# Program Type (PTY), Traffic Program (TP), Traffic Announcement (TA), Music/Speech (MS),
# Clock Time (CT), and RadioText (RT) for each program.

def recreate_rds_json():
        """
        Delete and recreate RDS JSON files for both programs with default/empty values.
        This function is intended to reset the RDS metadata for both program slots (prog1 and prog2)
        by overwriting their rds-info.json files with a default structure.
        """

    """Delete and recreate RDS JSON files for both programs with default/empty values."""
    base_paths = [
        "/home/ompx/rds/prog1/rds-info.json",
        "/home/ompx/rds/prog2/rds-info.json"
    base_paths = [
        "/home/ompx/rds/prog1/rds-info.json",  # Path for program 1 RDS info
        "/home/ompx/rds/prog2/rds-info.json"   # Path for program 2 RDS info
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
    # Default RDS structure: all fields empty or zeroed
    default_rds = {
        "ps": "",   # Program Service name (station name)
        "pi": "",   # Program Identification code
        "pty": 0,    # Program Type (numeric code)
        "tp": False, # Traffic Program flag
        "ta": False, # Traffic Announcement flag
        "ms": False, # Music/Speech flag
        "ct": "",   # Clock Time (string)
        "rt": ""    # RadioText (freeform text)
    }
    for path in base_paths:
        try:
    for path in base_paths:
        try:
            # Ensure the directory exists
            os.makedirs(os.path.dirname(path), exist_ok=True)
                        # Remove the file if it already exists
                        if os.path.exists(path):
                            os.remove(path)
                        # Write the default RDS structure to the file as JSON
                        with open(path, "w") as f:
                            json.dump(default_rds, f)
                    except Exception as e:
                        # Print a clear error message if anything fails
                        print(f"[RDS] Failed to recreate {path}: {e}")
            if os.path.exists(path):
                os.remove(path)
            with open(path, "w") as f:
                json.dump(default_rds, f)
        except Exception as e:
            print(f"[RDS] Failed to recreate {path}: {e}")
