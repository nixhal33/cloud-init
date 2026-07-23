# Approach B: Prebaked Cloud Image Workflow (Proxmox)

Approach B = install Docker/Kubernetes/Helm/git etc. **once**, into one VM,
then freeze that VM into a template. Every future clone already has the full
stack — cloud-init only handles lightweight per-instance setup (user, SSH key,
hostname, IP), not software installation.

Run all commands from the **Proxmox host shell** unless otherwise noted.

---

## PART 1 — Download the base cloud image

```bash
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```
Same as Approach A — same base image, same reasoning (pre-built cloud-init-ready
disk, not a regular installer ISO). No difference yet — the divergence starts
once the VM actually boots.

---

## PART 2 — Create the base VM (this one will become your "golden image")

```bash
qm create 9006 --name devops-stack-B --memory 8192 --cores 4 --net0 virtio,bridge=vmbr0
```
- Same flags as before, but note the **ID is 9006**, not 9000 — keep this
  separate from your Approach A template so you can compare both side by side
  without overwriting anything.
- `--name devops-stack-B` — labeling it clearly as the not-yet-finished
  "base" image, before it becomes a template

```bash
qm importdisk 9006 jammy-server-cloudimg-amd64.img local-lvm
```
Imports the same cloud image as an unattached disk into VM 9006.

```bash
qm set 9006 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9006-disk-0
qm set 9006 --ide2 local-lvm:cloudinit
qm set 9006 --boot order=scsi0
qm set 9006 --vga std
```
Identical purpose to Approach A Part 4 — attach the OS disk, add the
Proxmox-managed cloud-init drive, set boot order, configure serial console.

```bash
qm resize 9006 scsi0 +50G
```
Same as before — grow the disk before you start installing a full DevOps
stack, since Docker images/K8s/Helm charts will need real space. You may even
want more than 20G here, since this VM will accumulate more disk usage than a
bare Approach-A clone would at first boot (e.g. `+30G` if you plan to pull
container images into it too).

---

## PART 3 — Boot this VM temporarily (NOT templatized yet)

This is the key divergence point from Approach A. Instead of templatizing
immediately, you boot it as a **working, temporary VM** so you can manually
install software inside it.

```bash
qm set 9006 --ciuser nix-devops --cipassword 'nix@wwe3390' --sshkeys /root/.ssh/id_ed25519.nix.pub --ipconfig0 ip=192.168.50.xxx/24,gw=192.168.xx.x 
```
- `--ciuser devops` — tells Proxmox's auto-generated cloud-init data to create a user called `nix-devops` (simpler than a full custom YAML, since this is just a temporary working session, not the final per-clone config)
- `--cipassword 'nix@wwe33'` — tells Proxmox's auto-generated cloud-init data to put the password to the user called `nix-devops` 
- `--sshkeys /root/.ssh/id_ed25519.nix.pub` — **note this path is on the Proxmox
  host**, not your laptop. If your public key isn't already there, copy it
  Basically, I have first copied my own host ssh keys into my pve server terminal and gave the exact location of my .pub key of my host system. 
  over first: `scp ~/.ssh/id_ed25519.nix.pub root@<pve-host>:/root/.ssh/`
- `--ipconfig0 ip=dhcp` — get an IP so you can actually SSH in and it's a dynamic ip whereas i have set permanent/static ip explicitly defining ip=xxx.xxx.xx.xxx/24,gw=xxx.xxx.xx.xx as ip address with subnet and gateway

```bash
qm start 9006
```
Boots the VM. Cloud-init runs its lightweight default job here (create
`devops` user + inject key) — nothing heavy yet.

---

## PART 4 — SSH in and install the full stack manually

From your workstation (get the IP from Proxmox UI or your DHCP leases):

```bash
ssh nix-devops@<vm-ip>
```

Now run your existing install script **directly**, interactively, once:

```bash
sudo bash install-devops-stack.sh
```
- This is the exact same script logic you've already built and tested via
  cloud-init in Approach A — Docker, tree, docker-compose-plugin, etc.
- The difference: this time you're running it **by hand, once**, into a VM
  that will become the template — not via `runcmd` on every future boot.
- If you also want Kubernetes/Helm/git baked in (as you mentioned), install
  those here too, e.g.:

```bash
# git
sudo apt install -y git

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl (client only — full K8s cluster setup is a separate topic)
sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Verify everything's actually installed before moving on:
```bash
docker --version
git --version
helm version
kubectl version --client
```

---

## PART 5 — Clean up cloud-init state before freezing

This step is **critical** and easy to miss. If you skip it, every future
clone will think cloud-init "already ran" and skip creating its own user/SSH
key — because cloud-init's completion state would be baked into the disk image.

```bash
sudo cloud-init clean --logs --seed
```
- `cloud-init clean` — resets cloud-init's recorded state so it thinks it
  hasn't run yet
- `--logs` — also clears old log files, so your future clones start with
  clean logs instead of this VM's manual-install logs
- `--seed` — removes cached seed/datasource data too

```bash
sudo rm -rf /var/lib/cloud/instances/*
```
- Extra-thorough cleanup of any leftover per-instance state cloud-init stored,
  ensuring nothing "remembers" this specific boot when the disk is cloned

```bash
sudo shutdown now
```
- Cleanly powers off the VM before you templatize it. Templatizing a running
  VM is not something you want to do — always shut down first.

---

## PART 6 — Convert to a template

Back on the **Proxmox host**:

```bash
qm template 9006
```
Same meaning as Approach A — freezes this VM as read-only, clone-only from
here on. Except this time, the frozen disk **already contains Docker, git,
Helm, kubectl fully installed** — that's the entire point of Approach B.

---

## PART 7 — Clone for an actual dev/UAT server

```bash
qm clone 9006 102 --name dev-approach-b --full
```
Same reasoning as Approach A's clone step — full, independent clone.

```b0ash
qm set 102 --ciuser devops --sshkeys /root/.ssh/id_ed25519.pub --ipconfig0 ip=dhcp
```
- Since the heavy software is already baked in, this clone's cloud-init job
  is now **only**: create the user, inject the SSH key, configure the IP.
  Nothing to install — hence much faster.
- You could still use `--cicustom` with a lightweight YAML here instead if you
  want more per-clone customization (e.g. writing a hostname-specific config
  file, setting a custom message), but it no longer needs a `packages:` or
  Docker `runcmd` section at all, since that's already on the disk.

---

## PART 8 — Boot and verify (this is the comparison point)

```bash
qm start 102
```

```bash
ssh devops@<vm-ip>
docker --version
git --version
helm version
kubectl version --client
```

**Time this exact sequence** — from `qm start 102` to `docker --version`
returning successfully. Compare directly against your Approach A timing.
You should see this come up noticeably faster, since nothing is being
downloaded/installed/compiled at boot — it's already sitting on the disk.

---

## Side-by-side summary

| | Approach A | Approach B |
|---|---|---|
| When software installs | Every clone, every boot | Once, before templatizing |
| Boot-to-ready time | Minutes (real install happening) | Seconds (nothing to install) |
| Template disk size | Small (bare OS only) | Larger (full stack baked in) |
| Consistency across clones | Depends on install succeeding identically each time | Guaranteed identical — it's a literal copy |
| Best for | Wanting latest package versions each time, or infrequent VM creation | Frequent clone creation, consistent dev/UAT environments, fast spin-up |
| cloud-init's role at clone-time | Heavy — runs full install script | Light — just user/SSH/network setup |

Once you've run this and timed it, you'll have real numbers from your own
infrastructure to decide which approach fits your dev/UAT migration best —
or, quite possibly, a mix: Approach B for your common baseline stack, with a
small Approach-A-style `--cicustom` script layered on top for anything
environment-specific (like dev-only debug tools vs UAT-only monitoring agents).
