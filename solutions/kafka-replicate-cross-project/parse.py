import argparse
import json

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('ips')

    args = parser.parse_args()
    ips = json.loads(args.ips)
    for i, ip in enumerate(ips):
        ips[i] = str(ip) + '/32'
    ips = json.dumps(ips)[1:-1]
    ips = ips.replace(', ', ",")
    ips = ips.replace('"', '')
    print(ips)
