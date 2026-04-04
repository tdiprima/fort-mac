#!/usr/bin/env bash
# run_it.sh
# Runs daily system update tasks: rustup and Homebrew update/upgrade/cleanup.
# Expects: rustup and brew installed and on PATH.

main() {
    echo "Updating rustup..."
    rustup update

    echo "Updating Homebrew..."
    brew update

    echo "Upgrading Homebrew packages..."
    brew upgrade

    echo "Cleaning up Homebrew..."
    brew cleanup --prune=all

    echo "Running Homebrew doctor..."
    brew doctor
}

main "$@"
