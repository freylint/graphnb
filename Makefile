# Variables
DEPLOY_VARIANT ?= server
ANSIBLE_PLAYBOOK := ansible-playbook -v
ANSIBLE_INVENTORY ?= ansible/inventories/production/hosts.yml
ANSIBLE_RUNNER ?= ansible/runner.yml

.PHONY: all build build-no-cache build-nvidia build-nvidia-no-cache client client-no-cache client-nvidia client-nvidia-no-cache build-cloud build-cloud-no-cache test deploy clean check-root

# Default target
all: build

# 1. Build the server container image locally
build: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=server -e target_action=build

# 1b. Build without using cache
build-no-cache: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=server -e target_action=build-no-cache -e no_cache=true

# 1b2. Build server image (NVIDIA base image)
build-nvidia: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=server -e target_action=build -e build_variant=nvidia

# 1b3. Build server image (NVIDIA base image) without using cache
build-nvidia-no-cache: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=server -e target_action=build-no-cache -e build_variant=nvidia -e no_cache=true

# 1c. Build client image (AMD/Intel base)
client: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=client -e target_action=build

# 1c2. Build client image without using cache (AMD/Intel base)
client-no-cache: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=client -e target_action=build-no-cache -e no_cache=true

# 1d. Build client image (NVIDIA base image)
client-nvidia: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=client -e target_action=build -e build_variant=nvidia

# 1d2. Build client image without using cache (NVIDIA base image)
client-nvidia-no-cache: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=client -e target_action=build-no-cache -e build_variant=nvidia -e no_cache=true

# 1e. Build cloud image
build-cloud: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=cloud -e target_action=build

# 1e2. Build cloud image without using cache
build-cloud-no-cache: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=cloud -e target_action=build-no-cache -e no_cache=true

# 2. Deploy/Rebase the local machine to a selected image variant
# Supported: DEPLOY_VARIANT=server|server-nvidia|client|client-nvidia (default: server)
deploy: check-root
	@case "$(DEPLOY_VARIANT)" in \
		server) ROLE=server; VARIANT=base ;; \
		server-nvidia) ROLE=server; VARIANT=nvidia ;; \
		client) ROLE=client; VARIANT=base ;; \
		client-nvidia) ROLE=client; VARIANT=nvidia ;; \
		*) \
			echo "Error: Invalid DEPLOY_VARIANT='$(DEPLOY_VARIANT)'"; \
			echo "Use one of: server, server-nvidia, client, client-nvidia"; \
			exit 1 ;; \
	esac; \
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=$$ROLE -e target_action=deploy -e build_variant=$$VARIANT

# Check if the user has sudo/root privileges
check-root:
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "Error: This target must be run with sudo or as root."; \
		exit 1; \
	fi

# Clean up local podman images
clean: check-root
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_RUNNER) -e target_role=server -e target_action=clean

