#!/usr/bin/env bash
# Set up system Homebrew PATH for all users.
# /home/linuxbrew/.linuxbrew is a system-wide install — belongs in profile.d.
# Guards mirror the BlueBuild brew module reference implementation.

if [[ -d /home/linuxbrew/.linuxbrew && $- == *i* && "$(/usr/bin/id -u)" != "0" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
