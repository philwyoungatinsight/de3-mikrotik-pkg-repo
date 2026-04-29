# mikrotik-pkg

Manages the MikroTik CRS317-1G-16S+RM 10GigE switch via the
[terraform-routeros/routeros](https://registry.terraform.io/providers/terraform-routeros/routeros/latest)
Terraform provider.

## What it configures

- **VLAN-aware bridge** (`bridge1`) with hardware offload on all active SFP+ ports
- **Port roles**: uplink (→ Pro Max port 18), cloud_public (VLAN 10)
- **Bridge VLAN table**: VLAN 10 (cloud), 11 (management), 12 (provisioning pass-through), 14 (storage reserved)
- **Management interface**: `vlan11-mgmt` on `bridge1` → `10.0.11.5/24` via VLAN 11
- **Default route**: `0.0.0.0/0` via `10.0.11.1` (UDM gateway on VLAN 11)

## Current cabling

5 SFP+ cables in use: 1 uplink + 4 host cloud ports (pve-1, ms01-01/02/03).
Storage ports (VLAN 14, MTU 9000) are deferred until more cables are available.

```
Pro Max port 18 (hypervisor_trunk) ──SFP+── CRS317 sfpplus16 (uplink, PVID 10) [pre-existing]
pve-1    SFP+ NIC ──────────────────────────── CRS317 sfpplus1  (cloud,  PVID 10)
ms01-01  SFP+ NIC ──────────────────────────── CRS317 sfpplus2  (cloud,  PVID 10)
ms01-02  SFP+ NIC ──────────────────────────── CRS317 sfpplus3  (cloud,  PVID 10)
ms01-03  SFP+ NIC ──────────────────────────── CRS317 sfpplus4  (cloud,  PVID 10)
sfpplus5-15                                                      (spare — storage VLAN 14 when cables available)
```

## Future storage expansion

When more SFP+ cables are available, add storage ports to `mikrotik-pkg.yaml`:

```yaml
ports:
  sfpplus3:
    name: pve-1-storage
    role: storage
    pvid: 14
  # ... repeat for ms01-01 (sfpplus5), ms01-02 (sfpplus7), ms01-03 (sfpplus9)
storage_mtu: 9000
```

Then add `nic_10g_storage` to each Proxmox node entry in `pwy-home-lab-pkg.yaml` and
run `configure-proxmox-10g-bridges` to create the `vmbr-storage` bridge.

## Bootstrap procedure (one-time)

The CRS317 ships with factory default IP `192.168.88.1` on `ether1`/bridge. Terraform
connects via the RouterOS API-SSL service (port 8729, enabled by default on RouterOS 7)
while the laptop's RJ45 port is plugged into the CRS317's RJ45 management port.

**Steps:**

1. Ensure `_provider_routeros_endpoint: "apis://192.168.88.1:8729"` in your deployment
   config (this is the bootstrap default; only change it after bootstrap is complete).

2. With the laptop directly cabled to CRS317 RJ45:
   ```bash
   source set_env.sh
   cd infra/mikrotik-pkg/_stack/routeros/example-lab/switches/crs317-example-switch
   terragrunt apply
   ```

3. Verify management IP is reachable: `ping 10.0.11.5`
   (requires CRS317 → Pro Max → network path, so the sfpplus1 uplink cable must be in.)

4. Disconnect laptop RJ45 from CRS317.

5. Update your deployment config:
   ```yaml
   _provider_routeros_endpoint: "apis://10.0.11.5:8729"
   ```

6. Re-apply (idempotent): `terragrunt apply`

## Adding or removing a host connection

Edit `config_params` in `mikrotik-pkg.yaml` under the `crs317-example-switch` key.
Add or remove entries in `ports:` for the relevant `sfpplusN` interfaces. Re-run
the `network.mikrotik` wave.

## Tech debt

See `docs/idempotence-and-tech-debt.md` for:
- Bootstrap endpoint swap (manual endpoint change after first apply)
- Admin password rotation (not yet managed by Terraform)
