#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
cosmos_v5_stream_example.py
"""
import argparse
import hashlib
import json
import os
import logging

# See cosmosc2/docs/environment.md for environment documentation

os.environ["COSMOS_VERSION"] = "1.1.1"
os.environ["COSMOS_API_PASSWORD"] = "www"
os.environ["COSMOS_LOG_LEVEL"] = "INFO"
os.environ["COSMOS_WS_SCHEMA"] = "ws"
os.environ["COSMOS_API_HOSTNAME"] = "127.0.0.1"
os.environ["COSMOS_API_PORT"] = "2900"

# os.environ["COSMOS_DATA"] = "\\git\\tmp\\"

from cosmosc2.stream_api.data_extractor_client import DataExtractorClient


def hash_args(args):
    return hashlib.sha1(
        " ".join(
            [" ".join([item for item in args.items]), args.start, args.end, args.mode]
        ).encode("utf-8")
    ).hexdigest()[:16]


def output_data_to_file(data, filename):
    with open(filename, "w") as f:
        f.write("ITEM,VALUE,TIME\n")
        for d in data:
            f.write(f"{d['item']},{d['value']},{d['time']}\n")
    print(filename)


def output_metadata(args, data_path):
    metadata_file = os.path.join(data_path, "metadata.json")
    metadata = {
        "items": args.items,
        "start": args.start,
        "end": args.end,
        "mode": args.mode,
    }
    with open(metadata_file, "w") as f:
        f.write(json.dumps(metadata, indent=4))


def output(args, data, data_path, filename):
    if not data:
        return
    try:
        os.makedirs(data_path)
        output_metadata(args, data_path)
        output_data_to_file(data, filename)
    except OSError as e:
        logging.exception(f"failed to output data, {e}")


# item example: INST.ADCS.POSX
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "mode", type=str, choices=["CONVERTED", "DECOM", "WITH_UNITS", "RAW"], help="item mode"
    )
    parser.add_argument(
        "start", type=str, help="start time in format: '2022/01/24 11:04:19'"
    )
    parser.add_argument(
        "end", type=str, help="end time in format: '2022/01/25 11:04:19'"
    )
    parser.add_argument(
        "items", type=str, nargs="+", help="item in format: INST.ADCS.POSX"
    )
    args = parser.parse_args()

    dir_name = hash_args(args)
    home = os.path.expanduser("~")
    data_home = os.getenv("COSMOS_DATA", home)
    data_path = os.path.join(data_home, "cosmosc2", dir_name)
    filename = os.path.join(data_path, "data.csv")

    if os.path.isdir(dir_name) and os.path.exists(filename):
        print(filename)
        return

    try:
        api = DataExtractorClient(
            items=args.items,
            start_time=args.start,
            end_time=args.end,
            mode=args.mode,
        )
        data = api.get()
        output(args, data, data_path, filename)
    except ValueError as e:
        logging.error(e)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception as err:
        logging.exception(err)
