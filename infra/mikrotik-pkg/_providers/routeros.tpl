# RouterOS provider — MikroTik switch management via terraform-routeros/routeros.
#
# hosturl: SSH or REST API endpoint for the RouterOS device.
#   SSH mode:      ssh://<host>[:<port>]   (works with factory defaults; port 22)
#   REST API mode: https://<host>          (requires /ip/service www-ssl enabled first)
#
# BOOTSTRAP NOTE: First apply must use the factory-default address while the
# laptop is directly connected to the switch's RJ45 management port:
#   _provider_routeros_endpoint: "ssh://192.168.88.1"
# After first apply, the switch has management IP 10.0.11.5 on VLAN 11.
# Update the endpoint to "ssh://10.0.11.5" and re-apply (idempotent).
# See docs/idempotence-and-tech-debt.md for details.
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    routeros = { source = "terraform-routeros/routeros", version = "~> 1.0" }
  }
}
provider "routeros" {
  hosturl  = "${ENDPOINT}"
  username = "${USERNAME}"
  password = "${PASSWORD}"
  insecure = ${INSECURE}
}
