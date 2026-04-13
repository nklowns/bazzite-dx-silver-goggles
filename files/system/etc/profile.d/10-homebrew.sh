#!/usr/bin/env sh
# Set up system Homebrew PATH for all users.
# /home/linuxbrew/.linuxbrew is a system-wide install — belongs in profile.d.
# No interactive guard: PATH must be available for scripts and login shells alike.

if [ -d /home/linuxbrew/.linuxbrew ] && [ "$(/usr/bin/id -u)" != "0" ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
