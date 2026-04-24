# Bazzite-DX Silver Goggles: Shell Excellence (Declarative Wrapper)
# This file ensures that the Silver Goggles 'bling' is sourced for Fish.
# Named zz- for consistency with the sh wrapper (zz-bazzite-dx-bling.sh).
# To disable: BLING_ENABLE=0 fish

if test "$BLING_ENABLE" != 0 && test -f "/usr/share/ublue-os/silver-goggles/bling.fish"
    source "/usr/share/ublue-os/silver-goggles/bling.fish"
end
