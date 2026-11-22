#Requires -Version 7.0
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
  [switch]$CheckOnly,
  [string]$TerraformPath = "terraform"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$root = $PSScriptRoot
$inputsPath = Join-Path $root "config\inputs.yaml"
$platformPath = Join-Path $root "config\platform-landing-zone.tfvars"
$bootstrapPath = Join-Path $root "sources\bootstrap"
$additionalFiles = @(
  (Join-Path $root "config\lib")
  (Join-Path $root "overlays\main.connectivity.hub.and.spoke.virtual.network.tf")
  (Join-Path $root "overlays\modules")
  (Join-Path $root "overlays\tests")
)

Import-Module powershell-yaml -ErrorAction Stop
$settings = Get-Content -LiteralPath $inputsPath -Raw | ConvertFrom-Yaml -Ordered

# ALZ 7.1.5 prioritizes file/environment values over CLI paths. Reject stale wiring.
foreach ($key in @("bootstrap_module_override_folder_path", "starter_additional_files", "output_folder_path")) {
  if ($settings.Contains($key) -or [Environment]::GetEnvironmentVariable("ALZ_$key")) {
    throw "Remove $key from inputs.yaml and ALZ_$key from this process; the launcher supplies this path."
  }
}

foreach ($key in @("root_parent_management_group_id", "azure_devops_organization_name", "azure_devops_project_name", "service_name", "environment_name")) {
  $value = [string]$settings[$key]
  if ([string]::IsNullOrWhiteSpace($value) -or $value -match "[<>]") {
    throw "Set customer input '$key' in config\inputs.yaml."
  }
}

foreach ($key in @("service_name", "environment_name")) {
  if ([string]$settings[$key] -notmatch "^[a-z0-9]+$") {
    throw "Customer input '$key' must contain lowercase letters and numbers only."
  }
}
foreach ($key in @("azure_devops_create_project", "use_separate_repository_for_templates", "create_branch_policies")) {
  if ($settings[$key] -isnot [bool]) { throw "Set '$key' to a YAML Boolean." }
}
if ($settings.use_separate_repository_for_templates -ne $true -or $settings.create_branch_policies -ne $true) {
  throw "This profile requires separate templates and branch policies; review a different design separately."
}
if ($settings.apply_approvers -isnot [System.Collections.IList] -or
    @($settings.apply_approvers | Where-Object { [string]$_ -notmatch "^[^<>\s]+@[^<>\s]+$" }).Count -gt 0) {
  throw "Set apply_approvers to a YAML list of existing Azure DevOps user principal names, or []."
}
if ($settings.Contains("github_organization_name") -or $settings.Contains("use_self_hosted_runners")) {
  throw "Remove GitHub-only inputs; use the Azure DevOps inputs supplied with this package."
}

$subscriptions = @()
foreach ($role in @("management", "identity", "connectivity", "security")) {
  $value = [string]$settings.subscription_ids[$role]
  $id = [guid]::Empty
  if (-not [guid]::TryParse($value, [ref]$id) -or $id -eq [guid]::Empty) {
    throw "Set a real customer subscription GUID for '$role' in config\inputs.yaml."
  }
  $subscriptions += $id.ToString()
}
if (@($subscriptions | Select-Object -Unique).Count -ne 4) {
  throw "This architecture places four distinct platform subscriptions into different management groups."
}
$bootstrapSubscription = [guid]::Empty
if (-not [guid]::TryParse([string]$settings.bootstrap_subscription_id, [ref]$bootstrapSubscription) -or
    $bootstrapSubscription -eq [guid]::Empty) {
  throw "Set bootstrap_subscription_id in config\inputs.yaml."
}

foreach ($key in @("azure_devops_personal_access_token", "azure_devops_agents_personal_access_token")) {
  if ($settings[$key] -ne "<$key>") {
    throw "Keep the literal <$key> placeholder in inputs.yaml. Supply the PAT through TF_VAR_$key."
  }
}
if ($settings.iac_type -ne "terraform" -or $settings.bootstrap_module_name -ne "alz_azuredevops" -or
    $settings.starter_module_name -ne "platform_landing_zone" -or
    $settings.starter_module_version -ne "v17.7.0" -or $settings.terraform_version -ne "1.14.9") {
  throw "The starter/tool pins differ from the tested package. Revalidate before changing this profile."
}
if ($settings.bootstrap_location -ne "uaenorth" -or $settings.use_self_hosted_agents -ne $true -or
    $settings.use_private_networking -ne $true -or $settings.allow_storage_access_from_my_ip -ne $false) {
  throw "This package represents the UAE private-agent profile. Review a different design separately."
}

foreach ($path in @($bootstrapPath, $platformPath, (Join-Path $root "checks\main.tf")) + $additionalFiles) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required package source is missing: $path"
  }
  $hubModulePath = Join-Path $root "overlays\modules\vendor\hub-and-spoke-vnet"
  foreach ($relative in @("main.tf", "LICENSE", "modules\hub-virtual-network-mesh\main.tf", "modules\virtual-network-gateway\main.tf")) {
    if (-not (Test-Path -LiteralPath (Join-Path $hubModulePath $relative) -PathType Leaf)) {
      throw "Required pinned hub-spoke module source is missing: $relative"
    }
  }
  $rootSource = Get-Content -LiteralPath $additionalFiles[1] -Raw
  $hubSource = Get-Content -LiteralPath (Join-Path $hubModulePath "main.tf") -Raw
  $dnsPath = Join-Path $root "overlays\modules\vendor\private-dns-zones\locals.tf"
  if (-not (Test-Path -LiteralPath $dnsPath) -or
      $rootSource -notmatch 'source\s*=\s*"\./modules/vendor/hub-and-spoke-vnet"' -or
      $hubSource -notmatch 'module\s+"private_dns_zones"\s*\{\s*source\s*=\s*"\.\./private-dns-zones"' -or
      (Get-Content -LiteralPath $dnsPath -Raw) -notmatch 'saudiarabiaeast\s*=\s*"sae"') {
    throw "The hub-spoke-to-local-Private-DNS Saudi compatibility wiring is missing."
  }
}
foreach ($name in @("plan", "apply")) {
  $path = Join-Path $bootstrapPath "alz\azuredevops\pipelines\terraform\templates\helpers\terraform-$name.yaml"
  $pipeline = Get-Content -LiteralPath $path -Raw | ConvertFrom-Yaml -Ordered
  $tasks = @($pipeline.steps | Where-Object { $_.task -eq "AzureCLI@2" })
  if ($tasks.Count -ne 1 -or
      $tasks[0].env.ARM_PROVIDER_ENHANCED_VALIDATION_LOCATIONS -ne "false" -or
      $tasks[0].env.Contains("ARM_PROVIDER_ENHANCED_VALIDATION")) {
    throw "The expected AzureRM task environment guard is missing or conflicting in terraform-$name.yaml."
  }
}

$terraform = (Get-Command $TerraformPath -ErrorAction Stop).Source
$versionJson = & $terraform version -json
if ($LASTEXITCODE -ne 0) { throw "Cannot inspect the selected Terraform executable." }
if (($versionJson | ConvertFrom-Json).terraform_version -ne "1.14.9") {
  throw "Use Terraform 1.14.9 for the workflow-matching format check; pass its path with -TerraformPath."
}
& $terraform fmt -check $platformPath
if ($LASTEXITCODE -ne 0) {
  throw "Run Terraform 1.14.9 fmt on config\platform-landing-zone.tfvars after the last edit, then retry."
}
& $terraform fmt -check -recursive (Join-Path $root "overlays")
if ($LASTEXITCODE -ne 0) { throw "Staged Terraform files fail formatting." }
& $terraform fmt -check (Join-Path $root "checks\main.tf")
if ($LASTEXITCODE -ne 0) { throw "The offline profile contract fails formatting." }

$contractJson = "jsonencode(local.profile_errors)" |
  & $terraform "-chdir=$(Join-Path $root 'checks')" console -no-color "-var-file=$platformPath"
if ($LASTEXITCODE -ne 0) { throw "Cannot evaluate the offline hub-spoke NVA-ready profile contract." }
$contractErrors = @(($contractJson | ConvertFrom-Json) | ConvertFrom-Json)
if ($contractErrors.Count -gt 0) {
  throw ("Hub-spoke NVA-ready profile check failed: " + ($contractErrors -join "; "))
}

Write-Output "Local customer-input, hub-spoke NVA-ready profile, DNS wiring, template-guard and Terraform-format checks passed."
Write-Output "These offline checks do not verify Azure/Azure DevOps permissions, IPAM, regional capacity or production readiness."
if ($CheckOnly) { return }

Import-Module ALZ -RequiredVersion 7.1.5 -ErrorAction Stop
foreach ($key in @("azure_devops_personal_access_token", "azure_devops_agents_personal_access_token")) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable("TF_VAR_$key"))) {
    throw "Set TF_VAR_$key securely in this PowerShell process before starting bootstrap."
  }
}

$profile = "Saudi hub-spoke NVA-ready networking, no NVA appliance or workload spokes; UAE state/agents/policy identities; monitoring/Firewall/Resolver/DDoS/gateways omitted. Do not send traffic to the sample next hop before vendor integration. Azure DevOps creates or references the selected project and separate repositories. Review customer approvals, agent/pipeline authorization and environment approvals, IPAM, RBAC and naming first."
if (-not $PSCmdlet.ShouldProcess($profile, "Run the official ALZ bootstrap with this reviewed customer profile")) {
  return
}

# Keep only the replacement AzureRM setting; never let the wizard rewrite prepared inputs.
if (Test-Path Env:\ARM_PROVIDER_ENHANCED_VALIDATION) {
  Remove-Item Env:\ARM_PROVIDER_ENHANCED_VALIDATION
}
$env:ARM_PROVIDER_ENHANCED_VALIDATION_LOCATIONS = "false"
# The exact import above replaces the unpinned online latest-version lookup.
Deploy-Accelerator `
  -skipAlzModuleVersionRequirementsCheck `
  -inputs $inputsPath, $platformPath `
  -starterAdditionalFiles $additionalFiles `
  -bootstrapModuleOverrideFolderPath $bootstrapPath `
  -output (Join-Path $root "output")
