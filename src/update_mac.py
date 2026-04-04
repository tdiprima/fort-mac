# Updates Rust and Homebrew, upgrades installed packages, cleans up, and
# checks system health, handling exceptions and keyboard interrupts.
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
    logger.info("📦 Updating Cargo...")
    subprocess.run(["rustup", "update"])
    logger.info("✅ Cargo updated.")

    conga = get_conga_from_keychain()

    logger.info("🍺 Updating Homebrew...")
    subprocess.run(["brew", "update"])
    subprocess.run(["brew", "upgrade"], input=conga, text=True)
    subprocess.run(["brew", "cleanup", "-s"])
    subprocess.run(["brew", "doctor"])
    logger.info("✅ Homebrew updated.")
except RuntimeError as e:
    logger.error(e)
except Exception as e:
    logger.exception("Unexpected error: %s", e)
except KeyboardInterrupt:
    logger.info("Stopping.")
