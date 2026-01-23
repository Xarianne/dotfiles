# Justfile for Fedora 42 Snapper & Rollback Setup
# Based on guide: "How to Install Fedora 42 with Full Disk Encryption, Snapshot, and Rollback Support"

# The main workflow command
setup-snapper: show-grub install-deps config-dnf config-snapper config-updatedb install-grub-btrfs enable-timers
    @echo "Setup complete! A reboot is recommended to verify the GRUB menu."

# Section 3: Post-Installation Configuration
show-grub:
    @echo "Step 1: Unhiding GRUB menu..."
    sudo grub2-editenv - unset menu_auto_hide

# Section 5: Install necessary packages
install-deps:
    @echo "Step 2: Installing dependencies..."
    sudo dnf install -y snapper libdnf5-plugin-actions btrfs-assistant inotify-tools git make

# Section 5: Set Up Automatic Snapshot Creation with DNF
# FIX: Replaces fragile inline commands with a robust external script.
config-dnf:
    #!/usr/bin/env bash
    echo "Step 3: configuring DNF snapshot hooks (External Script Mode)..."
    
    # 1. Create the helper script
    # This script handles the pre/post logic safely using standard bash.
    cat <<'SCRIPT' | sudo tee /usr/local/bin/snapper-dnf-hook > /dev/null
    #!/bin/bash
    ACTION=$1
    PID=$2
    ID_FILE="/var/run/snapper-dnf.id"

    # Ensure we have a valid PID
    if [ -z "$PID" ]; then exit 0; fi

    if [ "$ACTION" == "pre" ]; then
        # Capture the DNF command
        CMD=$(ps -o command --no-headers -p "$PID")
        if [ -z "$CMD" ]; then CMD="System Update"; fi
        
        # Create Pre-Snapshot and save the ID
        # We use explicit paths and suppress stdout to keep DNF clean
        ID=$(/usr/bin/snapper create -t pre -c root -p -d "$CMD" -u root)
        echo "$ID" > "$ID_FILE"
        
    elif [ "$ACTION" == "post" ]; then
        # Only run if we have a recorded Pre-Snapshot ID
        if [ -f "$ID_FILE" ]; then
            ID=$(cat "$ID_FILE")
            CMD=$(ps -o command --no-headers -p "$PID")
            
            # Create Post-Snapshot
            /usr/bin/snapper create -t post -c root --pre-number "$ID" -d "$CMD" -u root
            
            # Cleanup
            rm -f "$ID_FILE"
        fi
    fi
    SCRIPT
    
    # Make the script executable
    sudo chmod 755 /usr/local/bin/snapper-dnf-hook

    # 2. Configure DNF to call our script
    # We pass the ${pid} from the plugin to our script as argument $2
    cat <<'EOF' | sudo tee /etc/dnf/libdnf5-plugins/actions.d/snapper.actions > /dev/null
    pre_transaction::::/usr/local/bin/snapper-dnf-hook pre ${pid}
    post_transaction::::/usr/local/bin/snapper-dnf-hook post ${pid}
    EOF
    
    # Clean up any leftover debug files
    sudo rm -f /etc/dnf/libdnf5-plugins/actions.d/debug.actions
    
    echo "Robust snapshot hook installed."

# Section 5: Create Snapper Configurations
config-snapper:
    @echo "Step 4: Configuring Snapper for root and home..."
    # Create configs if they don't exist
    sudo snapper -c root create-config / || echo "Root config likely exists, skipping creation."
    sudo snapper -c home create-config /home || echo "Home config likely exists, skipping creation."
    
    # Restore SELinux contexts (ignore read-only errors)
    sudo restorecon -RFv /.snapshots || true
    sudo restorecon -RFv /home/.snapshots || true
    
    # Allow the current user to manage snapshots and sync ACLs
    sudo snapper -c root set-config ALLOW_USERS=$(whoami) SYNC_ACL=yes
    sudo snapper -c home set-config ALLOW_USERS=$(whoami) SYNC_ACL=yes

# Section 5: Configure updatedb
config-updatedb:
    @echo "Step 5: Excluding snapshots from updatedb..."
    if ! grep -q 'PRUNENAMES = ".snapshots"' /etc/updatedb.conf; then \
        echo 'PRUNENAMES = ".snapshots"' | sudo tee -a /etc/updatedb.conf; \
    fi

# Section 5: Install and Configure grub-btrfs
install-grub-btrfs:
    @echo "Step 6: Installing grub-btrfs..."
    rm -rf /tmp/grub-btrfs
    git clone https://github.com/Antynea/grub-btrfs /tmp/grub-btrfs
    
    # Configure grub-btrfs for Fedora paths (/boot/grub2)
    cd /tmp/grub-btrfs && sed -i.bkp \
        -e '/^#GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS/s/^#//' \
        -e 's/#GRUB_BTRFS_MKCONFIG=.*/GRUB_BTRFS_MKCONFIG=\/usr\/sbin\/grub2-mkconfig/' \
        -e 's/#GRUB_BTRFS_SCRIPT_CHECK=.*/GRUB_BTRFS_SCRIPT_CHECK=no/' \
        -e 's/#GRUB_BTRFS_GRUB_DIRNAME=.*/GRUB_BTRFS_GRUB_DIRNAME="\/boot\/grub2"/' \
        config

    # Install the package
    cd /tmp/grub-btrfs && sudo make install

    # Regenerate the GRUB configuration file
    @echo "Regenerating GRUB config..."
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    
    # Cleanup
    rm -rf /tmp/grub-btrfs

# Section 6: Enable Systemd Timers & Services
enable-timers:
    @echo "Step 7: Enabling systemd timers and services..."
    sudo systemctl enable --now snapper-timeline.timer
    sudo systemctl enable --now snapper-cleanup.timer
    sudo systemctl enable --now grub-btrfsd