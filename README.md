# Satellite Demo — Ansible Automation

Ansible playbook that stands up the full [satellite-demo](https://github.com/swarred/satellite-demo) environment end-to-end from a single command.

## What it automates

1. **OCP setup** — creates the namespace, Skupper site, listener, and AccessGrant
2. **Bootc image build** — builds the satellite VM container image via podman
3. **qcow2 conversion** — runs bootc-image-builder to produce the VM disk image
4. **VM deploy** — deploys the KVM VM with cloud-init (injects live Skupper token)
5. **Ground station deploy** — in-cluster build and deploy of the ground station pod + MaaS secret

## Prerequisites

- Fedora/RHEL host with KVM, `podman`, `sshpass`, `virsh`, `virt-install`
- `oc` CLI logged in to your OpenShift cluster
- Active Red Hat subscription on the build host
- Ansible 2.14+, `kubernetes.core` collection
- The [satellite-demo](https://github.com/swarred/satellite-demo) repo cloned as a sibling directory:
  ```
  ~/satellite-demo/           ← source repo
  ~/satellite-demo-automation/ ← this repo
  ```

## Setup

**1. Install Ansible dependencies**

```bash
pip install ansible
ansible-galaxy collection install kubernetes.core
```

**2. Configure MaaS credentials**

```bash
./setup-creds.sh
```

This prompts for your LiteLLM endpoint URL and API key, encrypts them with Ansible Vault, and writes `vars/vault.yml`. The vault password is stored at `~/.satellite-demo.vaultpass` (never committed).

**3. Log in to OCP**

```bash
oc login <your-cluster-api-url> --token=<your-token>
```

## Deploy

```bash
ansible-playbook site.yml --ask-become-pass
```

`--ask-become-pass` is required for the root steps (bootc-image-builder, virt-install).

## Teardown

```bash
ansible-playbook teardown.yml --ask-become-pass
```

Deletes the OCP namespace and destroys + undefines the KVM VM.

## Configuration

All defaults are in `group_vars/all.yml`. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp_namespace` | `satellite-ground` | OCP namespace for the ground station |
| `vm_name` | `satellite-sim` | KVM domain name |
| `vm_memory` | `2048` | VM RAM in MB |
| `satellite_demo_src` | `../satellite-demo` | Path to the source repo |
| `skupper_grant_redemptions` | `5` | AccessGrant redemptions per deploy |

Override any variable on the command line:

```bash
ansible-playbook site.yml -e ocp_namespace=my-namespace --ask-become-pass
```

## Vault

MaaS credentials are stored encrypted in `vars/vault.yml` (Ansible Vault AES256). The vault password lives outside the repo at `~/.satellite-demo.vaultpass`. To update credentials, re-run `./setup-creds.sh`.
