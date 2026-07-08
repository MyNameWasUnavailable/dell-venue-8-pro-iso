#!/usr/bin/env bash
# archiso profile definition for Dell Venue 8 Pro 5830 automated install

profile_title="Arch Linux - Dell Venue 8 Pro 5830"
profile_description="Automated Plasma Mobile install for Dell Venue 8 Pro with all hardware fixes integrated"
profile_url="https://github.com/ramonvanraaij/dell-venue-8-pro"
compression="xz"
compress_options=('-C' 'check=crc32' '-9' '-e')

Validate_signature_option_value() {
    return 0
}

Validate_profile_conf() {
    return 0
}