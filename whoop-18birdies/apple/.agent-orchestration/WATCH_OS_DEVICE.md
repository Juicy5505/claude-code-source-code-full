# Watch OS vs device

**Checked:** 2026-08-21  
**Device:** Alex’s Apple Watch — **watchOS 10.6.2**

## Project minimum

| Source | Value |
|--------|--------|
| `project.yml` → `options.deploymentTarget.watchOS` | **9.0** |
| `project.yml` → target `WhoopGolfWatch.deploymentTarget` | **9.0** |
| `WhoopGolf.xcodeproj` → `WATCHOS_DEPLOYMENT_TARGET` (Debug & Release) | **9.0** |

No Watch Swift sources use `@available(watchOS …)` / `#available` gates that raise the floor above 9.0.

## Verdict

**10.6.2 is OK.** Device OS satisfies the project minimum (9.0). No pbxproj / project.yml change required for OS compatibility.

## Alex action

None for OS version. If Watch install still fails, look elsewhere (pairing, signing / Personal Team, Trust / Developer Mode after reboot) — not a deployment-target mismatch.
