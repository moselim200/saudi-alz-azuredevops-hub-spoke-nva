# Source provenance and third-party notices

Retain the upstream licenses with redistributed source.
The starter license is also retained at
`overlays\LICENSE.alz-terraform-accelerator`; module and bootstrap licenses
remain alongside their respective sources.

| Component | Pin | Included source / local change |
| --- | --- | --- |
| ALZ Terraform accelerator starter | v17.7.0 / `971521667191010072a3e0a3d8f300a72c701c08` | The single root overlay changes the hub-spoke module source to the local vendor copy. The official ALZ bootstrap downloads the remaining starter. |
| AVM hub-spoke VNet | 0.17.2 / `a7da6e9bf6ae7a4be49ccbe47e57ce6e8efc2fb6` | Runtime root `.tf` files, both complete local child-module directories, README and LICENSE. The root Private DNS call alone is redirected locally. |
| AVM Private DNS zones | 0.23.2 / `4d2214f162806d48ea9a157de4b904f879fc61d4` | Existing Saudi-compatible runtime source, LICENSE and regression tests; confirmed `sae` Backup mapping retained. |
| ALZ bootstrap modules | `7887040f5e865ba134b4108aeac7b83a397a0d5c` | Existing pinned bootstrap source and license. CI plan, CD plan and CD apply templates retain `ARM_PROVIDER_ENHANCED_VALIDATION_LOCATIONS: "false"`. |
| ALZ library | `platform/alz@2026.11.0` | Custom library references the public library and supplies the reviewed architecture/archetype overrides. |

Upstream repositories:

- https://github.com/Azure/alz-terraform-accelerator
- https://github.com/Azure/terraform-azurerm-avm-ptn-alz-connectivity-hub-and-spoke-vnet
- https://github.com/Azure/terraform-azurerm-avm-ptn-network-private-link-private-dns-zones
- https://github.com/Azure/accelerator-bootstrap-modules
- https://github.com/Azure/Azure-Landing-Zones-Library

Registry child modules and provider binaries are downloaded through the normal
Terraform workflow, not bundled. Root constraints are not an exhaustive
transitive dependency freeze; retain generated dependency locks and record the
versions used in the customer's own runs.
