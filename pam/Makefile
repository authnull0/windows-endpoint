# Makefile for installing and uninstalling the PAM module

PAM_MODULE=pam_authnull.so
PAM_PATH=/lib64/security/$(PAM_MODULE)
SSHD_CONFIG=/etc/ssh/sshd_config
PAM_FILE=/etc/pam.d/sshd
# Detect OS dynamically
OS_INFO := $(shell cat /etc/os-release 2>/dev/null)

# Determine package manager and PAM path
ifeq ($(shell echo "$(OS_INFO)" | grep -iE 'centos|rhel|rocky|alma'),)
  ifeq ($(shell echo "$(OS_INFO)" | grep -i oracle),)
    ifeq ($(shell echo "$(OS_INFO)" | grep -iE 'ubuntu|debian'),)
      $(error Unknown OS detected. Please update Makefile.)
    else
      PAM_PATH := /lib/x86_64-linux-gnu/security/$(PAM_MODULE)
      PKG_MANAGER := apt-get
    endif
  else
      PAM_PATH := /lib64/security/$(PAM_MODULE)
      SSHD_CONFIG := /etc/ssh/sshd_config
      PKG_MANAGER := yum
  endif
else
  PAM_PATH := /lib64/security/$(PAM_MODULE)
  SSHD_CONFIG := /etc/ssh/sshd_config
  PKG_MANAGER := yum
endif

# Print detected configuration
$(info Detected Package Manager: $(PKG_MANAGER))
$(info Detected PAM Path: $(PAM_PATH))
$(info Detected SSHD Config: $(SSHD_CONFIG))


# Installation: Configure and restart services
install: copy restart_services
	@echo "Installation completed successfully."


uninstall: remove_pam restore_sshd restart_services
	@echo "Uninstallation completed successfully."

copy:
	@echo "Copying $(PAM_MODULE) to $(PAM_PATH)..."
	@sudo cp $(PAM_MODULE) $(PAM_PATH)
	@if [ $$? -ne 0 ]; then echo "Failed to copy $(PAM_MODULE)." && exit 1; fi

restart_services:
	@echo "Restarting SSH services..."
	@sudo systemctl restart sshd 2>/dev/null || true
	@sudo systemctl restart ssh 2>/dev/null || true

remove_pam:
	@echo "Removing PAM configuration from $(PAM_FILE)..."
	@sudo sed -i "/pam_authnull.so/d" $(PAM_FILE)
	@sudo sed -i 's/^#@include common-auth/@include common-auth/' $(PAM_FILE)
	@echo "Removing PAM module..."
	@sudo rm -f $(PAM_PATH)

restore_sshd:
	@echo "Restoring $(SSHD_CONFIG)..."
	@sudo sed -i 's/^ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' $(SSHD_CONFIG)
	@sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' $(SSHD_CONFIG)
	@sudo sed -i '/AuthenticationMethods keyboard-interactive/d' $(SSHD_CONFIG)

.PHONY: install uninstall download copy configure restart_services remove_pam restore_sshd
