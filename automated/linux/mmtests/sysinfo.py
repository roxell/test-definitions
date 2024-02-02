import argparse
import json
import re
import subprocess

UNKNOWN = "UNKNOWN"
OUTFILE = "sysinfo.json"
# Note: it would be better to add lshw, dmidecode, and other tools to the image
# to collect more detailed information about the system


def run_command(command):
    """Run a shell command and return its output as a string."""
    try:
        out = subprocess.check_output(
            command, shell=True, stderr=subprocess.STDOUT
        ).decode("utf-8")
        return out.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.cmd}, exit status: {e.returncode}")
        return ""


def parse_cpu_info():
    """Parse CPU information from lscpu command."""
    cpu_info = run_command("lscpu")
    caches = {
        line.split(":")[0]: line.split(":")[1].strip()
        for line in cpu_info.splitlines()
        if "cache" in line.lower()
    }
    match = re.search(r"CPU MHz:\s+(\S+)", cpu_info)
    freq = match.group(1) if match else UNKNOWN
    return {
        "Arch": re.search(r"Architecture:\s+(\S+)", cpu_info).group(1),
        "Cores": int(re.search(r"^CPU\(s\):\s+(\d+)", cpu_info, re.MULTILINE).group(1)),
        "Frequency": f"{freq}MHz",
        "Caches": caches,
    }


def parse_memory_info():
    """Parse memory information from /proc/meminfo."""
    mem_info = run_command("grep MemTotal /proc/meminfo")
    total = int(re.search(r"\d+", mem_info).group(0)) // 1024
    return {
        "Total": f"{total} MB",
        "Speed": UNKNOWN,
    }


def parse_storage_info():
    """Parse storage information from lsblk command."""
    # Remove header and split lines
    block_info = run_command("lsblk -b -o NAME,SIZE,TYPE,MOUNTPOINT").splitlines()[1:]
    disks = []
    current_disk = None

    for line in block_info:
        parts = line.split()
        name = parts[0]

        # Remove Unicode characters
        name = re.sub(r"[\u2500-\u257F]", "", name)
        size = f"{int(parts[1]) // (1024 ** 3)}G"
        block_type = parts[2]
        mountpoint = parts[3] if len(parts) > 3 else "Not mounted"

        if type == "disk":
            if current_disk:
                disks.append(current_disk)
            current_disk = {"Name": name, "Size": size, "Partitions": []}
        elif block_type == "part" and current_disk:
            partition = {"Name": name, "Size": size, "Mountpoint": mountpoint}
            current_disk["Partitions"].append(partition)

    if current_disk:
        disks.append(current_disk)
    return {"Disks": disks}


def parse_os_info():
    """Parse OS information from /etc/os-release."""
    os_info = "Unknown"
    try:
        with open("/etc/os-release", "r") as osfile:
            for line in osfile:
                if line.startswith("PRETTY_NAME"):
                    os_info = line.split("=")[1].strip().strip('"')
                    break
    except Exception as e:
        os_info = f"Error retrieving OS information: {str(e)}"

    return {
        "Name": os_info,
        # TODO: Add when needed
        "Packages list": UNKNOWN,
    }


def parse_kernel_version():
    """Parse kernel version and config path."""
    kernel_version = run_command("uname -r")
    return {
        "Version": kernel_version,
        # Here must be a link to tuxsuite's build
        "Config": UNKNOWN,
    }


def parse_filesystem_info():
    """Parse filesystem information from df command."""
    df_info = run_command("df -Th").splitlines()[1:]  # Skip header
    fses = []
    for line in df_info:
        name, fs_type, size, used, avail, use_perc, mounted_on = line.split(None, 6)
        # Filter out loop and tmpfs
        if "loop" not in name and "tmpfs" not in fs_type:
            fs = {
                "Name": name,
                "Type": fs_type,
                "Size": size,
                "Used": used,
                "Avail": avail,
                "Use%": use_perc.strip("%"),
                "Mounted on": mounted_on,
            }
            fses.append(fs)
    return {"Filesystems": fses}


def collect_system_info():
    """Build a dictionary with system information."""
    return {
        "CPU": parse_cpu_info(),
        "Memory": parse_memory_info(),
        "Storage": parse_storage_info(),
        "OS": parse_os_info(),
        "Kernel version": parse_kernel_version(),
        "Filesystem": parse_filesystem_info(),
    }


if __name__ == "__main__":
    system_info = collect_system_info()
    with open(OUTFILE, "w", encoding="utf-8") as f:
        json.dump(system_info, f, indent=4)
