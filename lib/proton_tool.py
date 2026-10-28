#!/usr/bin/env python3
"""DroidDeck-Proton and the tool droiddeck-proton-run picks, answered by DroidDeck's own code.

    proton_tool.py find BIN STEAM_ROOT          newest DroidDeck-Proton build: "name<TAB>dir"
    proton_tool.py chosen BIN STEAM_ROOT APPID  the tool droiddeck-proton-run uses for APPID
    proton_tool.py request BIN APPID DIR        ask DroidDeck to run APPID with the build in DIR

BIN is the folder holding steam-compatibility and droiddeck-proton-run (normally /usr/local/bin).
request adds the same per-game entry the DroidDeck app writes when a game's Proton is picked in it
(~/.local/share/droiddeck-compat/games.json); DroidDeck applies it to Steam's CompatToolMapping.
"""
import os
import runpy
import sys

OWN_PROTON = "DroidDeck-Proton"


def compat(bin_dir):
    return runpy.run_path(os.path.join(bin_dir, "steam-compatibility"))


def find(bin_dir, steam_root):
    c = compat(bin_dir)
    builds = [t for t in c["tool_catalog"](steam_root)
              if not t["valve"] and t["dir"].startswith(c.get("OWN_PROTON", OWN_PROTON))]
    if not builds:
        return None
    best = max(builds, key=lambda t: (c["build_key"](t["dir"]), t["dir"]))
    return best["name"], best["dir"]


def chosen(bin_dir, steam_root, appid):
    run = runpy.run_path(os.path.join(bin_dir, "droiddeck-proton-run"))
    name, _ = run["choose_tool"](str(appid), run["mapping"](steam_root), run["tools"](steam_root))
    return name or ""


def request(bin_dir, appid, directory):
    c = compat(bin_dir)
    for _ in range(3):
        games, original = c["read_game_requests"]()
        games = dict(games)
        games[str(appid)] = {"valve": False, "dir": directory}
        if c["write_game_requests"](games, original):
            return True
    return False


def main(argv):
    if len(argv) == 3 and argv[0] == "find":
        found = find(argv[1], argv[2])
        if not found:
            return 1
        print("\t".join(found))
        return 0
    if len(argv) == 4 and argv[0] == "chosen":
        print(chosen(argv[1], argv[2], argv[3]))
        return 0
    if len(argv) == 4 and argv[0] == "request":
        return 0 if request(argv[1], argv[2], argv[3]) else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
