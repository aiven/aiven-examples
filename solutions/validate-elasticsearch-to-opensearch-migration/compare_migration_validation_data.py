"""
This script connects to an Elasticsearch cluster to gather information about specific indices that match provided patterns. It gets key details like document count, aliases, and ISM (Index State Management) policies. It also tries to record any active indexing into the indices.

The output is in a tabular format, and the severity of each issue found is described in the tables.

Script Usage

You can run the script with the following command:

python compare_migration_validation_data.py file1.json file2.json

Example Commands

It has been tested with python 3.11
To install dependencies:
pip install icecream rich

"""

import argparse
import json
from rich import print
from rich.console import Console
from rich.table import Table


def compare_indices(json1, json2):
    # Severity counters
    severity_0 = 0
    severity_1 = 0
    severity_2 = 0
    severity_3 = 0
    severity_4 = 0
    severity_5 = 0
    total_indices = 0

    # List to store indices with severity > 0
    mismatched_indices = []

    # Iterate over indices from the first JSON
    for index_name, data1 in json1.get("indices", {}).items():
        total_indices += 1
        data2 = json2.get("indices", {}).get(index_name)

        if not data2:
            severity_5 += 1
            mismatched_indices.append((index_name, 5))
            continue

        # Compare has_write_alias, ism_policy, and aliases
        if (
            data1["has_write_alias"] != data2["has_write_alias"]
            or data1["ism_policy"] != data2["ism_policy"]
            or data1["aliases"] != data2["aliases"]
        ):
            severity_4 += 1
            mismatched_indices.append((index_name, 4))
            continue  # Skip further comparison since severity 5 takes precedence

        # Compare document counts
        doc_count_mismatch = (
            data1["document_count"] != data2["document_count"]
            or data1["document_count2"] != data2["document_count2"]
        )

        if doc_count_mismatch:
            if data1["document_count_delta"]:
                severity_1 += 1
                mismatched_indices.append((index_name, 1))
            elif data1["has_write_alias"]:
                severity_2 += 1
                mismatched_indices.append((index_name, 2))
            else:
                severity_3 += 1
                mismatched_indices.append((index_name, 3))
        else:
            severity_0 += 1

    return {
        "total": total_indices,
        "severity_0": severity_0,
        "severity_1": severity_1,
        "severity_2": severity_2,
        "severity_3": severity_3,
        "severity_4": severity_4,
        "severity_5": severity_5,
        "mismatched_indices": mismatched_indices,  # Return the list of mismatched indices
    }


def compare_json_files(file1, file2):
    with open(file1) as f1, open(file2) as f2:
        json_data1 = json.load(f1)
        json_data2 = json.load(f2)

    result = compare_indices(json_data1, json_data2)

    print("\n")
    console = Console()
    table = Table(title="Results")
    # make individual severe rows red etc if wnated: https://github.com/Textualize/textual/discussions/2101
    table.add_column("Item", style="magenta")
    table.add_column("Severity", style="cyan", no_wrap=True)
    table.add_column("Number", style="red", no_wrap=True)
    table.add_column("Explanation", style="cyan", no_wrap=True)
    # data
    table.add_row("Total indices", "", f"{result['total']}", "Number of indices")
    table.add_row("Perfect Matches", "0", f"{result['severity_0']}", "No issues")
    table.add_row(
        "Indices with issues",
        ">0",
        f"{result['severity_1']+result['severity_2']+result['severity_3']+result['severity_4']+result['severity_5']}",
        "Issues or possible issues",
    )
    table.add_row("---------------", "-", "--", "-------------------------")
    table.add_row(
        "Probably ok",
        "1",
        f"{result['severity_1']}",
        "Diff nb docs, but indexing was ongoing",
    )
    table.add_row(
        "Probably ok",
        "2",
        f"{result['severity_2']}",
        "Diff nb docs, on index with write alias",
    )
    table.add_row(
        "Check Issues",
        "3",
        f"{result['severity_3']}",
        "Diff nb docs, no indexing found, no write alias",
    )
    table.add_row(
        "Major Issues", "4", f"{result['severity_4']}", "Diff in ISM, aliases"
    )
    table.add_row(
        "Missing index", "5", f"{result['severity_5']}", "Index was not restored"
    )
    console.print(table)
    # print("Result:")
    # print(f"Total indices                                                               : {result['total']}")
    # print(f"Perfect Matches                                                             : {result['severity_0']}")
    # print(f"Probably ok (severity 1, diff nb docs, but indexing was ongoing)            : {result['severity_1']}")
    # print(f"Probably ok (severity 2, diff nb docs, on index with write alias)           : {result['severity_2']}")
    # print(f"Check Issues (severity 3, diff nb docs, no indexing found, no write alias)  : {result['severity_3']}")
    # print(f"Major Issues (severity 4, diff in ISM, aliases)                             : {result['severity_4']}")
    # print(f"Major Issues (severity 5, missing index, not restored)                      : {result['severity_5']}")

    # Print indices with severity > 0
    if result["mismatched_indices"]:
        print("\n")
        table = Table(title="Indices with issues")
        table.add_column("Number", style="magenta")
        table.add_column("Index", style="cyan", no_wrap=True)
        table.add_column("Severity", style="red", no_wrap=True)
        # print("\nIndices with issues (severity > 0):")
        i = 0
        for index_name, severity in result["mismatched_indices"]:
            table.add_row(str(i), index_name, str(severity))
            # print(f"Index: {index_name}, Severity: {severity}")
            i += 1
        console.print(table)


def main():
    parser = argparse.ArgumentParser(
        description="Compare two JSON files containing index information."
    )
    parser.add_argument("file1", type=str, help="Path to the first JSON file")
    parser.add_argument("file2", type=str, help="Path to the second JSON file")

    args = parser.parse_args()

    compare_json_files(args.file1, args.file2)


if __name__ == "__main__":
    main()
