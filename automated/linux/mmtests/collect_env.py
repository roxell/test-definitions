# Usage: python3 collect_env.py <path_to_config_file>
import json
import subprocess
import sys

OUTPUT_FILE = "mmtests_config_env.json"


def capture_env(cmd):
    """Executes a command using subprocess and captures environment variables.
    :param cmd: Command string to execute.
    :return: A dictionary of the environment variables with their values.
    """
    # It's assumed that shell is bash!
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, shell=True, executable="/bin/bash"
    )
    output, _ = proc.communicate()
    env_lines = output.decode().split("\n")
    capture = {}
    for line in env_lines:
        if "=" in line:
            var_name, var_value = line.split("=", 1)
            capture[var_name] = var_value
    return capture


def collect_vars(config_path):
    """Sources the config file and extracts only the variables that were exported.
    :param config_path: Path to the configuration file
    :return: A dict of the sourced env vars
    """
    pre_env = capture_env("env")
    post_env = capture_env(f"source {config_path} && env")
    # Find diff
    exported_variables = {
        key: post_env[key]
        for key in post_env.items()
        if key not in pre_env or post_env[key] != pre_env[key]
    }

    return exported_variables


if __name__ == "__main__":
    file_path = sys.argv[1]
    data = collect_vars(file_path)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as json_file:
        json.dump(data, json_file, indent=4)
