# Set up system Homebrew PATH for all users.
# /home/linuxbrew/.linuxbrew is a system-wide install — belongs in conf.d.
# Mirrors the BlueBuild brew module reference (non-root, Homebrew present).

if test -d /home/linuxbrew/.linuxbrew && test (id -u) != 0
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end
