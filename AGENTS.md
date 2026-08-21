## Learned User Preferences

- Cursor Mixpanel and ZoomInfo marketplace plugins auto-open Chrome OAuth; keep them disabled and do not re-enable auto-connect.
- Treat Whoop Golf as the single golfer-facing iPhone app; fold Whoop Swing / WHOOP IMU into it instead of shipping a second competing golf icon.
- Wearable priority is Apple Watch (pivoted 2026-08-21 from WHOOP live IMU): build the Watch companion into `whoop-18birdies/apple/WhoopGolf.xcodeproj`, not a second golf icon or Kit A install.
- Use phone GPS for yardage/location; Apple Watch for heart rate, motion/swing, on-wrist path guidance, golf improver, and yardage display; WHOOP delayed-import remains optional.
- Wear the Watch on the right (trail) hand when golfing, not the left/lead hand.
- Do not install new MCP servers, and do not authenticate Mixpanel or ZoomInfo.
- Do not commit Apple team IDs or WHOOP ingest tokens, and do not record those secrets in vault notes.

## Learned Workspace Facts

- Whoop Golf iOS lives in `whoop-18birdies/apple/WhoopGolf.xcodeproj` (Claude + Codex); home-screen name WHOOP Golf; bundle ID `com.alex.whoopgolf`.
- Whoop Swing sidecar (Kit C, BLE IMU) is `whoop-18birdies/sidecar/` (`WhoopSwingSidecar`, `com.whoopgolf.sidecar`); it should merge into Golf rather than remain a second product.
- Watch-only Kit A (`whoop-18birdies/watch/WhoopGolf.xcodeproj`) is not the golfer-facing install target; the Watch companion belongs in the apple/ WhoopGolf project (WhoopGolfWatch / WatchSupport).
- The active integration branch is `claude/whoop-18birdies-integration-n630ma`.
- `wb serve` is the local Mac ingest/bridge for the golf/WHOOP pipeline on port 8790 (LAN only).
- `whoop-18birdies/setup-mac-xcode.sh` may be missing; Kit A/C setup uses the watch/sidecar build scripts instead.
- Project decisions live in the Obsidian vault under `10 Projects/Whoop Golf Companion/`; record the 2026-08-21 Apple Watch wearable pivot as a new dated decision rather than silently rewriting D15.
- iOS apps are Personal Team signed; after a phone reboot they can show as unavailable until Developer Mode / Trust is confirmed again.
- WHOOP 5 firmware refuses live raw IMU (TOGGLE_IMU / Arming); the supported 5.0 motion path is delayed import / Check for WHOOP swings (historical offload), not a live stream.
