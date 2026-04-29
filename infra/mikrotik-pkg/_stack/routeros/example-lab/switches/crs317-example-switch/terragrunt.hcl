include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${include.root.locals.modules_dir}/routeros_switch"
}

# ---------------------------------------------------------------------------
# Example unit — disabled by _skip_on_build: true in mikrotik-pkg.yaml.
# Illustrates the required config structure for a CRS317 deployment.
#
# Switch-specific values live under:
#   mikrotik-pkg/_stack/routeros/example-lab/switches/crs317-example-switch
#
# Provider endpoint / credentials live under (ancestor-merged):
#   mikrotik-pkg/_stack/routeros/example-lab
#
# For a real deployment copy this stack to your deployment package
# (e.g. pwy-home-lab-pkg/_stack/routeros/) and add _modules_dir in config.
# ---------------------------------------------------------------------------

locals {
  hostname           = try(include.root.locals.unit_params.hostname,            "crs317")
  management_vlan_id = try(include.root.locals.unit_params.management_vlan_id, 11)
  management_ip      = try(include.root.locals.unit_params.management_ip,       "")
  management_prefix  = try(include.root.locals.unit_params.management_prefix,   24)
  management_gateway = try(include.root.locals.unit_params.management_gateway,  "")
  storage_mtu        = try(include.root.locals.unit_params.storage_mtu,         9000)
  ports              = try(include.root.locals.unit_params.ports,               {})
  vlans              = try(include.root.locals.unit_params.vlans,               {})
}

inputs = {
  hostname           = local.hostname
  management_vlan_id = local.management_vlan_id
  management_ip      = local.management_ip
  management_prefix  = local.management_prefix
  management_gateway = local.management_gateway
  storage_mtu        = local.storage_mtu
  ports              = local.ports
  vlans              = local.vlans
}
