# routeros_switch module — configures a MikroTik CRS317 running RouterOS.
#
# What this manages:
#   - System hostname
#   - VLAN-aware bridge (bridge1) with hardware offload enabled
#   - Bridge ports for all SFP+ interfaces with PVID and frame-type policy
#   - Bridge VLAN table:
#       VLAN 10 (cloud_public)  – untagged on uplink + cloud host ports
#       VLAN 11 (management)    – tagged on uplink, CPU (bridge1) for mgmt IP
#       VLAN 12 (provisioning)  – tagged on uplink only (PXE pass-through)
#       VLAN 14 (storage)       – tagged on uplink, untagged on storage host ports
#   - Management VLAN interface (vlan<id>-mgmt on bridge1) and static IP
#   - Default route via management gateway
#
# What this does NOT manage (tech debt):
#   - Admin password rotation (change manually; see docs/idempotence-and-tech-debt.md)
#   - Removal of factory-default bridge, DHCP server, or ether1 IP — left intact
#     as a "console" path for direct laptop access at 192.168.88.1

locals {
  uplink_port   = one([for k, v in var.ports : k if v.role == "uplink"])
  cloud_ports   = [for k, v in var.ports : k if v.role == "cloud_public"]
  storage_ports = [for k, v in var.ports : k if v.role == "storage"]

  all_port_names = keys(var.ports)
}

# ---------------------------------------------------------------------------
# System identity — sets the RouterOS hostname shown in winbox/SSH prompt
# ---------------------------------------------------------------------------
resource "routeros_system_identity" "this" {
  name = var.hostname
}

# ---------------------------------------------------------------------------
# VLAN-aware bridge — bridge1
#
# Uses bridge1 (not the factory-default "bridge") to avoid disrupting the
# factory ether1 management address (192.168.88.1) during bootstrap.
# Hardware offload (hw=true on ports) delegates L2 forwarding to the
# Marvell switch ASIC for 10G line-rate performance.
#
# MTU is set globally to storage_mtu (9000) which enables jumbo frames on
# all ports. The cloud and uplink paths handle 9000-byte frames fine; the
# storage path explicitly requires it.
# ---------------------------------------------------------------------------
resource "routeros_interface_bridge" "bridge1" {
  name           = "bridge1"
  vlan_filtering = true
  mtu            = var.storage_mtu

  # Admit all frame types at the bridge level; per-port frame_types narrows this.
  frame_types = "admit-all"
}

# ---------------------------------------------------------------------------
# Interface comments — labels visible in RouterOS UI and logs
# ---------------------------------------------------------------------------
resource "routeros_interface_ethernet" "port_labels" {
  for_each = var.ports

  factory_name = each.key
  name         = each.key
  comment      = each.value.name
}

# ---------------------------------------------------------------------------
# Bridge ports — adds each SFP+ interface to bridge1 with PVID and policy
#
# Uplink (sfpplus1):
#   pvid=10      — Pro Max sends VLAN 10 untagged (native on hypervisor_trunk)
#   admit-all    — also accepts tagged VLAN 11/12/14 from the trunk
#
# Cloud host ports (sfpplus2/4/6/8):
#   pvid=10      — host NIC sends untagged; bridge classifies as VLAN 10
#   admit-only-untagged-and-priority-tagged — access port; blocks unexpected tags
#
# Storage host ports (sfpplus3/5/7/9):
#   pvid=14      — host NIC sends untagged; bridge classifies as VLAN 14
#   admit-only-untagged-and-priority-tagged — access port
# ---------------------------------------------------------------------------
resource "routeros_interface_bridge_port" "ports" {
  for_each = var.ports

  bridge    = routeros_interface_bridge.bridge1.name
  interface = each.key
  pvid      = each.value.pvid
  hw        = true

  frame_types = each.value.role == "uplink" ? "admit-all" : "admit-only-untagged-and-priority-tagged"

  depends_on = [routeros_interface_bridge.bridge1]
}

# ---------------------------------------------------------------------------
# Bridge VLAN table — VLAN 10 (cloud_public)
#
# untagged: uplink + all cloud host ports
#   Pro Max sends VLAN 10 as native (untagged); hosts receive untagged traffic.
#   No tagged entries needed — switch CPU does not participate in VLAN 10.
# ---------------------------------------------------------------------------
resource "routeros_interface_bridge_vlan" "vlan_cloud_public" {
  bridge   = routeros_interface_bridge.bridge1.name
  tagged   = []
  untagged = concat([local.uplink_port], local.cloud_ports)
  vlan_ids = [tostring(var.vlans.cloud_public.id)]

  depends_on = [routeros_interface_bridge_port.ports]
}

# ---------------------------------------------------------------------------
# Bridge VLAN table — VLAN 11 (management)
#
# tagged: uplink (tagged from Pro Max hypervisor_trunk) + bridge1 CPU
#   The bridge1 interface is in tagged so the vlan11-mgmt VLAN sub-interface
#   can send/receive tagged VLAN 11 frames for the management IP.
# ---------------------------------------------------------------------------
resource "routeros_interface_bridge_vlan" "vlan_management" {
  bridge   = routeros_interface_bridge.bridge1.name
  tagged   = [local.uplink_port, routeros_interface_bridge.bridge1.name]
  untagged = []
  vlan_ids = [tostring(var.vlans.management.id)]

  depends_on = [routeros_interface_bridge_port.ports]
}

# ---------------------------------------------------------------------------
# Bridge VLAN table — VLAN 12 (provisioning, pass-through only)
#
# tagged: uplink only — PXE traffic passes between Pro Max and any future
# device that needs it. No host 10G ports participate in provisioning VLAN;
# ms01 PXE NICs are on the dedicated 2.5G Flex switch.
# ---------------------------------------------------------------------------
resource "routeros_interface_bridge_vlan" "vlan_provisioning" {
  bridge   = routeros_interface_bridge.bridge1.name
  tagged   = [local.uplink_port]
  untagged = []
  vlan_ids = [tostring(var.vlans.provisioning.id)]

  depends_on = [routeros_interface_bridge_port.ports]
}

# ---------------------------------------------------------------------------
# Bridge VLAN table — VLAN 14 (storage)
#
# tagged:   uplink — Pro Max sends VLAN 14 tagged (hypervisor_trunk)
# untagged: all storage host ports — host NICs receive untagged; Proxmox
#           assigns vmbr-storage (MTU 9000) on the storage VLAN
# ---------------------------------------------------------------------------
resource "routeros_interface_bridge_vlan" "vlan_storage" {
  bridge   = routeros_interface_bridge.bridge1.name
  tagged   = [local.uplink_port]
  untagged = local.storage_ports
  vlan_ids = [tostring(var.vlans.storage.id)]

  depends_on = [routeros_interface_bridge_port.ports]
}

# ---------------------------------------------------------------------------
# Management VLAN interface — vlan<id>-mgmt on bridge1
#
# Creates a CPU-side VLAN sub-interface so the switch can have a routable
# IP address on the management VLAN (10.0.11.5/24).
# ---------------------------------------------------------------------------
resource "routeros_interface_vlan" "mgmt" {
  name      = "vlan${var.vlans.management.id}-mgmt"
  vlan_id   = var.vlans.management.id
  interface = routeros_interface_bridge.bridge1.name

  depends_on = [routeros_interface_bridge_vlan.vlan_management]
}

resource "routeros_ip_address" "mgmt" {
  address   = "${var.management_ip}/${var.management_prefix}"
  interface = routeros_interface_vlan.mgmt.name
}

# ---------------------------------------------------------------------------
# Default route — via management gateway
#
# Requires RouterOS 7+: provider v1.99.1 sends routing-table=main which
# RouterOS 6.49.x rejects with "unknown parameter". Switch is on ROS 7.
# ---------------------------------------------------------------------------
resource "routeros_ip_route" "default" {
  dst_address = "0.0.0.0/0"
  gateway     = var.management_gateway

  depends_on = [routeros_ip_address.mgmt]
}
