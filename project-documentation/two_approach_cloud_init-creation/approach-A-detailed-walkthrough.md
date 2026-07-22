# Approach A: Fresh-Install-Every-Time Cloud-Init Workflow (Proxmox)

This document walks through Approach A step by step, explaining **every single
line** of every command — what it does, why it's needed, and what would break
if you skipped it.

Approach A = start from a bare cloud image, and let cloud-init install the
full DevOps stack (Docker, Kubernetes, Helm, git, etc.) **fresh, on every boot**
of every clone.

Run all of this from the **Proxmox host shell** (Datacenter → pve → Shell),
NOT from inside any VM.

---

## PART 1 — Download the base cloud image

```bash
cd /var/lib/vz/template/iso
```
- `cd` — change directory
- `/var/lib/vz/template/iso` — this is Proxmox's default local storage path for
  ISO/image files. Anything downloaded here becomes visible to Proxmox as an
  importable image. If you skip this and download somewhere else, `qm importdisk`
  later won't find the file unless you give it a full path.

```bash
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```
- `wget` — downloads a file from a URL
- The URL points to **Ubuntu 22.04's official cloud image** — not a regular
  installer ISO. This distinction matters: a normal Ubuntu Server ISO expects
  an interactive install (choose language, partition disks, etc.) and does
  NOT have cloud-init pre-installed/configured to look for a datasource.
  This `.img` file, by contrast, is a pre-built disk image with cloud-init
  already installed and set to check for a NoCloud/other datasource on first boot.
- Result: a file named `jammy-server-cloudimg-amd64.img` now sits in
  `/var/lib/vz/template/iso/`.

---

## PART 2 — Create the VM shell (no OS disk yet)

```bash
qm create 9000 --name approach-a-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
```
- `qm create` — Proxmox's command to define a new virtual machine
- `9000` — the VM ID. Must be unique across your Proxmox node. Using round
  numbers like 9000 is a common convention for templates (as opposed to 100s
  for regular VMs/containers).
- `--name approach-a-template` — a human-readable label shown in the Proxmox UI
- `--memory 2048` — allocates 2048 MB (2 GB) of RAM to this VM
- `--cores 2` — allocates 2 CPU cores
- `--net0 virtio,bridge=vmbr0` — creates a network interface using the
  `virtio` driver (fast, paravirtualized — better performance than emulating
  real NIC hardware) attached to `vmbr0`, which is Proxmox's default network
  bridge connecting VMs to your physical network

At this point, VM 9000 exists but has **no disk** — it's just an empty shell
with CPU/RAM/network defined.

---

## PART 3 — Import the cloud image as this VM's disk

```bash
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm
```
- `qm importdisk` — takes an existing disk image file and imports it as an
  **unattached disk** into a VM's storage
- `9000` — which VM to import into
- `jammy-server-cloudimg-amd64.img` — the file we downloaded in Part 1
- `local-lvm` — the Proxmox storage pool to import into (this is commonly the
  default LVM-thin storage; yours might be named differently — check with
  `pvesm status` if unsure)

After this, the disk exists in storage but is **not yet attached** to the
VM's boot configuration — that's the next step.

---

## PART 4 — Attach the disk and add the cloud-init drive

```bash
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
```
- `qm set 9000` — modifies VM 9000's configuration
- `--scsihw virtio-scsi-pci` — sets the SCSI controller type to VirtIO SCSI
  (better performance than default emulated SCSI)
- `--scsi0 local-lvm:vm-9000-disk-0` — attaches the imported disk (from Part 3)
  as SCSI device 0. The disk name `vm-9000-disk-0` is Proxmox's auto-generated
  name for the first disk imported into VM 9000 — confirm this matches with
  `qm config 9000` if it was named differently.

```bash
qm set 9000 --ide2 local-lvm:cloudinit
```
- `--ide2 local-lvm:cloudinit` — this is the critical cloud-init-specific line.
  It tells Proxmox: "create a small virtual CD-ROM drive on IDE slot 2, and
  auto-generate NoCloud datasource content for it." This is what replaces the
  manual `genisoimage`/`seed.iso` process — Proxmox builds and manages that
  seed data internally whenever you set `--ciuser`, `--sshkeys`, `--cicustom`, etc.

```bash
qm set 9000 --boot order=scsi0
```
- Tells the VM's BIOS/UEFI to boot from `scsi0` (our actual OS disk) — without
  this, the VM might not know which device to boot from first, especially
  since we now have two "disks" attached (the real OS disk + the cloud-init drive).

```bash
qm set 9000 --serial0 socket --vga serial0
```
- Cloud images are often built without a proper graphical console (no GRUB
  splash screen, minimal video driver support). This line configures a serial
  console instead of a VGA display, which is how cloud images expect to output
  boot logs. Without this, you may see a blank/frozen console in the Proxmox
  UI even though the VM is booting fine underneath.

---

## PART 5 — Resize the disk

```bash
qm resize 9000 scsi0 +20G
```
- Cloud images ship intentionally small (often just 2-3 GB) to keep downloads
  fast. `qm resize` grows the disk by an additional amount.
- `scsi0` — which disk to resize (our OS disk from Part 4)
- `+20G` — add 20 GB on top of the existing size (not "set to 20G" — this is
  additive)
- Note: this resizes the underlying block device, but the filesystem inside
  the VM won't automatically use the new space unless `cloud-init`'s `growpart`
  module runs (which is enabled by default in most cloud images) — it detects
  the larger disk and extends the root partition/filesystem automatically on boot.

---

## PART 6 — Convert to a template

```bash
qm template 9000
```
- Converts VM 9000 from a regular VM into a **Proxmox template**. Templates
  are read-only and exist specifically to be cloned from — you cannot boot a
  template directly anymore after this command; you can only clone it.
- This is the "freeze the base image" step — from here on, VM 9000 itself is
  never touched again; all future work happens on clones.

---

## PART 7 — Clone the template for an actual dev server

```bash
qm clone 9000 101 --name dev-approach-a --full
```
- `qm clone 9000 101` — clone template 9000, creating a new VM with ID 101
- `--name dev-approach-a` — label for this specific clone
- `--full` — performs a **full clone** (an independent copy of the disk),
  as opposed to a linked clone (which would depend on the template disk
  still existing and share storage with it). Full clones are safer for
  production-style servers since they're fully independent — deleting or
  modifying the template later won't affect them.

---

## PART 8 — Deliver your DevOps install script via cloud-init

```bash
cp production-user-data.yaml /var/lib/vz/snippets/
```
- Copies your existing cloud-config YAML (the one with Docker install,
  idempotent script, user creation, etc.) into Proxmox's **snippets** storage
  location — the designated place Proxmox looks for custom cloud-init files.
- **Prerequisite:** the storage (`local` by default) must have "Snippets"
  enabled under its Content settings in the Proxmox UI, or this file won't
  be usable by `--cicustom` below.

```bash
qm set 101 --cicustom "user=local:snippets/production-user-data.yaml"
```
- `--cicustom` — tells Proxmox to use your **custom** file instead of
  auto-generating a minimal one from `--ciuser`/`--sshkeys` flags
- `"user=local:snippets/production-user-data.yaml"` — format is
  `user=<storage>:<path-under-snippets>`. This says: "for the user-data
  portion specifically, use this exact file from the `local` storage's
  snippets folder." (Proxmox also supports separate `network=` and `meta=`
  custom files the same way, if you needed those too.)
- Once you use `--cicustom` for user-data, it **replaces** anything you'd
  normally set via `--ciuser`/`--sshkeys`/`--cipassword` — those get ignored
  in favor of whatever your YAML file defines (your `users:` block already
  handles this).

```bash
qm set 101 --ipconfig0 ip=dhcp
```
- Configures the VM's first network interface to request an IP via DHCP.
  If your company network uses static IPs instead, replace with something like:
  `qm set 101 --ipconfig0 ip=192.168.1.50/24,gw=192.168.1.1`

---

## PART 9 — Boot and verify

```bash
qm start 101
```
- Powers on VM 101. On this first boot, cloud-init inside the guest OS will:
  1. Detect the Proxmox-generated NoCloud datasource (via the `ide2` cloud-init drive)
  2. Read your `production-user-data.yaml` content from it
  3. Create the `devops` user, install Docker, run your idempotent script — all live, right now, taking real time (this is Approach A's defining trait)

From your workstation, once you have the VM's IP (check Proxmox UI or your DHCP server's leases):

```bash
ssh devops@<vm-ip>
```
- Connects using the SSH key you baked into the YAML's `users:` block

Once inside:

```bash
cat /var/log/provision.log
```
- Shows your script's own timestamped log — confirms each install step
  actually ran and in what order

```bash
docker --version
```
- Confirms Docker installed successfully

```bash
groups devops
```
- Confirms `devops` is in the `docker` group (so `docker ps` works without sudo)

```bash
cloud-init status --long
```
- Confirms cloud-init itself completed all stages without error

---

## What "Approach A" means in this whole sequence

Every single time you run **Part 7 + Part 8 + Part 9** again for a *new* clone
(say VM 102 for UAT), the **entire Docker/Kubernetes/Helm install runs again,
from scratch, live** on that new VM's first boot. Parts 1-6 (download image,
build+templatize the base) only need to happen once — but the actual heavy
software installation repeats on every single clone, every time, because
nothing was pre-installed into the template itself.

That repeated install time is exactly what Approach B eliminates — worth
timing this whole Part 9 boot-to-`docker --version`-working process so you
have a real number to compare against once we do B.
