#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
cosmos_v5_stream_example.py
"""
import argparse
import json
import os
import logging

# See openc3/docs/environment.md for environment documentation

os.environ["OPENC3_API_PASSWORD"] = "password"
os.environ["OPENC3_LOG_LEVEL"] = "INFO"
os.environ["OPENC3_API_SCHEMA"] = "http"
os.environ["OPENC3_API_HOSTNAME"] = "127.0.0.1"
os.environ["OPENC3_API_PORT"] = "2900"

from openc3.stream_api.data_extractor_client import DataExtractorClient

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
    }
    with open(metadata_file, "w") as f:
        f.write(json.dumps(metadata, indent=4))


def output(args, data, data_path, filename):
    if not data:
        return
    try:
        output_metadata(args, data_path)
        output_data_to_file(data, filename)
    except OSError as e:
        logging.exception(f"failed to output data, {e}")


# item example: INST.ADCS.POSX
def main():
    parser = argparse.ArgumentParser()
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

    data_path = "./"
    filename = os.path.join(data_path, "data.csv")

    if os.path.exists(filename):
        print(filename)
        return

    try:
        api = DataExtractorClient(
            items=args.items,
            start_time=args.start,
            end_time=args.end,
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
