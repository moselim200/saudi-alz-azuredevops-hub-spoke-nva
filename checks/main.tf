variable "starter_locations" {
  type = list(string)
}

variable "connectivity_type" {
  type = string
}

variable "hub_virtual_networks" {
  type = any
}

variable "custom_replacements" {
  type = any
}

variable "management_resources_enabled" {
  type = bool
}

variable "management_group_settings" {
  type = any
}

variable "management_groups_enabled" {
  type = bool
}

variable "connectivity_resource_groups" {
  type = any
}

variable "hub_and_spoke_networks_settings" {
  type = any
}

variable "tags" {
  type = map(string)
}

variable "enable_telemetry" {
  type    = bool
  default = true
}

variable "telemetry_additional_content" {
  type    = map(string)
  default = null
}

variable "virtual_hubs" {
  type    = any
  default = {}
}

variable "virtual_wan_settings" {
  type    = any
  default = null
}

locals {
  profile_errors = compact([
    var.connectivity_type == "hub_and_spoke_vnet" && length(var.virtual_hubs) == 0 && var.virtual_wan_settings == null ? "" : "Use the hub-spoke topology without vWAN maps",
    length(var.starter_locations) == 1 && var.starter_locations[0] == "saudiarabiaeast" ? "" : "This reviewed profile uses Saudi Arabia East only",
    !var.management_resources_enabled && var.management_group_settings.location == "uaenorth" ? "" : "Retain the reviewed monitoring reduction and UAE policy identity location",
    try(var.management_group_settings.policy_default_values.private_dns_zone_region == "$${starter_location_01}" && var.management_group_settings.policy_default_values.resource_group_location == "$${starter_location_01}", false) ? "" : "Policy-created resources must retain Saudi starter-location replacements",
    try(!tobool(var.hub_virtual_networks.primary.enabled_resources.firewall), false) ? "" : "Azure Firewall must remain disabled in the NVA-ready profile",
    try(!tobool(var.custom_replacements.names.primary_private_dns_resolver_enabled) && tobool(var.custom_replacements.names.primary_private_dns_zones_enabled), false) ? "" : "Keep Resolver disabled and Private DNS zones enabled",
    try(var.hub_virtual_networks.primary.enabled_resources.private_dns_resolver == "$${primary_private_dns_resolver_enabled}" && var.hub_virtual_networks.primary.enabled_resources.private_dns_zones == "$${primary_private_dns_zones_enabled}", false) ? "" : "Keep the reviewed Private DNS and Resolver flag wiring",
    try(!tobool(var.custom_replacements.names.ddos_protection_plan_enabled), false) ? "" : "DDoS remains outside this reduced test profile",
    try(var.hub_virtual_networks.primary.hub_virtual_network.hub_router_ip_address == "$${primary_nva_ip_address}" && can(cidrhost("${var.custom_replacements.names.primary_nva_ip_address}/32", 0)), false) ? "" : "Set a valid NVA next-hop IPv4 address and retain its replacement wiring",
    try(!var.hub_virtual_networks.primary.hub_virtual_network.subnets.nva.route_table.assign_generated_route_table, false) ? "" : "Do not associate the appliance subnet with its own generated user route table",
    try(var.management_group_settings.policy_assignments_to_modify.corp.policy_assignments["Deploy-Private-DNS-Zones"].parameters.dnzZoneRegionShortNames.saudiarabiaeast == "sae", false) ? "" : "Retain the confirmed Saudi Backup DNS policy mapping",
    try(length(var.hub_virtual_networks.primary.bastion.zones) == 0 && length(var.hub_virtual_networks.primary.bastion.bastion_public_ip.zones) == 0, false) ? "" : "Keep matching non-zonal Bastion and public-IP settings"
  ])
}
