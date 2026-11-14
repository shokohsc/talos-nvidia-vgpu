# Proxmox host configuration boundary

The Talos extension is guest-only. Proxmox must have a compatible NVIDIA vGPU Manager installed for the host kernel and GPU. Create the mediated device on Proxmox and assign it to the Talos VM using the Proxmox-supported workflow.

Do not put host vGPU Manager packages or the nvidia-vgpu-vfio module in this extension.

For Tesla P4 or P40, select a full-card vGPU profile from the profile list exposed by the installed vGPU Manager. P4-8Q and P40-24Q are examples previously considered; availability depends on exact GPU SKU, vGPU Manager release, and licensing. Validate against the host profile list rather than hard-coding profile IDs in Talos.

The guest driver branch/version must be compatible with the host vGPU Manager branch. This project pins guest 535.161.07; verify the host manager compatibility matrix before assignment.