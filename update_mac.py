# Updates Rust and Homebrew, upgrades installed packages, cleans up, and
# checks system health, handling exceptions and keyboard interrupts.
# nosec B404, B603, B607
import logging
import subprocess

from keychain import get_conga_from_keychain

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


try:
    logger.info("Updating Cargo...")
    subprocess.run(["/Users/xxxxx/.cargo/bin/rustup", "update"])
    logger.info("Cargo updated.")

    conga = get_conga_from_keychain()

    logger.info("Updating Homebrew...")
    subprocess.run(["/usr/local/bin/brew", "update"])
    subprocess.run(["/usr/local/bin/brew", "upgrade"], input=conga, text=True)
    subprocess.run(["/usr/local/bin/brew", "cleanup", "-s"])
    subprocess.run(["/usr/local/bin/brew", "doctor"])
    logger.info("Homebrew updated.")
except RuntimeError as e:
    logger.error(e)
except Exception as e:
    logger.exception("Unexpected error: %s", e)
except KeyboardInterrupt:
    logger.info("Stopping.")
