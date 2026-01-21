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
    
    @echo "Cleaning up unused Flatpak runtimes..."
    flatpak uninstall --unused -y

    @echo "Checking for config conflicts..."
    @sudo rpmconf -a || echo "No conflicts found."
    
    @echo "Update and cleanup complete."

# Utils
check-duplicates:
    @echo "Checking for duplicate binaries..."
    @type -a curl python3 git just yadm metapac

# Boot into this device's BIOS/UEFI screen
bios:
    #!/usr/bin/bash
    if [ ! -d /sys/firmware/efi ]; then
      echo "Rebooting to legacy BIOS from OS is not supported."
      exit 1
    fi

    if gum confirm "Reboot into BIOS?" ; then
      systemctl reboot --firmware-setup
    fi

# Show BIOS info
bios-info:
    #!/usr/bin/bash
    sudo bash <<'EOF'
    echo "Manufacturer: $(dmidecode -s baseboard-manufacturer)"
    echo "Product Name: $(dmidecode -s baseboard-product-name)"
    echo "Version: $(dmidecode -s bios-version)"
    echo "Release Date: $(dmidecode -s bios-release-date)"
    EOF

# Show all messages from this boot
logs-this-boot:
    sudo journalctl --no-hostname -b 0

# Show all messages from last boot
logs-last-boot:
    sudo journalctl --no-hostname -b -1

# Check for local overrides
check-local-overrides:
    #!/usr/bin/bash
    RESET="\x1b[0m"
    if [ "${NO_COLOR}" == 1 ]; then
        BLUE_COLOR=""
        GREEN_COLOR=""
        YELLOW_COLOR=""
    else
        BLUE_COLOR="${BLUE_COLOR:-\x1b[38;5;117m}"
        GREEN_COLOR="${GREEN_COLOR:-\x1b[38;5;85m}"
        YELLOW_COLOR="${YELLOW_COLOR:-\x1b[93m}"
    fi

    diff -qr \
      --suppress-common-lines \
      --color="always" \
      --exclude "passwd*" \
      --exclude "group*" \
      --exclude="subgid*" \
      --exclude="subuid*" \
      --exclude="machine-id" \
      --exclude="adjtime" \
      --exclude="fstab" \
      --exclude="system-connections" \
      --exclude="shadow*" \
      --exclude="gshadow*" \
      --exclude="ssh_host*" \
      --exclude="cmdline" \
      --exclude="crypttab" \
      --exclude="hostname" \
      --exclude="localtime" \
      --exclude="locale*" \
      --exclude="*lock" \
      --exclude=".updated" \
      --exclude="*LOCK" \
      --exclude="vconsole*" \
      --exclude="00-keyboard.conf" \
      --exclude="grub" \
      --exclude="system.control*" \
      --exclude="cdi" \
      --exclude="default.target" \
      /usr/etc /etc 2>/dev/null | sed \
          -e '/Binary\ files\ /d ; /Common subdirectories/d' \
          -e "/Files/ s/^/${BLUE_COLOR}&/g" \
          -e "/Files/ s/\$/&${RESET}/g" \
          -e "/Only in/ s/^/${GREEN_COLOR}&/g" \
          -e "/Only in/ s/\$/&${RESET}/g" \
          -e "s/\:.*/${RESET}${YELLOW_COLOR}&${RESET}/g"

# Gather device info to a pastebin
device-info:
    #!/usr/bin/bash
    if ! gum confirm "Submit information to the CentOS pastebin?" ; then
        exit 0
    fi

    cat &> /tmp/deviceinfo-out <<EOF
    --#--# sudo bootc status --verbose:
    $(sudo bootc status --verbose)
    --#--# fpaste --sysinfo --printonly:
    $(fpaste --sysinfo --printonly)
    --#--# flatpak list --columns=application,version,options:
    $(flatpak list --columns=application,version,options)
    EOF

    cat /tmp/deviceinfo-out | fpaste

# Measure Idle Power Draw
check-idle-power-draw:
    #!/usr/bin/bash
    if ! command -v powerstat ; then
        echo "Powerstat is not available"
        exit 1
    fi
    sudo powerstat -a -r

# Run a one minute system benchmark
[group('System')]
benchmark:
    #!/usr/bin/env bash
    if ! command -v "stress-ng" ; then
        if gum confirm "Stress does not seem to be on your path, do you wish to install it?" ; then
            set -eu
            brew install stress-ng
            brew link stress-ng
            set +eu
        else
            exit 0
        fi
    fi

    echo "Running a 1 minute benchmark ..."
    trap popd EXIT
    pushd "$(mktemp -d)"
    stress-ng --matrix 0 -t 1m --times

# TPM2 auto-unlock toggle
[group('System')]
toggle-tpm2:
    @/usr/bin/luks-tpm2-autounlock

# Audit system state and interactively reconcile package drift
verify-state:
    #!/usr/bin/env bash
    set -e
    
    # Visuals
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
    
    echo -e "${YELLOW}Starting System State Verification...${NC}\n"

    # 1. CHECK CRITICAL SERVICES (Snapper & Grub-Btrfs)
    # -------------------------------------------------
    ERRORS=0
    echo -e "Checking System Timers & Services..."
    # These services ensure snapshots happen and appear in GRUB
    SERVICES=("snapper-timeline.timer" "snapper-cleanup.timer" "grub-btrfsd.service")
    
    for SERVICE in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$SERVICE"; then
            echo -e "  [${GREEN}OK${NC}] $SERVICE is active"
        else
            echo -e "  [${RED}FAIL${NC}] $SERVICE is NOT active"
            ERRORS=$((ERRORS+1))
        fi
    done

    # 2. CHECK FLATPAK REMOTES (Ensure purity)
    # ----------------------------------------
    echo -e "\nChecking Flatpak Remotes..."
    # We want Flathub, but we explicitly removed 'fedora' in setup-system
    if flatpak remote-list | grep -q "fedora" && ! flatpak remote-list | grep -q "flathub"; then
         echo -e "  [${RED}FAIL${NC}] 'fedora' remote detected or 'flathub' missing."
         ERRORS=$((ERRORS+1))
    elif flatpak remote-list | grep -q "fedora"; then
         echo -e "  [${YELLOW}WARN${NC}] 'fedora' remote is present (preferred: flathub only)."
    else
         echo -e "  [${GREEN}OK${NC}] Flatpak remotes look clean."
    fi

    # 3. CHECK USER SHELL
    # -------------------
    echo -e "\nChecking User Shell..."
    EXPECTED_SHELL="/usr/bin/fish"
    if [ "$SHELL" != "$EXPECTED_SHELL" ]; then
        echo -e "  [${YELLOW}WARN${NC}] Current shell is $SHELL (Expected: $EXPECTED_SHELL)"
        ERRORS=$((ERRORS+1))
    else
        echo -e "  [${GREEN}OK${NC}] Shell is Fish."
    fi

    # 4. CHECK REPOS (Terra & COPRs)
    # ------------------------------
    echo -e "\nChecking RPM Repositories..."
    if rpm -q terra-release >/dev/null; then
        echo -e "  [${GREEN}OK${NC}] Terra repository installed."
    else
        echo -e "  [${RED}FAIL${NC}] Terra repository missing."
        ERRORS=$((ERRORS+1))
    fi

    # 5. DRIFT MANAGEMENT (Metapac & Gum)
    # ---------------------------------------------------------
    echo -e "\nChecking for Package Drift..."
    
    # Capture unmanaged packages
    UNMANAGED=$(~/.cargo/bin/metapac unmanaged)

    if [ -z "$UNMANAGED" ]; then
        echo -e "  [${GREEN}OK${NC}] No unmanaged packages found."
    else
        echo -e "  [${YELLOW}DRIFT DETECTED${NC}] The following packages are installed but not in Metapac:"
        echo -e "${RED}${UNMANAGED}${NC}"
        echo ""
        
        # Ask user for action using Gum
        echo "Select an action for these packages:"
        ACTION=$(gum choose "Save to unsorted.toml" "Uninstall (Clean)" "Ignore for now")

        case $ACTION in
            "Save to unsorted.toml")
                echo "Blessing packages into configuration..."
                mkdir -p ~/.config/metapac/groups
                ~/.cargo/bin/metapac unmanaged > ~/.config/metapac/groups/unsorted.toml
                echo -e "${GREEN}Saved to ~/.config/metapac/groups/unsorted.toml${NC}"
                echo "Review this file later to organize packages into proper groups."
                ;;
                
            "Uninstall (Clean)")
                echo "Purging unmanaged packages..."
                # Runs sync, which removes anything not in the TOML files
                ~/.cargo/bin/metapac sync
                echo -e "${GREEN}System cleaned.${NC}"
                ;;
                
            "Ignore for now")
                echo -e "${YELLOW}Drift ignored. These packages remain installed but unmanaged.${NC}"
                ;;
        esac
    fi

    echo -e "\n----------------------------------------"
    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN} System state verification complete.${NC}"
    else
        echo -e "${RED} Found $ERRORS potential configuration issues (excluding drift).${NC}"
    fi