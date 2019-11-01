#!/usr/bin/env python
# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/


import argparse
import logging
import os

from cassandra_example import cassandra_example


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', help="Cassandra host", required=True)
    parser.add_argument('--port', help="Cassandra port", required=True, type=int)
    parser.add_argument('--username', help="Cassandra username", default='avnadmin')
    parser.add_argument('--password', help="Cassandra password", required=True)
    parser.add_argument('--ca-path', help="Path to cluster CA certificate", default='ca.pem')
    args = parser.parse_args()

    if not os.path.isfile(args.ca_path):
        logging.error("Could not locate CA certificate at path: %s. \n"
                      "You can download it from the Overview tab in the Aiven console, "
                      "or retrieve it with the Aiven command line client (https://github.com/aiven/aiven-client): \n"
                      "'avn project ca-get --project <project-name> --target-filepath ./ca.pem'" % args.ca_path)
        exit(1)

    cassandra_example(args)


if __name__ == '__main__':
    main()
