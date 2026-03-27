# Automates the daily execution of system updates for Rust and Homebrew at 3:00 PM,
# logging the process and handling exceptions.
# nosec B404, B603, B607
import subprocess
import time

import schedule
from loguru import logger

from keychain import get_conga_from_keychain

logger.add("scheduler.log", rotation="5 MB", retention=3, level="DEBUG")


def my_daily_task():
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


try:
    schedule.every().day.at("15:00").do(my_daily_task)

    logger.info("Scheduler started. Waiting for 3:00 PM each day...")
    while True:
        schedule.run_pending()
        time.sleep(1)
except Exception as e:
    logger.error(e)
except KeyboardInterrupt:
    logger.info("\n🎬 Stopping.")
