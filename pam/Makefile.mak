# Makefile for installing and uninstalling the PAM module

PAM_MODULE=pam_authnull.so
PAM_PATH=/lib/x86_64-linux-gnu/security/$(PAM_MODULE)
SSHD_CONFIG=/etc/ssh/sshd_config
PAM_FILE=/etc/pam.d/sshd
ENV_FILE=/usr/local/sbin/app.env

install: download copy configure_sshd configure_pam restart_services
	@echo "Installation completed successfully."

uninstall: remove_pam restore_sshd restart_services
	@echo "Uninstallation completed successfully."

download:
	@echo "Downloading the PAM module..."
	curl -L -o $(PAM_MODULE) https://github.com/authnull0/windows-endpoint/raw/refs/heads/main/pam/$(PAM_MODULE)
	@if [ $$? -ne 0 ]; then echo "Failed to download the .so file." && exit 1; fi

copy:
	@echo "Copying $(PAM_MODULE) to $(PAM_PATH)..."
	sudo cp $(PAM_MODULE) $(PAM_PATH)
	@if [ $$? -ne 0 ]; then echo "Failed to copy $(PAM_MODULE)." && exit 1; fi

configure_sshd:
	@echo "Configuring $(SSHD_CONFIG)..."
	sudo sed -i 's/^KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' $(SSHD_CONFIG)
	sudo sed -i 's/^#\?PasswordAuthentication no/PasswordAuthentication yes/' $(SSHD_CONFIG)
	@if ! grep -q "AuthenticationMethods keyboard-interactive" $(SSHD_CONFIG); then \
		echo "AuthenticationMethods keyboard-interactive" | sudo tee -a $(SSHD_CONFIG); \
	fi

configure_pam:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "Error: $(ENV_FILE) not found!"; exit 1; \
	fi
	@echo "Configuring $(PAM_FILE)..."
	@ORG_ID=$$(grep "^ORG_ID=" "$(ENV_FILE)" | cut -d '=' -f2); \
	TENANT_ID=$$(grep "^TENANT_ID=" "$(ENV_FILE)" | cut -d '=' -f2); \
	AUTH_LINE="auth sufficient $(PAM_PATH) tenant_id=$$TENANT_ID org_id=$$ORG_ID"; \
	if ! grep -Fxq "$$AUTH_LINE" "$(PAM_FILE)"; then \
		sudo sed -i "1s|^|$$AUTH_LINE\n|" "$(PAM_FILE)"; \
	fi
	sudo sed -i 's/^@include common-auth/#&/' $(PAM_FILE)

restart_services:
	@echo "Restarting SSH services..."
	sudo systemctl restart sshd && sudo systemctl restart ssh

remove_pam:
	@echo "Removing PAM configuration from $(PAM_FILE)..."
	sudo sed -i "/pam_authnull.so/d" $(PAM_FILE)
	sudo sed -i 's/^#@include common-auth/@include common-auth/' $(PAM_FILE)
	@echo "Removing PAM module..."
	sudo rm -f $(PAM_PATH)

restore_sshd:
	@echo "Restoring $(SSHD_CONFIG)..."
	sudo sed -i 's/^KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/' $(SSHD_CONFIG)
	sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' $(SSHD_CONFIG)
	sudo sed -i '/AuthenticationMethods keyboard-interactive/d' $(SSHD_CONFIG)

.PHONY: install uninstall download copy configure_sshd configure_pam restart_services remove_pam restore_sshd
