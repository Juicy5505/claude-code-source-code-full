# D19 — Hybrid maximize-both (Watch + WHOOP) — both required

Date: 2026-08-21  
Status: Active product decision  
Supersedes for wearable priority: live WHOOP IMU (see D18 history; do not delete)  
Related: D15 modes retained as **diagnostic** only; D16 graphify control loop

## Decision

Ship **one** golfer-facing app that maximizes **both**, and **requires both** for new rounds:

1. **Apple Watch Series 5** on the **trail (right)** wrist — live motion, path score + explanation, improver, HR, on-wrist face
2. **WHOOP 5.0** — delayed historical swing import + readiness/recovery/strain; refuse live Arming hang
3. **iPhone GPS** — swing-to-swing shot yards only

Admission API: `DualWearableRequirement` — Watch-only / WHOOP-only / manual are **not startable**.

## Comprehensive tracking (shipped by decision)

Club-in-hand · path score/explanation · ball-start tendency (not radar) · attack feel · Hybrid fusion caption · Overview health glass · Obsidian App Overview

## Non-goals

- Second golf home-screen icon
- Live WHOOP raw IMU as the primary golf path on firmware 5.0
- Inventing green F/M/B from Apple Maps facility search
- Secrets in vault notes
