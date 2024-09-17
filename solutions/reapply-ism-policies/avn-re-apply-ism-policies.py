# Re-apply migrated ISM policies.
#
# After migrating the indices and the policies, the policies need to be
# re-applied to the indices for them to take effect.
#
# NOTE! snapshot restore needs to be done with include_global_state enabled
# for the ISM policy assignments to be available in the cluster state.
#
import argparse
import json
import requests
import urllib3

from typing import Any


class AivenForOpensearchIsm:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        user: str,
        password: str,
    ):
        self.session = requests.Session()
        self.session.verify = False
        self.session.headers.update(
            {
                "Content-Type": "application/json",
                "Accept": "application/json",
            }
        )
        self.session.auth = (user, password)
        self.base_url = f"https://{host}:{port}"
        # Test connection
        r = self.session.get(self.base_url)
        r.raise_for_status()

    def already_applied(self) -> bool:
        # Check if the policies are already applied, if the "total_managed_indices"
        # is not zero then the policies are already applied.
        result = self.session.get(f"{self.base_url}/_plugins/_ism/explain")
        try:
            if result.status_code == 200:
                data = result.json()
                if data["total_managed_indices"] == 0:
                    return False
        except Exception as e:
            print("ERROR: Failed to check if policies are already applied")

        return True  # Assume policies have already applied if we cannot reliably determine it

    def retrieve_assignments_from_cluster_metadata(self) -> dict[str, Any]:
        result = self.session.get(
            f"{self.base_url}/_cluster/state/metadata/*?"
            "expand_wildcards=all&filter_path=metadata.indices.*.managed_index_metadata.policy_id"
        )
        try:
            if result.status_code != 200:
                print(f"ERROR: failed to retrieve policy assignments {result.text}")
                return {}
            data = result.json()
            assignments = {}
            for index, policy in data["metadata"]["indices"].items():
                policy_id = policy.get("managed_index_metadata", {}).get("policy_id")
                if not policy_id:
                    print(f"WARNING: Could not determine policy for {index}")
                assignments[index] = policy_id
            return assignments
        except Exception as e:
            print(f"ERROR: Failed to retrieve policy assignments: {e}")
            return {}

    def add_policy(self, *, index: str, policy_id: str) -> None:
        result = self.session.post(
            f"{self.base_url}/_plugins/_ism/add/{index}",
            json={
                "policy_id": policy_id,
            },
        )
        result.raise_for_status()


def init_argparse() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Migrate security configuration from Opendistro to Aiven for Opensearch"
    )
    parser.add_argument(
        "--config",
        type=str,
        required=True,
        help="Configuration for the migration",
    )
    return parser


def main() -> None:
    # Disable SSL warnings as we are not verifying the server certificate
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    parser = init_argparse()
    args = parser.parse_args()
    if not args.config:
        parser.print_help()
        return

    try:
        with open(args.config) as f:
            config = json.load(f)
    except Exception as e:
        print(f"ERROR: Failed to read the configuration file: {e}")

    try:
        aiven_ism = AivenForOpensearchIsm(
            host=config["host"],
            port=config["port"],
            user=config["user"],
            password=config["password"],
        )
    except requests.exceptions.ConnectionError as e:
        print(f"ERROR: Failed to connect to AivenForOpensearch: {e}")
        print(
            "Please make sure that service is running and accessible and "
            "the host and port are correct."
        )
        return
    except requests.exceptions.HTTPError as e:
        print(f"ERROR: Failed to connect to AivenForOpensearch: {e}")
        print("Please make sure that the credentials are correct.")
        return
    except Exception as e:
        print(f"ERROR: Failed to connect to AivenForOpensearch: {e}")
        return

    if aiven_ism.already_applied():
        print(
            "ERROR: Policies appear to be already applied. Re-applying them using "
            "this script is not possible."
        )
        return

    # Read the original ism assignments (after migration those are stored in cluster state)
    original_policy_assignments = aiven_ism.retrieve_assignments_from_cluster_metadata()
    if not original_policy_assignments:
        print(
            "ERROR: Failed to retrieve original policy assignments. Was restore done "
            "with include_global_state enabled?"
        )
        return

    # Re-apply the policies, there does not seem to be a way to do this in bulk so we need to execute this one by one
    applied_policies = {}
    failed_policies = {}
    for index, policy_id in original_policy_assignments.items():
        print(f"Re-applying {policy_id} to {index}", end=" ")
        try:
            aiven_ism.add_policy(index=index, policy_id=policy_id)
            print("OK")
            if policy_id not in applied_policies:
                applied_policies[policy_id] = 1
            else:
                applied_policies[policy_id] += 1
        except Exception as e:
            print(f"FAILED {e}")
            if policy_id not in failed_policies:
                failed_policies[policy_id] = 1
            else:
                failed_policies[policy_id] += 1

    if applied_policies:
        print("Re-applied policies:")
        for policy_id, count in applied_policies.items():
            print(f"  {policy_id}: {count}")
    else:
        print("No policies re-applied")

    if failed_policies:
        print("Failed to re-apply policies:")
        for policy_id, count in failed_policies.items():
            print(f"  {policy_id}: {count}")
    else:
        print("No policies failed to be re-applied")
    return


if __name__ == "__main__":
    main()
