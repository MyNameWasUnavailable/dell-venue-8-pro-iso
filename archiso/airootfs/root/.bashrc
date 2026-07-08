# Dell Venue 8 Pro 5830 - Automated Installation Environment

alias ls='ls --color=auto'
alias grep='grep --colour=auto'

echo "========================================"
echo "Arch Linux Automated Installation (ISO)"
echo "Dell Venue 8 Pro 5830"
echo "========================================"
echo ""
echo "This is a fully automated install environment."
echo "Installation will begin automatically on first boot."
echo ""
echo "To manually trigger installation:"
echo "  sudo systemctl start venue-install.service"
echo ""
echo "Troubleshooting:"
echo "  - Check journal: journalctl -xe"
echo "  - List devices: lsblk"
echo "  - Manual install: sudo /root/install-venue.sh"
echo ""
echo "Attribution:"
echo "  Hardware fixes: github.com/ramonvanraaij/dell-venue-8-pro"
echo ""