"""
This script provides functionality for submitting test metrics along with
attachment to a SQUAD server.

The script is designed to work in tandem with `mr2metrics` to produce a
`metrics.json` metrics file compatible with SQUAD.

SQUAD token can be provided as a command line argument or as an environment
variable SQUAD_AUTH_TOKEN.

Example:
    python submit_metrics.py -s <server_URL> -g <group_name> -p <project_name>
                          -e <environment_name> -b <build_name>
                          -m <metrics_file_path> -a <attachment_file_path>
                          -t <token>
"""

import http.client
import os
import sys
import argparse
from dataclasses import dataclass


@dataclass
class SquadConfig:
    """Configuration object for SQUAD
    :param server: SQUAD server URL
    :param token: SQUAD token
    :param group: SQUAD group name
    :param project: SQUAD project name
    :param env: SQUAD environment name
    :param build: SQUAD build name
    """

    server: str
    token: str
    group: str
    project: str
    env: str
    build: str


def submit_results(connection, squad_url, http_headers, body):
    """Submit results to SQUAD server.
    :param connection: Connection object
    :param squad_url: URL
    :param http_headers: Dictionary of headers
    :param body: String with payload
    """
    try:
        connection.request("POST", squad_url, headers=http_headers, body=body)
    except http.client.HTTPException as e:
        print(f"HTTP Error: {e}")
        raise e
    res = connection.getresponse()
    data = res.read()
    print(data.decode("utf-8"))
    connection.close()


def read_file(path):
    """Read file content.
    :param path: Path to the file
    :return: File content
    """
    with open(path, "rb") as f:
        return f.read()


def build_headers(token):
    """Build headers for the POST request to SQUAD server.
    :param token: SQUAD token
    :return: Dictionary of headers
    """
    return {
        "Auth-Token": token,
        "Content-Type": "multipart/form-data; boundary=WebAppBoundary",
    }


def build_payload(attachment_data, metrics_data):
    """Build payload for the POST request to SQUAD server.
    :param attachment_data: Attachment file content
    :param metrics_data: Metrics file content
    :return: String with payload
    """
    return (
        f"--WebAppBoundary\r\n"
        f'Content-Disposition: form-data; name="attachment"; filename="metrics.json"\r\n\r\n'
        f"{attachment_data.decode('utf-8')}\r\n"
        f"--WebAppBoundary\r\n"
        f'Content-Disposition: form-data; name="metrics"; filename="attachment.json"\r\n\r\n'
        f"{metrics_data.decode('utf-8')}\r\n"
        f"--WebAppBoundary--"
    )


def build_url(sq: SquadConfig):
    """Build URL for the POST request to SQUAD server.
    :param sq: SQUAD configuration object
    :return: String with URL
    """
    return f"/api/submit/{sq.group}/{sq.project}/{sq.build}/{sq.env}/"


def get_connection(sq: SquadConfig):
    """Get connection to SQUAD server.
    :param sq: SQUAD configuration object
    :return: Connection object
    """
    return http.client.HTTPSConnection(sq.server)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="This script submits test metrics and attachments to a SQUAD server."
    )
    parser.add_argument(
        "-s",
        metavar="SERVER_URL",
        type=str,
        required=True,
        help="URL of the SQUAD server",
    )
    parser.add_argument(
        "-g", metavar="GROUP_NAME", type=str, required=True, help="SQUAD group name"
    )
    parser.add_argument(
        "-p", metavar="PROJECT_NAME", type=str, required=True, help="SQUAD project name"
    )
    parser.add_argument(
        "-e", metavar="ENV_NAME", type=str, required=True, help="SQUAD environment name"
    )
    parser.add_argument(
        "-b", metavar="BUILD_NAME", type=str, required=True, help="SQUAD build name"
    )
    parser.add_argument(
        "-m",
        metavar="METRICS_PATH",
        type=str,
        required=True,
        help="Path to the metrics file",
    )
    parser.add_argument(
        "-a",
        metavar="ATTACHMENT_PATH",
        type=str,
        required=True,
        help="Path to the attachment file",
    )
    parser.add_argument(
        "-t",
        metavar="TOKEN",
        type=str,
        default=os.environ.get("SQUAD_AUTH_TOKEN", None),
        help="Authentication token for the SQUAD server.",
    )

    args = parser.parse_args()

    if args.t is None:
        print("Error:-t not provided and SQUAD_AUTH_TOKEN env variable is not set.")
        sys.exit(1)

    config = SquadConfig(
        args.s,
        args.t,
        args.g,
        args.p,
        args.e,
        args.b,
    )
    conn = get_connection(config)
    url = build_url(config)
    headers = build_headers(config.token)
    metrics_content = read_file(args.m)
    attachment_content = read_file(args.a)
    payload = build_payload(attachment_content, metrics_content)
    submit_results(conn, url, headers, payload)
