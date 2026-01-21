# ~/.just/maintenance.just

# Full System Update
update:
    @echo "Running Topgrade..."
    topgrade
    
    @echo "Syncing package state with Metapac..."
    ~/.cargo/bin/metapac sync
    
    @echo "Cleaning up dnf orphans and cache..."
    sudo dnf autoremove -y
    sudo dnf clean packages
    
    @echo "Update and cleanup complete."

# Utils
check-duplicates:
    @echo "Checking for duplicate binaries..."
    @type -a curl python3 git just yadm metapac