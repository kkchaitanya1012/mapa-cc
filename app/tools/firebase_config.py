#!/usr/bin/env python3
"""Copy the four Firebase values the app needs out of google-services.json.

    python3 tools/firebase_config.py ~/Downloads/google-services.json

Adds FIREBASE_* to config.android.json (the file is gitignored). Prints names, never values.
"""
import json
import sys
from pathlib import Path

if len(sys.argv) != 2:
    sys.exit(__doc__)
g = json.loads(Path(sys.argv[1]).expanduser().read_text())
client = next(c for c in g["client"] if c["client_info"]["android_client_info"]["package_name"] == "app.mapa.mapa")
values = {
    "FIREBASE_PROJECT_ID": g["project_info"]["project_id"],
    "FIREBASE_SENDER_ID": g["project_info"]["project_number"],
    "FIREBASE_APP_ID": client["client_info"]["mobilesdk_app_id"],
    "FIREBASE_API_KEY": client["api_key"][0]["current_key"],
}
cfg_path = Path(__file__).resolve().parent.parent / "config.android.json"
cfg = json.loads(cfg_path.read_text())
cfg.update(values)
cfg_path.write_text(json.dumps(cfg, indent=2))
print("added to config.android.json:", ", ".join(values))
