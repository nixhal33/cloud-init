# Cloud-Init: Automated Server Provisioning

This repo documents and demonstrates the use of **cloud-init** for automating first-boot configuration of Linux servers — across public cloud providers (AWS EC2) and local virtualization (Proxmox/KVM via NoCloud).

## What is Cloud-Init?

Cloud-init is the industry-standard tool for automating the initial setup of Linux servers. On first boot, it reads a configuration file (`user-data`) and can:

- Install packages
- Create users, set up SSH keys and sudo access
- Write files to disk
- Run arbitrary shell commands/scripts (`runcmd`)
- Configure networking and hostnames

It runs **once**, on first boot, and marks its state in `/etc/cloud/` and `/var/lib/cloud/`. Subsequent boots skip user-data unless the state is reset — which is why a fresh disk/image is required for repeatable results.

## Why Use It

Instead of manually SSHing into a fresh server and running provisioning scripts by hand, cloud-init lets you hand off that exact same script to run **automatically and unattended** the moment the instance boots. It doesn't replace your existing bash automation — it's just the delivery mechanism that triggers it at boot time.

## Datasources Covered

| Datasource | Used When | How Config Is Delivered |
|---|---|---|
| **Cloud provider** (AWS, Azure, GCP) | VM runs in a public cloud | Fetched automatically from a metadata HTTP API; you paste YAML into the console's "User data" field |
| **NoCloud** | VM runs locally (Proxmox, KVM, VirtualBox) — no metadata service available | You manually provide `user-data` + `meta-data` via a small ISO (labeled `cidata`) attached as a virtual CD-ROM |

## Repo Contents

```
.
├── aws/
│   └── user-data.yaml          # cloud-config used for EC2 instance launch
├── proxmox/
│   ├── user-data.yaml          # cloud-config for NoCloud ISO
│   ├── meta-data               # instance-id / hostname
│   └── build-iso.sh            # script to generate seed.iso via genisoimage
└── scripts/
    └── install-devops-stack.sh # provisioning script (Docker, docker-compose, tree, etc.)
```

## Usage

### AWS EC2

1. Launch an instance (Debian/Ubuntu AMI — both ship with cloud-init pre-installed).
2. Under **Advanced details → User data**, paste the contents of `aws/user-data.yaml`.
3. Launch, wait ~1-2 minutes, then SSH in with the user/key defined in the config.
4. Verify: `cloud-init status`, `cat /var/log/cloud-init-output.log`.

> Make sure your **security group** allows inbound SSH (port 22) — a common first-run gotcha.

### Proxmox (NoCloud)

1. Download a fresh, never-booted cloud image (e.g. `debian-12-generic-amd64.qcow2`).
2. Build the seed ISO:
   ```bash
   mkdir seed
   cp proxmox/user-data proxmox/meta-data seed/
   genisoimage -output seed.iso -volid cidata -joliet -rock seed/
   ```
3. Attach `seed.iso` as a CD-ROM to the VM (or use Proxmox's built-in `--ide2 <storage>:cloudinit` cloud-init drive instead of a manual ISO).
4. Boot the VM on a fresh disk. Cloud-init detects the `cidata`-labeled disk and applies the config.

## Key Lesson: Fresh Disk Required

Cloud-init marks a disk as "used" after first boot. Reusing a disk with a new ISO/config will **not** reapply user-data unless you reset state:

```bash
sudo cloud-init clean --logs
sudo rm -rf /etc/cloud/ /var/lib/cloud/
```

Then reboot (or re-attach a new ISO and boot).

## Debugging Cloud-Init

| Check | Command | Tells You |
|---|---|---|
| Overall status | `cloud-init status --long` | Which stage failed (init/config/final) |
| Internal log | `sudo cat /var/log/cloud-init.log` | YAML parsing errors, datasource detection, module tracebacks |
| Script output | `sudo cat /var/log/cloud-init-output.log` | stdout/stderr of your actual `runcmd` script |
| What cloud-init received | `sudo cat /var/lib/cloud/instance/user-data.txt` | Confirms the datasource actually delivered your config |

**Re-run without rebuilding the VM** (useful for fast iteration while debugging):

```bash
sudo cloud-init clean --logs
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

### Common Pitfalls

- **Invalid YAML indentation** — especially inside `write_files: content: |` blocks (whitespace-sensitive).
- **`set -e` + a normally-failing command** (e.g. `apt remove` on a non-existent package) silently kills the rest of the script.
- **Missing/mislabeled ISO** — must be labeled `cidata` for NoCloud to detect it.
- **Race conditions** — `runcmd` running before networking is fully up.

## How Cloud-Init Compares

| Tool | Role |
|---|---|
| **Cloud-init** | One-time, first-boot bootstrap (users, packages, initial scripts) |
| **Ansible / Chef / Puppet** | Ongoing configuration management, runs repeatedly, needs the machine reachable |
| **Terraform** | Provisions the infrastructure itself (the VM, network, disks) — cloud-init configures what's inside it |
| **Packer** | Bakes a custom image ahead of time (pre-configured); cloud-init configures a generic image at boot |

In practice: Terraform creates the instance → passes cloud-init YAML as user-data → cloud-init bootstraps the box → Ansible/Puppet takes over for ongoing configuration management.

## References

- [Official cloud-init docs](https://cloudinit.readthedocs.io/)
- [Debian cloud images](https://cloud.debian.org/images/cloud/bookworm/latest/)
