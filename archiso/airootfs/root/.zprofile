# Auto-start installation on first boot
if [ ! -f /var/lib/venue-installed ]; then
    echo "Starting automated installation for Dell Venue 8 Pro 5830..."
    echo "This may take 10-15 minutes. Please do not power off the device."
    sudo systemctl start venue-install.service
else
    echo "Installation already complete."
fi