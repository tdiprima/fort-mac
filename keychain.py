# Utility for retrieving secrets from the macOS Keychain.
import os
import subprocess

KEYCHAIN_SERVICE = "mac_update_conga"


def get_conga_from_keychain() -> str:
    """Retrieve the CONGA secret from the macOS Keychain."""
    result = subprocess.run(
        [
            "security",
            "find-generic-password",
            "-a", os.environ["USER"],
            "-s", KEYCHAIN_SERVICE,
            "-w",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Could not retrieve CONGA from Keychain. "
            f"Store it first with:\n"
            f'  security add-generic-password -a "$USER" -s "{KEYCHAIN_SERVICE}" -w "<value>"'
        )
    return result.stdout.strip()
