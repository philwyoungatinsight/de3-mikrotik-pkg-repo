output "management_ip" {
  description = "Configured management IP of the switch (VLAN 11 interface)"
  value       = var.management_ip
}

output "management_vlan_id" {
  description = "VLAN ID of the management interface"
  value       = var.vlans.management.id
}

output "bridge_name" {
  description = "Name of the VLAN-aware bridge"
  value       = routeros_interface_bridge.bridge1.name
}
