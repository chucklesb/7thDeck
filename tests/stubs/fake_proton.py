"""A compatibilitytools.d entry shaped like a DroidDeck-Proton release, for tests."""
import os

VDF = '''"compatibilitytools"
{
  "compat_tools"
  {
    "%s"
    {
      "install_path" "."
      "display_name" "%s"
      "from_oslist"  "windows"
      "to_oslist"    "linux"
    }
  }
}
'''
MANIFEST = '''"manifest"
{
  "version" "2"
  "commandline" "/proton %verb%"
}
'''


def make_tool(tools, name):
    folder = os.path.join(tools, name)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "compatibilitytool.vdf"), "w") as f:
        f.write(VDF % (name, name))
    with open(os.path.join(folder, "toolmanifest.vdf"), "w") as f:
        f.write(MANIFEST)
    proton = os.path.join(folder, "proton")
    with open(proton, "w") as f:
        f.write("#!/bin/sh\nexit 0\n")
    os.chmod(proton, 0o755)
    return folder


def prefer_valve(home):
    """The state of a user who picked Valve's Proton ARM64 as their default in the DroidDeck app."""
    import json
    state = os.path.join(home, ".local/share/droiddeck-compat/state.json")
    with open(state) as f:
        data = json.load(f)
    data.update(default="droiddeck-proton-arm64", source="app")
    with open(state, "w") as f:
        json.dump(data, f)
    config = os.path.join(home, ".local/share/Steam/config/config.vdf")
    with open(config) as f:
        text = f.read()
    with open(config, "w") as f:
        f.write(text.replace('"DroidDeck-Proton-11-11.9"', '"droiddeck-proton-arm64"', 1))


if __name__ == "__main__":
    import sys
    if sys.argv[1:2] == ["prefer-valve"]:
        prefer_valve(sys.argv[2])
