mock_provider "alz" {}
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}
mock_provider "azurerm" {
  alias = "connectivity"
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}
mock_provider "azurerm" {
  alias = "management"
}
mock_provider "azapi" {}
mock_provider "azapi" {
  alias = "connectivity"
}
mock_provider "local" {}
mock_provider "random" {}
mock_provider "time" {}

override_module {
  target = module.hub_and_spoke_vnet[0].module.regions[0]
  outputs = {
    regions_by_name = {
      saudiarabiaeast = {
        zones = []
      }
    }
  }
}

override_module {
  target = module.config.module.regions
  outputs = {
    regions_by_name = {
      saudiarabiaeast = {
        geo_code   = null
        short_name = "sae"
      }
    }
  }
}

override_module {
  target = module.hub_and_spoke_vnet[0].module.private_dns_zones["primary"].module.regions
  outputs = {
    regions_by_name_or_display_name = {
      saudiarabiaeast = {
        name     = "saudiarabiaeast"
        geo_code = null
      }
    }
  }
}

variables {
  root_parent_management_group_id = "synthetic-validation-parent"
  subscription_ids = {
    management   = "00000000-0000-0000-0000-000000000002"
    identity     = "00000000-0000-0000-0000-000000000004"
    connectivity = "00000000-0000-0000-0000-000000000003"
    security     = "00000000-0000-0000-0000-000000000005"
  }
  management_groups_enabled = false
  enable_telemetry          = false
}

run "hub_spoke_nva_ready" {
  command = plan

  assert {
    condition     = length(module.hub_and_spoke_vnet) == 1 && length(module.virtual_wan) == 0
    error_message = "The staged package must select the actual hub-spoke module, not vWAN."
  }

  assert {
    condition = (
      module.config.outputs.management_group_settings.location == "uaenorth" &&
      jsondecode(local.policy_default_values.resource_group_location).value == "saudiarabiaeast" &&
      jsondecode(local.policy_default_values.private_dns_zone_region).value == "saudiarabiaeast" &&
      !var.management_resources_enabled &&
      length(module.management_resources) == 0
    )
    error_message = "The shared Saudi/UAE policy and reduced-monitoring choices changed."
  }

  assert {
    condition = (
      length(module.hub_and_spoke_vnet[0].private_dns_zone_resource_ids) == 1 &&
      module.hub_and_spoke_vnet[0].private_link_private_dns_zones_maps.primary.azure_backup.zone_name == "privatelink.sae.backup.windowsazure.com"
    )
    error_message = "The real hub-spoke module must call the patched DNS module and produce the Saudi Backup zone."
  }

  assert {
    condition = (
      length(module.hub_and_spoke_vnet[0].dns_resolver_resource_ids) == 0 &&
      module.hub_and_spoke_vnet[0].ddos_protection_plan_resource_id == null &&
      length(module.hub_and_spoke_vnet[0].virtual_network_gateway_resource_ids) == 0 &&
      length(module.hub_and_spoke_vnet[0].firewall_resource_ids) == 0 &&
      length(module.hub_and_spoke_vnet[0].firewall_policies) == 0
    )
    error_message = "Unsupported or out-of-scope Resolver, DDoS, gateways or Azure Firewall resources were re-enabled."
  }

  assert {
    condition = (
      module.config.outputs.hub_virtual_networks.primary.hub_virtual_network.hub_router_ip_address == module.config.custom_replacements.primary_nva_ip_address &&
      !module.config.outputs.hub_virtual_networks.primary.hub_virtual_network.subnets.nva.route_table.assign_generated_route_table &&
      length(module.hub_and_spoke_vnet[0].route_tables_user_subnets) == 1
    )
    error_message = "Generated user routes must use the reviewed sample next hop without associating its own subnet back to it."
  }

  assert {
    condition = (
      length(module.hub_and_spoke_vnet[0].bastion_host_resource_ids) == 1 &&
      length(module.config.outputs.hub_virtual_networks.primary.bastion.zones) == 0 &&
      length(module.config.outputs.hub_virtual_networks.primary.bastion.bastion_public_ip.zones) == 0 &&
      !strcontains(jsonencode(module.config.outputs), "$${")
    )
    error_message = "Bastion settings must remain non-zonal and all source replacement tokens must resolve."
  }
}
