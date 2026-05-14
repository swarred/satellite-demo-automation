# Satellite Demo — Ansible Automation

Ansible playbooks that stand up and operate the full [satellite-demo](https://github.com/swarred/satellite-demo) environment from a single command.

## What it automates

**`site.yml` — full environment standup:**

1. **Preflight** — verifies host dependencies, installs Ollama if absent, pulls llama3.2:1b if not cached
2. **RHSI operator** — installs the Red Hat Service Interconnect operator cluster-wide (`stable-2` channel) if not already present; waits for the CSV to reach Succeeded
3. **Skupper setup** — creates the OCP namespace, Skupper site and listener, and AccessGrant; extracts the token for VM injection
4. **Ground station deploy** — in-cluster binary build and deployment of the ground station pod; captures the route URL
5. **Image build** — builds two satellite bootc images: `offline` first (Ollama + llama3.2:1b baked in), then `online` (EDA DDIL monitor, compiled with the live ground station route URL); pushes both to a local registry at `192.168.122.1:5000`
6. **qcow2 conversion** — runs `bootc-image-builder` to produce the VM disk image from the online image
7. **VM deploy** — provisions the KVM VM with cloud-init, injecting the live Skupper AccessGrant token

**`demo-ddil.yml` — run the DDIL demonstration:**

Automates the DDIL sequence with narrated Ansible task names: breaks the Skupper link, poisons the ground station hostname, waits for EDA to detect and trigger the bootc switch, waits through the reboot cycle, confirms the offline image is booted, and streams the first autonomous LLM classifications.

**`demo-restore.yml` — restore connectivity:**

Removes the hostname poison, waits for EDA to detect reconnect and trigger the bootc switch back to the online image, waits through the reboot cycle, confirms online image and Skupper link re-establishment, and reports how many alerts were classified during DDIL.

**`teardown.yml` — full environment teardown:**

Deletes the OCP namespace, removes the RHSI Subscription and CSV, deletes the `service-interconnect` namespace, destroys and undefines the KVM VM, stops the local image registry, and closes the firewall port.

---

## Prerequisites

### OpenShift cluster

Provision an **"AWS with OpenShift Open Environment"** cluster from the [Red Hat Demo Platform catalog](https://catalog.demo.redhat.com/catalog/babylon-catalog-prod?item=babylon-catalog-prod/sandboxes-gpte.sandbox-ocp.prod&utm_source=webapp&utm_medium=share-link).

Requirements:
- OpenShift **4.19 or later** (required for Red Hat Edge Manager)
- Cluster-admin credentials (`oc` logged in before running the playbook)
- Active **Red Hat Edge Manager subscription** (required for the flightctl Helm chart)

> **Worker nodes — provision before ordering:** When configuring the cluster order on the catalog form, set the worker node count to **2** (the default is 0). Red Hat Edge Manager requires approximately 2 extra vCPU that a single control-plane-only cluster cannot provide, and having 2 workers ensures capacity for both Edge Manager and the ground station workloads. Adding workers at order time avoids a ~5-minute wait during `site.yml`.
>
> If you already have a cluster with fewer than 2 worker nodes, the `edge_manager` role will detect this and scale the worker MachineSet up automatically before proceeding.

### Build host

Fedora or RHEL host with an active Red Hat subscription (needed for `registry.redhat.io` base images during the satellite image build).

#### Install host dependencies

Run this before your first `site.yml` execution. The preflight role will catch anything missing, but installing ahead of time avoids a mid-run failure.

```bash
# Core packages — KVM, podman, sshpass, firewalld
sudo dnf install -y \
  qemu-kvm libvirt virt-install \
  podman \
  sshpass \
  firewalld

# Helm (required for Edge Manager install)
# https://helm.sh/docs/intro/install/
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# OpenShift CLI (oc) — download from your cluster's console or:
# https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
```

#### Enable required services

```bash
sudo systemctl enable --now libvirtd firewalld
```

#### Verify everything is in place

```bash
for bin in podman oc virsh virt-install sshpass helm; do
  command -v $bin &>/dev/null && echo "OK  $bin" || echo "MISSING  $bin"
done
systemctl is-active libvirtd firewalld
df -h /var/lib/libvirt/images /var/lib/containers   # need 20 GB free each
```

#### Ansible

```bash
pip install ansible
```

> `bootc-image-builder` is not a host binary — it runs as a container pulled automatically during the `bootc_convert` step. No manual install needed.

#### Source repos

Clone both repos as siblings:

```
~/satellite-demo/            ← source repo
~/satellite-demo-automation/ ← this repo
```

---

## Setup

### 1. Log in to OCP

```bash
oc login <your-cluster-api-url> --token=<your-token>
```

### 2. Configure MaaS credentials (optional)

The demo works without MaaS — classification falls back to a confidence-tier stub. If you have a LiteLLM-compatible endpoint:

```bash
./setup-creds.sh
```

This prompts for your endpoint URL and API key, encrypts them with Ansible Vault (AES256), and writes `vars/vault.yml`. The vault password is stored at `~/.satellite-demo.vaultpass` and is never committed.

If you skip this step, `vars/vault.yml` must still exist (the playbook references it). Create an empty one:

```bash
echo '{}' > vars/vault.yml
```

---

## Deploy

```bash
ansible-playbook site.yml --ask-become-pass
```

`--ask-become-pass` is required for the root steps (bootc-image-builder, virt-install, firewall).

**First-run duration:** ~40–60 minutes (Ollama model download + offline image build + qcow2 conversion dominate). Subsequent runs reuse cached image layers and are significantly faster if the images haven't changed.

> **Firewall note:** The playbook opens port `5000/tcp` in the host's `libvirt` firewall zone so the satellite VM can pull bootc images from the build host registry during DDIL mode switching. This zone is scoped to the KVM bridge (`virbr0`) and does not expose the port on external interfaces. `teardown.yml` closes it automatically.

---

## Running the demo

With the environment deployed, the demo uses two additional playbooks. See [DEMO.md](https://github.com/swarred/satellite-demo/blob/master/DEMO.md) in the source repo for the complete guide.

```bash
# Phase 2: simulate DDIL
ansible-playbook demo-ddil.yml --ask-become-pass

# Phase 3: restore connectivity
ansible-playbook demo-restore.yml --ask-become-pass
```

---

## Teardown

```bash
ansible-playbook teardown.yml --ask-become-pass
```

This removes everything: OCP namespace and resources, RHSI operator, KVM VM, local registry, and firewall port. Run `site.yml` again to redeploy from scratch.

---

## Configuration

All defaults are in `group_vars/all.yml`. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_namespace` | `satellite-ground` | OCP namespace for the ground station |
| `vm_name` | `satellite-sim` | KVM domain name |
| `vm_memory` | `5120` | VM RAM in MB (5 GB required for Ollama inference in offline mode) |
| `vm_vcpus` | `2` | VM vCPU count |
| `satellite_demo_src` | `../satellite-demo` | Path to the satellite-demo source repo |
| `local_registry_port` | `5000` | Local registry port (reachable from VM via KVM bridge) |
| `ollama_model` | `llama3.2:1b` | Ollama model baked into the offline bootc image |
| `ollama_models_dir` | `/usr/share/ollama/.ollama/models` | Ollama model storage on the build host |
| `skupper_grant_redemptions` | `5` | AccessGrant redemptions per deploy |
| `skupper_grant_expiration` | `168h` | AccessGrant TTL |
| `flightctl_namespace` | `flightctl` | OCP namespace for the Edge Manager install |
| `flightctl_chart_version` | `1.0.2` | flightctl Helm chart version |
| `flightctl_admin_user` | `oc whoami` (auto-detected) | OCP username granted flightctl org-admin access; defaults to whoever is logged in |

Override any variable on the command line:

```bash
ansible-playbook site.yml -e ocp_namespace=my-namespace --ask-become-pass
```

---

## Roles

| Role | Purpose |
|------|---------|
| `preflight` | Host dependency check; installs Ollama and pulls llama3.2:1b if needed |
| `rhsi_operator` | Installs RHSI operator cluster-wide; idempotent (skips if already present) |
| `edge_manager` | Installs Red Hat Edge Manager (flightctl 1.0.2) on OCP; scales worker MachineSet if needed; creates org label and admin RBAC binding |
| `skupper_grant` | Creates OCP namespace, Skupper site/listener/AccessGrant, extracts token |
| `ocp_deploy` | In-cluster binary build of ground station; captures route URL |
| `image_build` | Builds offline then online bootc images; starts local registry |
| `bootc_convert` | Converts online image to qcow2 via bootc-image-builder |
| `vm_deploy` | Provisions KVM VM with cloud-init and Skupper token |
| `teardown` | Removes all demo resources (namespace, RHSI operator, VM, registry) |

---

## Vault

MaaS credentials are stored encrypted in `vars/vault.yml` (Ansible Vault AES256). The vault password lives outside the repo at `~/.satellite-demo.vaultpass`. To update credentials, re-run `./setup-creds.sh`.
