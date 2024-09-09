# Migrate security configuration from Opendistro to Aiven for Opensearch
#
# The script will analyze the security configuration in Opendistro and Aiven for
# Opensearch and determine what needs to be done to migrate the configuration
# from Opendistro to Aiven for Opensearch.
#
# Migration actions are limited to adding and updating roles, roles mappings,
# action groups, tenants, and internal users. Nothing else will be migrated.
#
# NOTE! any resources that are reserved (or static) in Aiven for Opensearch
# cannot be modified via the REST API. Any resources that are marked as
# reserved or static in Opendistro are not migrated. Hidden flags are ignored.
#
import argparse
import base64
import json
import requests
import urllib3

from typing import Any

SECURITY_CONFIG_SECTIONS = [
    "roles",
    "rolesmapping",
    "actiongroups",
    "tenants",
    "internalusers",
]

AIVEN_SECURITY_MANAGER = "os-sec-admin"


class OpendistroSecurity:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        clientCrt: str,
        clientKey: str,
    ):
        self.session = requests.Session()
        self.session.verify = False
        self.session.headers.update(
            {
                "Content-Type": "application/json",
                "Accept": "application/json",
            }
        )
        self.session.cert = (clientCrt, clientKey)
        self.base_url = f"https://{host}:{port}"
        self.api_url = f"{self.base_url}/.opendistro_security/_doc"
        # Test connection
        r = self.session.get(self.base_url)
        r.raise_for_status()

    def get(self, entry: str) -> dict[str, Any]:
        # We need to use the direct _doc "interface" as the standard security
        # API does not return the password hash for users which is needed for
        # migration.
        url = f"{self.api_url}/{entry}"
        r = self.session.get(url)
        d = r.json()
        if d.get("_id") == entry:
            content = json.loads(
                base64.b64decode(d.get("_source", {}).get(entry, "")).decode("utf-8")
            )
            meta = content.pop("_meta", None)
            if meta is None:
                raise ValueError(f"Missing _meta in {entry}")
            if meta.get("config_version", 0) != 2:
                raise ValueError(f"Unsupported config_version in {entry}")
            if meta.get("type", "") != entry:
                raise ValueError(f"Invalid type in _meta for {entry}")
            return content
        return {}


class AivenForOpensearchSecurity:
    def __init__(
        self,
        *,
        host: str,
        port: int,
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
        self.session.auth = (AIVEN_SECURITY_MANAGER, password)
        self.base_url = f"https://{host}:{port}"
        self.api_url = f"{self.base_url}/_plugins/_security/api"
        # Test connection
        r = self.session.get(self.base_url)
        r.raise_for_status()

    def get(self, entry: str) -> dict[str, Any]:
        url = f"{self.api_url}/{entry}"
        r = self.session.get(url)
        return r.json()

    def patch(
        self, *, section: str, actions: list[dict[str, Any]]
    ) -> requests.Response:
        url = f"{self.api_url}/{section}"
        return self.session.patch(url, json=actions)


def untouchable_if_field_set(
    *,
    entries: dict[str, Any],
    fields: set[str],
) -> tuple[set[str], set[str]]:
    return {k for k in entries.keys()}, {
        k for k, v in entries.items() if any(v.get(field, False) for field in fields)
    }


# Go thru the config entries
# - if the entry is not reserved or static and is not present in Aiven it
#   should be created.
# - if it exists in Aiven but is different it should be updated
#   unless it is marked static or reserved or explicitly marked as untouchable
def simple_analyzes(
    *,
    opendistro: dict[str, Any],
    aiven: dict[str, Any],
    untouchables: set[str] | None = None,
) -> tuple[set[str], set[str]]:
    if untouchables is None:
        untouchables = set()
    os_entries, os_unmovable = untouchable_if_field_set(
        entries=opendistro,
        fields={"reserved", "static"},
    )
    aiven_entries, aiven_untouchables = untouchable_if_field_set(
        entries=aiven,
        fields={"reserved", "static", "hidden"},
    )
    aiven_untouchables.update(untouchables)  # add any additional untouchables
    valid_os_entries = os_entries - os_unmovable - aiven_untouchables
    new_entries = valid_os_entries - aiven_entries
    updated_entries = valid_os_entries & aiven_entries
    return new_entries, updated_entries


def simple_actions(
    opendistro: dict[str, Any],
    aiven: dict[str, Any],
    untouchables: set[str] | None = None,
) -> dict[str, dict[str, Any]]:
    # Go thru entries in a section and identify which entries need
    # to be added and which ones need to be updated
    if untouchables is None:
        untouchables = set()
    new, updated = simple_analyzes(
        opendistro=opendistro,
        aiven=aiven,
        untouchables=untouchables,
    )
    return {
        "add": {new: opendistro[new] for new in new},
        "update": {update: opendistro[update] for update in updated},
    }


PREDEFINED_UNTOUCHABLES = {
    "internalusers": {AIVEN_SECURITY_MANAGER},
    "rolesmapping": {"manage_snapshots"},
}


def analyze_security_configurations(
    *,
    opendistro: dict[str, Any],
    aiven: dict[str, Any],
) -> dict[str, dict[str, dict[str, Any]]]:
    # Go thru the security configuration sections and identify
    # entries that need to be added or updated in each section
    actions: dict[str, dict[str, dict[str, Any]]] = {}
    for entry in SECURITY_CONFIG_SECTIONS:
        actions.update(
            {
                entry: simple_actions(
                    opendistro=opendistro[entry],
                    aiven=aiven[entry],
                    untouchables=PREDEFINED_UNTOUCHABLES.get(entry, None),
                ),
            }
        )
    return actions


def inplace_filter_non_migratable_fields(d: dict[str, Any]) -> dict[str, Any]:
    # Remove the values we never migrate
    # NOTE! this does inplace modification, but as this is part of final
    # migration step these fields are not needed anymore.
    d.pop("static", None)
    # Following need to always be False for migration to work
    for key in ["hidden", "reserved"]:
        if d.pop(key, None):
            d[key] = False


def simple_adder(*, section: str, entries: dict[str, Any]) -> list[dict[str, Any]]:
    # Create list of patch actions to add the missing entries
    actions: list[dict[str, Any]] = []
    for path, values in entries.items():
        inplace_filter_non_migratable_fields(values)
        actions.append(
            {
                "op": "add",
                "path": f"/{path}",
                "value": values,
            }
        )
        print(f"- add {path}")
    return actions


def get_filtered_for_migration(
    *, name: str, entry: dict[str, Any], aiven: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    aiven_entry = aiven.get(name, {})
    if not aiven_entry:
        raise RuntimeError(f"Missing {name} in Aiven configuration")
    inplace_filter_non_migratable_fields(entry)
    inplace_filter_non_migratable_fields(aiven_entry)
    return entry, aiven_entry


def section_aware_updater(
    *,
    section: str,
    entries: dict[str, Any],
    aiven_config: dict[str, Any],
) -> list[dict[str, Any]]:
    # TODO: actually implement the section awareness
    actions: list[dict[str, Any]] = []
    for path, values in entries.items():
        os_values, aiven_values = get_filtered_for_migration(
            name=path,
            entry=values,
            aiven=aiven_config[section],
        )

        # If the values are the same, we don't need to do anything
        changed = False

        # Any section specific processing goes here
        # for rolesmapping we need to make sure the os-sec-admin is
        # not unmapped from any role it has been assigned
        if section == "rolesmapping":
            if "users" not in os_values:
                os_values["users"] = list()
            if (
                AIVEN_SECURITY_MANAGER in aiven_values["users"]
                and AIVEN_SECURITY_MANAGER not in os_values["users"]
            ):
                os_values["users"].add(AIVEN_SECURITY_MANAGER)

            keys = set(os_values.keys())
            keys.update(set(aiven_values.keys()))

            for key in keys:
                os_value = os_values.get(key, None)
                aiven_value = aiven_values.get(key, None)
                if os_value or aiven_value:
                    changed |= os_value != aiven_value
        else:
            changed = os_values != aiven_values

        if not changed:
            print(f"- skip {path} [unchanged]")
            continue

        aiven_values.update(os_values)
        actions.append(
            {
                "op": "replace",
                "path": f"/{path}",
                "value": aiven_values,
            }
        )
        print(f"- update {path}")

    return actions


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
    # Disable SSL warnings as we are not verifying the server certificates
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
        print(f"Failed to read configuration file: {e}")

    try:
        opendistro_security = OpendistroSecurity(
            host=config["source"]["host"],
            port=config["source"]["port"],
            clientCrt=config["source"]["certificate"],
            clientKey=config["source"]["key"],
        )
    except requests.exceptions.ConnectionError as e:
        print(f"Failed to connect to Opendistro: {e}")
        print(
            "Please make sure that Opendistro is running and accessible and "
            "the host and port are correct."
        )
        return
    except requests.exceptions.HTTPError as e:
        print(f"Failed to connect to Opendistro: {e}")
        print("Please make sure that the client certificate and key are correct.")
        return
    except Exception as e:
        print(f"Failed to connect to Opendistro: {e}")
        return

    try:
        aiven_security = AivenForOpensearchSecurity(
            host=config["target"]["host"],
            port=config["target"]["port"],
            password=config["target"]["password"],
        )
    except requests.exceptions.ConnectionError as e:
        print(f"Failed to connect to AivenForOpensearch: {e}")
        print(
            "Please make sure that service is running and accessible and "
            "the host and port are correct."
        )
        return
    except requests.exceptions.HTTPError as e:
        print(f"Failed to connect to AivenForOpensearch: {e}")
        print("Please make sure that the password for os-sec-admin user is correct.")
        return
    except Exception as e:
        print(f"Failed to connect to AivenForOpensearch: {e}")
        return

    # Get the security configurations
    opendistro_configuration: dict[str, Any] = {}
    aiven_configuration: dict[str, Any] = {}
    print("Retrieving configurations")
    print(f"          Opendistro: {opendistro_security.base_url}")
    print(f"Aiven for Opensearch: {aiven_security.base_url}")
    print()
    for entry in SECURITY_CONFIG_SECTIONS:
        try:
            opendistro_configuration[entry] = opendistro_security.get(entry)
            aiven_configuration[entry] = aiven_security.get(entry)
        except Exception as e:
            print(f"Failed to get security configuration {entry}: {e}")
            print("Contact support with the error message above.")
            return

    actions = analyze_security_configurations(
        opendistro=opendistro_configuration,
        aiven=aiven_configuration,
    )

    if not actions:
        print("Nothing to migrate.")
        return

    for entry, action in actions.items():
        print(f"Migrating {entry}")
        try:
            additions = simple_adder(section=entry, entries=action["add"])
            if additions:
                result = aiven_security.patch(section=entry, actions=additions)
                if not result.ok:
                    print(f"Failed to add {entry}: {result}")
                    print("Contact support with the error message above.")
                    return
        except Exception as e:
            print(f"Failed to migrate {entry}: {e}")
            print("Contact support with the error message above.")
            return
        try:
            updates = section_aware_updater(
                section=entry,
                entries=action["update"],
                aiven_config=aiven_configuration,
            )
            if updates:
                result = aiven_security.patch(section=entry, actions=updates)
                if not result.ok:
                    print(f"Failed to update {entry}: {result}")
                    print("Contact support with the error message above.")
                    return
        except Exception as e:
            print(f"Failed to update {entry}: {e}")
            print("Contact support with the error message above.")
            return
        print()


if __name__ == "__main__":
    main()
