# Updates Rust and Homebrew, upgrades installed packages, cleans up, and 
# checks system health, handling exceptions and keyboard interrupts.
# nosec B404, B603, B607
import os
import subprocess
from dotenv import load_dotenv

load_dotenv()

try:
    print("📦 Updating Cargo...")
    subprocess.run(["rustup", "update"])
    print("✅ Cargo updated.")
    conga = os.getenv("CONGA")
    print("🍺 Updating Homebrew...")
    subprocess.run(["brew", "update"])
    subprocess.run(["brew", "upgrade"], input=conga, text=True)
    subprocess.run(["brew", "cleanup", "-s"])
    subprocess.run(["brew", "doctor"])
    print("✅ Homebrew updated.")
except Exception as e:
    print(e)
except KeyboardInterrupt:
    print("\n🎬 Stopping.")
