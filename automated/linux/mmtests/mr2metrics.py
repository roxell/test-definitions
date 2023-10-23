# Converts MMTests exported test results from JSON format to "metrics" format,
# which SQUAD can understand.
import os
import json
import argparse
import re


def extract_metrics(log_data, config):
    """Extracts metrics from MMTests exported JSON data.
    :param log_data: MMTests exported JSON data
    :param config: MMTests configuration name
    :return: Dictionary of metrics
    """
    data = json.loads(log_data)
    results = data["results"]
    summary = {}

    ops = results["_OperationsSeen"].keys()
    for op in ops:
        if op in results["_ResultData"].keys():
            values = []

            for r in results["_ResultData"][op]:
                if r:
                    values += r["Values"]

            summary[config + "/" + op] = [float(x) for x in values]

    return summary


def extract_filename(file_path):
    return os.path.basename(file_path)


def extract_info(input_string):
    """Extracts benchmark name and config from filename.
    :param input_string: Filename
    :return: Tuple of benchmark name and config
    """
    pattern = r"BENCHMARK(.+)_CONFIG(.+).json"
    match = re.search(pattern, input_string)

    if match:
        benchmark = match.group(1)
        cfg = match.group(2)
        return benchmark, cfg
    else:
        return None, None


def parse_args():
    parser = argparse.ArgumentParser(description="...")
    parser.add_argument(
        "json_file",
        type=str,
        help="Absolute path to JSON file",
    )
    parser.add_argument(
        "output_file",
        type=str,
        help="Absolute path to output file",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    filename = extract_filename(args.json_file)
    benchmark_name, config = extract_info(filename)
    if not benchmark_name or not config:
        raise ValueError(f"Unable to parse filename: {filename}")
    print("Processing file: {}".format(args.json_file))
    with open(args.json_file, "r") as f:
        raw_data = f.read()
        if raw_data:
            metrics = extract_metrics(raw_data, config)
            with open(args.output_file, "w") as dump:
                print("Dumping metrics to: {}".format(args.output_file))
                json.dump(metrics, dump, indent=2, sort_keys=True)
