# Updates Rust and Homebrew, upgrades installed packages, cleans up, and
# checks system health, handling exceptions and keyboard interrupts.
# nosec B404, B603, B607
import logging
import os
import subprocess

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger(__name__)

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


try:
    logger.info("Updating Cargo...")
    subprocess.run(["rustup", "update"])
    logger.info("Cargo updated.")

    conga = get_conga_from_keychain()

    logger.info("Updating Homebrew...")
    subprocess.run(["brew", "update"])
    subprocess.run(["brew", "upgrade"], input=conga, text=True)
    subprocess.run(["brew", "cleanup", "-s"])
    subprocess.run(["brew", "doctor"])
    logger.info("Homebrew updated.")
except RuntimeError as e:
    logger.error(e)
except Exception as e:
    logger.exception("Unexpected error: %s", e)
except KeyboardInterrupt:
    logger.info("Stopping.")
