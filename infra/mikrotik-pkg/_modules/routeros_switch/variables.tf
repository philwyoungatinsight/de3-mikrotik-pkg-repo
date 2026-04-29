variable "hostname" {
  description = "Switch hostname (RouterOS system identity name)"
  type        = string
}

variable "management_vlan_id" {
  description = "VLAN ID for the switch management interface (e.g. 11 for the management VLAN)"
  type        = number
}

variable "management_ip" {
  description = "Management IP address (without prefix length, e.g. '10.0.11.5')"
  type        = string
}

variable "management_prefix" {
  description = "Management IP prefix length (e.g. 24)"
  type        = number
}

variable "management_gateway" {
  description = "Default gateway IP reachable via the management VLAN (e.g. '10.0.11.1')"
  type        = string
}

variable "storage_mtu" {
  description = "MTU applied to the bridge and all bridge ports. Set to 9000 to enable jumbo frames on the storage path."
  type        = number
  default     = 9000
}

variable "ports" {
  description = <<-EOT
    Map of SFP+ interface name → port config. Each entry:
      role  (string)           – "uplink" | "cloud_public" | "storage"
      pvid  (number)           – Port VLAN ID; untagged ingress frames are classified to this VLAN
      name  (string, optional) – Descriptive label written to the RouterOS interface comment
  EOT
  type = map(object({
    role = string
    pvid = number
    name = optional(string, "")
  }))
}

variable "vlans" {
  description = <<-EOT
    VLAN ID definitions. All four keys are required.
      cloud_public  – VLAN 10, cloud/VM traffic
      management    – VLAN 11, switch management and AMT/IPMI
      provisioning  – VLAN 12, MaaS PXE (pass-through on uplink only)
      storage       – VLAN 14, inter-host storage traffic (jumbo frames)
  EOT
  type = object({
    cloud_public = object({ id = number })
    management   = object({ id = number })
    provisioning = object({ id = number })
    storage      = object({ id = number })
  })
}
