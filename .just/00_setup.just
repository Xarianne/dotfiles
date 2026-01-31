# =============================================================================
# VARIABLES
# =============================================================================
fedora_ver := shell("rpm -E %fedora")
current_user := shell("whoami")

# =============================================================================
# FULL SYSTEM SETUP
# =============================================================================

# Added setup-cachyos to the chain
setup-system: _init setup-shell setup-repos _setup-cachyos _install-cargo-tools _sync
	@echo "Provisioning Complete. Please reboot your machine."

# =============================================================================
# SETUP STEPS
# =============================================================================

_init:
	@echo "--------------------------------------------------------"
	@echo "REMINDER: Ensure yadm is installed before proceeding."
	@echo "--------------------------------------------------------"
	@echo "Preparing configurations..."
	@yadm clone https://github.com/Xarianne/dotfiles.git || echo "Repo already exists."
	@yadm reset --hard HEAD
	@if ! command -v ~/.cargo/bin/metapac >/dev/null; then \
		sudo dnf install cargo gcc openssl-devel -y; \
		cargo install metapac || true; \
	fi
	@mkdir -p ~/.config/metapac/groups
	@if [ ! -f ~/.config/metapac/groups/base.toml ]; then \
		~/.cargo/bin/metapac unmanaged > ~/.config/metapac/groups/base.toml; \
	fi

setup-shell:
	@echo "Checking User Shell..."
	@if [ "$$SHELL" != "/usr/bin/fish" ]; then \
		sudo usermod --shell /usr/bin/fish {{current_user}}; \
	else \
		echo "Shell is already Fish."; \
	fi

setup-repos:
	@echo "Configuring Repositories..."
	@if ! rpm -q terra-release >/dev/null; then \
		sudo dnf install -y --refresh --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra{{fedora_ver}}" terra-release terra-release-mesa terra-release-multimedia; \
	fi
	@sudo dnf upgrade -y --allowerasing mesa* libgbm
	@if ! rpm -q gstreamer1-plugins-ugly >/dev/null; then \
		sudo dnf install -y --allowerasing ffmpeg gstreamer1-plugins-bad gstreamer1-plugins-bad-free-extras gstreamer1-plugins-ugly; \
	fi
	@if [ ! -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos-addons.repo ]; then \
		sudo dnf copr enable -y bieszczaders/kernel-cachyos-addons; \
	fi
	@if [ ! -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:xariann:tools.repo ]; then \
		sudo dnf copr enable -y xariann/tools; \
	fi
	@flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
	@flatpak update --appstream
	@if flatpak remote-list | grep -q "fedora"; then flatpak remote-delete fedora --force; fi

# Handles the CachyOS swap
_setup-cachyos:
	@echo "Applying CachyOS System Tweaks..."
	@if ! rpm -q cachyos-settings >/dev/null; then \
		sudo dnf swap -y zram-generator-defaults cachyos-settings; \
		sudo dracut -f; \
	else \
		echo "CachyOS settings already applied."; \
	fi

_install-cargo-tools:
	@echo "Checking Cargo Tools..."
	@if ! [ -f ~/.cargo/bin/cargo-install-update ]; then cargo install cargo-update; fi
	@if ! [ -f ~/.cargo/bin/topgrade ]; then cargo install topgrade; fi

_sync:
	@echo "Syncing Packages..."
	@~/.cargo/bin/metapac sync
