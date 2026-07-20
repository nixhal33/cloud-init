# Cloud-Init Learning Journey — Phase 1: Beginner

**Author:** [Your Name]
**Status:** Beginner phase complete
**Next phase:** Intermediate (multi-part user-data, validation, templating, hybrid workflows)

---

## 1. Objective

The goal of this phase was to build a working, first-principles understanding of cloud-init: what it is, why it exists, how it's delivered across different environments, and how to debug it when it fails — before moving into more advanced configuration patterns.

This phase intentionally stayed within **single-instance, first-boot provisioning** using cloud-init's built-in modules and raw script injection. No multi-stage configs, no templating, no config management handoff yet — that's Phase 2.

## 2. Core Concepts Learned

### 2.1 What cloud-init is

Cloud-init is a boot-time automation tool, pre-installed on most Linux cloud images, that reads a `user-data` configuration on **first boot only** and applies it — creating users, installing packages, writing files, and running commands. It marks its own completion state in `/etc/cloud/` and `/var/lib/cloud/`, and will not re-run on subsequent boots unless that state is explicitly cleared.

### 2.2 Why it's used

It replaces the manual workflow of *boot → SSH in → run provisioning script by hand* with a fully unattended process: describe the desired state (or hand it your existing script), and the server configures itself the moment it exists. It does not replace configuration management — it is strictly a one-time bootstrapper.

### 2.3 Datasources: cloud vs. NoCloud

Two delivery mechanisms were tested:

| Datasource | Environment | Delivery Method |
|---|---|---|
| Cloud provider metadata service | AWS EC2 | User-data pasted into the console; served automatically over the instance metadata API |
| NoCloud | Local hypervisor (Proxmox/KVM/VirtualBox) | User-data/meta-data supplied manually via a small ISO labeled `cidata`, attached as a virtual CD-ROM |

Key clarification reached during this phase: NoCloud is not a VM image or a hypervisor feature — it is the name of the *delivery mechanism* used when no cloud metadata service is available. Proxmox itself has no built-in concept of "cloud" or "NoCloud"; it simply hosts the VM, and NoCloud is the method used to hand that VM its configuration manually.

## 3. Practical Work Completed

### 3.1 AWS EC2 — first successful run

- Launched a Debian/Ubuntu EC2 instance with a `#cloud-config` YAML in the **User data** field.
- Config included: package installation, a sudo user with an injected SSH key, a `write_files` entry, and a `runcmd` log entry.
- **Result:** Initial SSH connection failed.

**Error encountered:** Unable to connect via SSH after instance launch.

**Root cause:** Security Group inbound rules did not permit traffic on port 22.

**Resolution:** Updated the Security Group to allow inbound SSH from the required source. Re-attempted connection — successful.

**Verification:**
```bash
cloud-init status        # → done
cat /home/devops/welcome.txt
cat /var/log/my-cloudinit-test.log
```

All expected artifacts were present, confirming user-data executed correctly on first boot.

### 3.2 Bringing in existing provisioning scripts

Rather than rewriting existing bash automation (Docker installation, repo key setup, `docker-ce` install, group permissions, etc.) into cloud-init's native YAML modules, the existing script was preserved as-is and executed via:

```yaml
write_files:
  - path: /root/install-devops-stack.sh
    permissions: '0755'
    content: |
      <existing bash script, unmodified>

runcmd:
  - /root/install-devops-stack.sh
```

**Outcome:** Confirmed that cloud-init requires no changes to existing provisioning logic — it only needs a mechanism (`write_files` + `runcmd`) to deliver and trigger the script at boot.

### 3.3 Intentional failure exercise (debugging)

To build debugging competence, a deliberately broken `user-data` file was used, containing two seeded issues:
1. A YAML indentation inconsistency inside a `write_files: content:` block.
2. A `runcmd` step referencing a non-existent package (`docker-ce-nonexistent-package`), combined with `set -e`, causing early script termination.

**Diagnostic workflow exercised:**

| Step | Command | Purpose |
|---|---|---|
| 1 | `cloud-init status --long` | Identify which stage (init/config/final) reported an issue |
| 2 | Check for expected marker file (`/var/log/my-marker.log`) | Confirm whether `runcmd` ran to completion |
| 3 | `cat /var/log/cloud-init-output.log` | Locate actual stdout/stderr from the failing script |
| 4 | `cat /var/log/cloud-init.log` | Check for YAML parsing/module-level errors |
| 5 | `cat /var/lib/cloud/instance/user-data.txt` | Confirm the datasource delivered the intended config at all |

This established the standing rule for future debugging: **YAML/parsing issues surface in `cloud-init.log`; script logic failures surface in `cloud-init-output.log`.**

Also learned: cloud-init state can be reset and replayed on a live instance without rebuilding it, via:
```bash
sudo cloud-init clean --logs
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

## 4. Comparative Understanding

| Tool | Role | Relationship to Cloud-Init |
|---|---|---|
| Ansible / Chef / Puppet | Ongoing configuration management | Cloud-init typically does the minimal bootstrap (user, SSH key, agent install), then hands off to these for continuous management |
| Terraform | Infrastructure provisioning (the VM/network/disk itself) | Terraform creates the instance and passes cloud-init YAML in as user-data |
| Packer | Pre-bakes a fully configured image | Opposite approach to cloud-init: image is ready before boot, vs. cloud-init configuring a generic image at boot time |

## 5. Assessment

Everything completed in this phase falls under **beginner scope**:
- Single-instance provisioning
- Built-in `#cloud-config` modules (`packages`, `users`, `write_files`, `runcmd`)
- Manual script injection via `write_files`
- Basic log-based debugging
- No templating, no multi-part MIME user-data, no schema validation tooling, no orchestration with Terraform/Ansible yet

This is an appropriate and complete foundation before progressing to intermediate work.

## 6. Next Phase: Intermediate Topics (Planned)

- Writing and validating cloud-config with `cloud-init schema --config-file`
- Multi-part user-data (combining `#cloud-config` with `#!/bin/bash` scripts via MIME multi-part archives)
- Jinja templating in user-data for reusable, parameterized configs
- Proxmox NoCloud implementation hands-on (building `seed.iso`, attaching as `cidata`, using Proxmox's native `--ide2 cloudinit` drive)
- Idempotency and re-run considerations
- Handoff pattern: cloud-init bootstrap → Ansible for ongoing configuration
