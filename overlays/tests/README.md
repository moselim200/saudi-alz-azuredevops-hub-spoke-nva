# Hub-spoke source regression

The bootstrap stages `hub_spoke_nva.tftest.hcl` into the generated platform root.
After initialization, `terraform test -no-color` runs a mocked plan using
synthetic subscription IDs and the active platform inputs. The test exercises
the actual hub-spoke module and its local Saudi DNS dependency. Provider and
regional lookups are mocked; telemetry and management-group creation are
disabled in the test only.

It checks topology selection, the Saudi/UAE policy settings, actual final Backup
zone naming, absent excluded services, NVA input/route-table wiring and Bastion
zone consistency. It does not allocate or exercise an NVA or test live policies,
RBAC, service entitlement, capacity or packet inspection.

Use the ordinary Terraform executable and generated module root, not this
overlay directory:

```powershell
& $tf "-chdir=$PWD\output\starter\v17.7.0\platform_landing_zone" test -no-color
if ($LASTEXITCODE -ne 0) { throw 'Mocked platform regression failed.' }
```

Keep any tests inherited from the pinned starter. The separate
`tests\Test-Launcher.ps1` in the source package tests the launcher with a scratch
copy and a stubbed `Deploy-Accelerator`; it never deploys.
