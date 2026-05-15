# Photon Fusion Godot Network Diagnostics

Living debug log for the Photon Fusion 3 for Godot shared-authority test project.
Keep this file updated until the lag/cadence cause is found. If no solution is found,
this should become the report sent to Photon/Fusion developers.

Last updated: 2026-05-15 08:00 PDT

## Project Context

- Project: `C:\Programming_Files\Shilocity\VirtuCadePrototype`
- Engine: Godot `4.6.2.stable.official.71f334935`
- Renderer: OpenGL 3.3 Compatibility, NVIDIA RTX 3070 Ti
- Photon Fusion Godot SDK: `3.0.0.1973`, protocol `8`
- Topology: Shared Authority
- Guide used: https://doc.photonengine.com/fusion-godot/current/getting-started/quick-start-guide
- Official starter sample checked: `C:\Users\shilo\Downloads\photon-fusion-godot-starter_3.0.0.407-2`

## Current Diagnostic Project State

Files currently modified for diagnostics:

- `core/network/network_manager/network_manager.gd`
- `world/player/player.gd`
- `world/player/player.tscn`
- `project.godot`

Current important runtime/test settings:

- `RoomSendRate = 30`
- `ClientSendRate = 30`
- `AuthoritySendRate = 30`
- `DefaultPriority = 2`
- `FusionSharedReplicator.update_interval = 1`
- `FusionSharedReplicator.root_replication_mode = AUTO`
- `FusionSharedReplicator.root_smoothing = true`
- `FusionSharedReplicator.root_smooth_time = 0.08`
- `FusionSharedReplicator.root_snap_distance = 100.0`
- `FusionSharedReplicator.root_min_position_error = 0.1`
- Current confirmed two-player movement baseline: `FusionSharedReplicator.interest_mode = 0`, no `FusionInterestArea` node, root smoothing enabled.

The interest-area setup has been run successfully twice at `RoomSendRate = 60`. It repeatedly improved raw cadence from about 15-16 visible changes/sec to about 30-32 visible changes/sec, but with a large bandwidth increase. At `RoomSendRate = 30`, `base_send_rate = 1` mostly produced about 20-21 raw visible changes/sec and about 60-67 kbps/client with smoothing off. `base_send_rate = 0` and `base_send_rate = 2` were both worse, mostly around 10-11 visible changes/sec. With smoothing on and `base_send_rate = 1`, visible remote motion reached render cadence, usually 60 changes/sec, but bandwidth stayed high at roughly 61-72 kbps/client. With smoothing on and area interest disabled/removed, visible remote motion still reached render cadence while bandwidth dropped to hundreds of bps in the tiny two-player test. This does not mean area interest should be avoided in production; production-scale area interest is still expected for culling many players/objects. It only means this specific `base_send_rate = 1` setup is not justified as a brute-force fix for player-root movement in a two-player close-range test.

Speed sensitivity is now confirmed: faster local movement does not make default 30 Hz/no-area root replication update more often. With smoothing disabled, `100 px/sec`, `200 px/sec`, and `500 px/sec` all stayed around 10-11 raw visible remote updates/sec. The only consistent change was larger jumps per update: about 9 px, 18 px, and 42-45 px respectively. This rules out the earlier theory that the original 100 px/sec movement was too small to trigger frequent updates.

## Original Symptom

With two local clients connected to the same Photon room, remote player movement looked very choppy. With smoothing disabled for diagnosis, the remote player appeared to update at roughly 10-16 visible changes per second, even when Godot itself was rendering at 60 FPS.

The user compared the visual result to intentionally capping Godot to 10 FPS and observed a similar feel.

## Earlier Spawning Finding

Initial issue: only one player instance appeared on each client.

Finding:

- The player needed root transform replication enabled on the `FusionSharedReplicator`.
- `root_replication_mode = AUTO` fixed remote player spawning/visibility.

Status: solved.

## Official Sample Comparison

The Photon starter sample is 3D, so its exact tuning may not translate directly to pixel art/2D. Still, useful comparisons:

- Player scenes use `FusionSharedReplicator`.
- Player scenes set `root_replication_mode = 1` / `AUTO`.
- The sample generally leaves smoothing/interpolation defaults alone.
- Sample player scripts disable Godot physics interpolation on remote player roots:

```gdscript
if not replicator.has_authority():
    physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
```

In this project, global Godot physics interpolation is already off, so that line is currently defensive/redundant.

## Key Log Evidence

### Godot Runtime Is Not The Limiter

Repeated logs show:

- `fps = 60`
- `physics_ticks_per_sec ~= 60`
- `Engine.max_fps = 0`
- `application/run/max_fps = 0`
- `physics/common/physics_interpolation = false`
- `low_processor_mode = false`

Conclusion:

Godot FPS, physics tick rate, background focus throttling, and global physics interpolation are not the primary cause of the raw 15 Hz remote transform cadence.

### Fusion Room Config Is Being Applied

The room join request includes:

```text
RoomSendRate: 60
ClientSendRate: 60
AuthoritySendRate: 60
DefaultPriority: 2
```

Fusion confirms:

```text
Fusion config applied: ... "AuthoritySendRate":60, "ClientSendRate":60, "RoomSendRate":60 ...
```

Conclusion:

The room send-rate override is accepted by Fusion. The problem is not that the room silently stayed at the default 30 Hz.

### Raw Remote Transform Cadence

During clean horizontal movement at `SPEED = 100 px/sec`, smoothing disabled:

Typical logs:

```text
remote_pos_changes_per_sec=15.9
avg_change_ms=64-67
avg_step_px=5.9-6.7
```

Interpretation:

- 60 room sends/sec with every 4th visible update gives 15 visible updates/sec.
- At 100 px/sec, 15 Hz gives about 6.67 px per step.
- This matches the observed `avg_step_px`.
- With a default 30 Hz room send rate, the same pattern would become about 7.5 visible updates/sec, matching the user's original "looks like about 10 FPS" impression.

Conclusion:

The symptom is deterministic and cadence-shaped. It looks more like Fusion scheduling/throttling/replication behavior than bandwidth starvation or random packet loss.

## Tests Already Run

### Test: `update_interval`

Finding:

- Previous `update_interval = 6` was a real throttle.
- Changing to `update_interval = 1` improved motion.
- However, remote movement still clustered around 15-16 visible changes/sec at `RoomSendRate = 60`.

Conclusion:

`update_interval = 6` was a problem, but fixing it did not fully solve the cadence issue.

### Test: `RoomSendRate = 60`

Finding:

- Config applied successfully.
- Motion looked smoother than default.
- Raw remote visible transform changes still clustered around 15-16/sec.

Conclusion:

Increasing room rate improves the visible symptom, but production should not require 60 ticks/s just to get acceptable movement. The underlying lower effective cadence still needs explanation.

### Test: `DefaultPriority = 1`

Why tested:

- At 60 Hz, the observed 15 Hz cadence looked like every 4th tick.
- `DefaultPriority = 2` in Fusion config looked suspicious.

Finding:

- `DefaultPriority = 1` was accepted by Fusion.
- Cadence did not meaningfully improve.

Conclusion:

`DefaultPriority` is probably not the direct cause, or at least `1` is not the correct knob for this symptom.

### Test: `root_min_position_error = 0.1`

Why tested:

- Hidden GDExtension metadata exposed `root_min_position_error` in pixels.
- It was not visible in docs/exports, so it was verified with an isolated Godot probe.

Probe result:

```text
has_getter=true
default_value=1.0
after_method_set=0.1
after_property_set=0.2
scene_value=0.1
```

Finding:

- The property is real and `.tscn` can set it.
- Runtime logs confirmed `min_position_error=0.1`.
- Clean horizontal movement still clustered around 15-16 visible changes/sec.

Conclusion:

This hidden threshold may still be useful for pixel-art precision, but it is not the main cause of the 15 Hz cadence.

### Test: `FusionInterestArea.base_send_rate = 1`

Why tested:

- Global/default root replication at `RoomSendRate = 60` produced only about 15-16 visible remote changes/sec.
- `FusionInterestArea.base_send_rate` is the only exposed per-area send-rate override found in the GDExtension metadata.

Test setup:

- `RoomSendRate = 60`
- `ClientSendRate = 60`
- `AuthoritySendRate = 60`
- `DefaultPriority = 2`
- `root_smoothing = false`
- `interest_mode = AREA`
- `FusionInterestArea.base_send_rate = 1`
- `FusionInterestArea.decay_mode = FLAT`
- `FusionInterestArea.orientation = 2D`

Runtime confirmation:

```text
interest_mode=1
[PlayerDiag] interest_area ... base_send_rate=1 decay_mode=0 enabled=true
```

Finding:

- Clean horizontal movement improved from about 15-16 visible remote changes/sec to about 29-32 visible remote changes/sec.
- Typical improved logs:

```text
remote_pos_changes_per_sec=29.3
avg_change_ms=36.2
avg_step_px=3.08

remote_pos_changes_per_sec=31.2
avg_change_ms=32.3
avg_step_px=3.04

remote_pos_changes_per_sec=32.2
avg_change_ms=31.8
avg_step_px=3.1
```

- At `SPEED = 100 px/sec`, a 30-32 Hz cadence predicts about 3.1-3.3 px per step, matching the logs.
- Outbound bandwidth jumped from roughly hundreds/low-thousands of bits/sec to roughly 112,000-142,000 bits/sec per client in this tiny two-player scene.
- Confirmation repeat reproduced the same result:

```text
remote_pos_changes_per_sec=29.8
avg_change_ms=31.6
avg_step_px=3.03
sent_bps=127073.4

remote_pos_changes_per_sec=31.7
avg_change_ms=31.7
avg_step_px=3.1
sent_bps=126281.4

remote_pos_changes_per_sec=32.2
avg_change_ms=31.5
avg_step_px=3.08
sent_bps=131373.9
```

Conclusion:

This is the first test that materially changed the raw cadence. The 15 Hz issue is strongly tied to Fusion interest/send-rate scheduling, not network speed, Godot FPS, physics interpolation, `DefaultPriority`, or `root_min_position_error`.

However, the bandwidth increase is too large to accept blindly. The interest-area send-rate setting is a promising cause/solution path, but it needs production tuning.

### Test: Network Probes

Commands/probes run from this machine:

- `ping -n 20 1.1.1.1`
- `ping -n 20 ns.exitgames.com`
- `tracert -d -h 12 ns.exitgames.com`
- `Test-NetConnection app-us.exitgamescloud.com -Port 443`
- `Test-NetConnection app-us.exitgamescloud.com -Port 4530`
- Small Cloudflare download test

Results:

- `1.1.1.1`: about 15 ms average, 0% loss
- Photon name server: about 16 ms average, 0% loss
- Route to Photon name server was clean
- Small download test: about 170 Mbps
- `app-us.exitgamescloud.com` blocks ICMP ping, but TCP `443` and `4530` connect
- Fusion in-game RTT to the room is around 95-100 ms

Conclusion:

Bandwidth is not the cause. The traffic in Fusion logs is only hundreds to roughly 1600 bits/sec, which is tiny.

Latency can add visible delay, especially with smoothing/interpolation, but a stable 95 ms RTT does not explain a deterministic 15-16 Hz visible update cadence by itself. Network congestion/packet loss would normally produce irregular gaps and spikes, not a clean ~64 ms cadence during steady horizontal movement.

## Red Herrings / Low Probability Causes

- Godot render FPS: stable around 60
- Godot physics FPS: stable around 60
- Godot max FPS cap: currently not capped
- Godot low processor mode: off
- Global physics interpolation: already off
- Remote `physics_ticks_per_sec = 0`: expected because remote physics processing is disabled
- `remote_pos_changes_per_sec = 0` while the remote object is idle: expected
- `network_delta = 2.0`: just our diagnostic print interval
- Photon app host ICMP ping timeout: app host blocks ping; TCP connects
- User internet bandwidth: enough headroom by multiple orders of magnitude

## Still Plausible Causes

### 1. Fusion Root Replication Send Scheduling / Interest Send Rate

Strongly supported by the interest-area test.

The remote root transform appears to visibly change around every 4 room ticks when `RoomSendRate = 60` under default/global interest behavior. Adding `FusionInterestArea.base_send_rate = 1` increased cadence to about 30-32 visible changes/sec.

Current active follow-up test:

- `RoomSendRate = 30`
- `interest_mode = 0`
- no `FusionInterestArea` node
- `root_smoothing = true`
- `root_smooth_time = 0.08`
- `root_snap_distance = 100.0`

Goal:

Confirmed: the clean smoothing-only setup behaves the same after removing the unused interest-area node.

### 2. Float Compression / Quantization

Still plausible.

Current runtime log shows:

```text
float_compression=0
```

Project setting hint from Fusion metadata:

```text
High,Mid,Low
```

If `0 = High`, then 2D pixel-art movement may expose quantization more severely than the 3D starter sample. However, the cadence is very regular, so this is currently behind send scheduling in likelihood.

Possible next tests:

- Change `fusion/serialization/float_compression` from High to Mid/Low.
- Keep all other variables fixed.
- Compare `remote_pos_changes_per_sec`, `avg_change_ms`, and `avg_step_px`.

### 3. Region / RTT

Fusion room RTT is around 95-100 ms even though the Photon name server ping is around 16 ms.

This may be because:

- the actual game server path differs from the name server path,
- Photon Cloud routing differs by region/cluster,
- ICMP and game traffic differ,
- the room is not in the nearest practical game-server location,
- or `us` is not the best region for this machine.

Possible next test:

- Set `fusion/connection/default_region` to `best`, or connect using best-region mode if exposed by the API.
- Compare Fusion `rtt`.

Expected:

This may reduce perceived delay, but it is not expected to fix the 15 Hz cadence by itself.

### 4. Smoothing Disabled During Diagnosis

Important context:

`root_smoothing=false` is useful for diagnosing raw update cadence, but it is not a production target.

Official Photon docs state that typical network replication is around 30/sec and smooth 60 FPS presentation comes from render-frame interpolation/smoothing:

https://doc.photonengine.com/fusion-godot/current/fusion-intro

Production tuning will likely need smoothing back on. However, if raw updates are effectively 7.5-15 Hz, smoothing has to hide too much and can feel laggy.

## Next Test Plan

### Test A: Interest Area Send Rate

Status: completed at `RoomSendRate = 60`.

Expected ready logs:

```text
interest_mode=1
[PlayerDiag] interest_area ... base_send_rate=1
```

Run two fresh clients, move one player horizontally at constant speed, and record:

```text
remote_pos_changes_per_sec
avg_change_ms
avg_step_px
min_step_px
max_step_px
```

Decision:

- Cadence rose above ~16/sec to roughly 30-32/sec.
- Interest/send scheduling is now the strongest confirmed cause path.
- Bandwidth increased sharply and needs follow-up tuning.

### Test A2: Interest Area At 30 Hz Room Send Rate

Status: completed with `base_send_rate = 1`.

Expected room config:

```text
RoomSendRate: 30
ClientSendRate: 30
AuthoritySendRate: 30
```

Expected ready logs:

```text
interest_mode=1
[PlayerDiag] interest_area ... base_send_rate=1
```

Run two fresh clients, move one player horizontally at constant speed, and record:

```text
remote_pos_changes_per_sec
avg_change_ms
avg_step_px
sent_bps
recv_bps
```

Decision:

- Cadence did not stay near 30/sec.
- It mostly stabilized around 20-21 visible remote changes/sec during horizontal movement, with occasional lower/higher windows depending on jumps/stops.
- Bandwidth dropped compared with the 60 Hz interest-area test, but was still high for a tiny two-player scene.

Representative logs:

```text
RoomSendRate=30
base_send_rate=1

remote_pos_changes_per_sec=15.9
avg_change_ms=61.8
avg_step_px=4.64
sent_bps=63219.4

remote_pos_changes_per_sec=20.8
avg_change_ms=49.6
avg_step_px=5.46
sent_bps=63917.1

remote_pos_changes_per_sec=21.3
avg_change_ms=48.0
avg_step_px=5.34
sent_bps=67122.0

remote_pos_changes_per_sec=20.8
avg_change_ms=49.2
avg_step_px=4.56
sent_bps=67287.9
```

Bandwidth attribution note:

The bandwidth increase is not explained by raw update frequency alone. The no-area two-player baseline later measured moving-client outbound traffic around 599-622 bps, while area interest with `base_send_rate = 1` measured about 63-67 kbps in this raw 30 Hz test. Raw visible updates rose from roughly 10-11/sec to roughly 20-21/sec, about a 2x increase. If payload size stayed similar, a 2x update-rate increase would predict roughly 2x bandwidth, not roughly 100x. Also, `base_send_rate = 0` and `base_send_rate = 2` still stayed in the same rough 60-77 kbps range while producing worse 10-11/sec cadence. That suggests most of the extra bandwidth comes from the explicit area-interest path / area configuration / payload behavior, not merely from sending twice as many root transforms.

Conclusion:

At `RoomSendRate = 30`, explicit area interest with `base_send_rate = 1` is better than the original low-cadence behavior, but it does not provide a clean raw 30 Hz visible cadence. It may still be acceptable once smoothing is enabled, but it is not a complete raw-cadence fix.

### Test A3: Map `base_send_rate = 0` At 30 Hz

Status: completed.

Expected room config:

```text
RoomSendRate: 30
ClientSendRate: 30
AuthoritySendRate: 30
```

Expected ready logs:

```text
interest_mode=1
[PlayerDiag] interest_area ... base_send_rate=0
```

Run two fresh clients, move one player horizontally at constant speed, and record:

```text
remote_pos_changes_per_sec
avg_change_ms
avg_step_px
sent_bps
recv_bps
```

Decision:

- `base_send_rate = 0` is worse than `base_send_rate = 1`.
- It mostly dropped cadence to about 10-11 visible remote changes/sec during horizontal movement.
- Step sizes rose to roughly 9-10 px during constant 100 px/sec movement.
- Bandwidth did not improve enough to justify the cadence loss; it stayed in the same rough 60-70 kbps/client range.

Representative logs:

```text
RoomSendRate=30
base_send_rate=0

remote_pos_changes_per_sec=10.4
avg_change_ms=99.2
avg_step_px=9.37
sent_bps=69000.5

remote_pos_changes_per_sec=10.9
avg_change_ms=97.6
avg_step_px=9.24
sent_bps=65549.3

remote_pos_changes_per_sec=10.4
avg_change_ms=98.3
avg_step_px=9.29
sent_bps=64639.9

remote_pos_changes_per_sec=10.9
avg_change_ms=98.4
avg_step_px=9.24
sent_bps=66451.7
```

Conclusion:

`base_send_rate = 0` is not a better diagnostic profile for improving raw player-root cadence. Restore or move above `base_send_rate = 1`.

### Test A4: Map `base_send_rate = 2` At 30 Hz

Status: completed.

Expected room config:

```text
RoomSendRate: 30
ClientSendRate: 30
AuthoritySendRate: 30
```

Expected ready logs:

```text
interest_mode=1
[PlayerDiag] interest_area ... base_send_rate=2
```

Run two fresh clients, move one player horizontally at constant speed, and record:

```text
remote_pos_changes_per_sec
avg_change_ms
avg_step_px
sent_bps
recv_bps
```

Decision:

- `base_send_rate = 2` did not improve cadence over `base_send_rate = 1`.
- It behaved much closer to `base_send_rate = 0`, mostly around 10-11 visible changes/sec during clean horizontal movement.
- Step sizes were roughly 8-10 px during 100 px/sec movement.
- Bandwidth stayed high, roughly 62-77 kbps/client in the representative windows.

Representative logs:

```text
RoomSendRate=30
base_send_rate=2

remote_pos_changes_per_sec=10.9
avg_change_ms=98.5
avg_step_px=9.39
sent_bps=76394.6

remote_pos_changes_per_sec=10.4
avg_change_ms=98.3
avg_step_px=9.37
sent_bps=70758.4

remote_pos_changes_per_sec=10.9
avg_change_ms=98.4
avg_step_px=9.47
sent_bps=62153.0

remote_pos_changes_per_sec=10.4
avg_change_ms=99.2
avg_step_px=8.41
sent_bps=63637.2
```

Conclusion:

`base_send_rate = 2` is not a better diagnostic profile for improving raw player-root cadence. The useful mapped setting is currently `base_send_rate = 1`.

### Test B: Speed Scaling

Temporarily increase `SPEED` from `100` to `300` while keeping smoothing off.

Decision:

- If `remote_pos_changes_per_sec` stays ~15-16 and `avg_step_px` grows, that supports fixed scheduler cadence.
- If `remote_pos_changes_per_sec` rises significantly, that supports quantization/threshold/compression.

### Test C: Float Compression

Change `fusion/serialization/float_compression` from High to Mid/Low and repeat the constant horizontal movement test.

Decision:

- If `avg_step_px` drops and cadence rises, compression/quantization was involved.
- If cadence remains ~15-16, compression is not the main limiter.

### Test D: Best Region

Switch from fixed `us` region to `best` region if possible.

Decision:

- If Fusion RTT drops, keep best-region selection or choose a better explicit region.
- If RTT remains ~95 ms, document it for Photon.
- Regardless, do not treat RTT as the cause of the deterministic 15 Hz cadence unless cadence changes too.

### Test E: Production Smoothing Pass

Status: completed with area interest enabled.

Setup:

- `RoomSendRate = 30`
- `ClientSendRate = 30`
- `AuthoritySendRate = 30`
- `interest_mode = AREA`
- `FusionInterestArea.base_send_rate = 1`
- `root_smoothing = true`
- `root_smooth_time = 0.08`
- `root_snap_distance = 100.0`
- `root_min_position_error = 0.1`

Important interpretation note:

With smoothing enabled, `remote_pos_changes_per_sec` no longer represents raw network packet cadence. It may rise because the visible root is now being moved locally between network snapshots. For this test, judge visual smoothness, added delay, snapping, and bandwidth. If it still feels laggy, tune `root_smooth_time`, `root_snapshot_delay`, `root_max_delay`, and possibly consider a custom interpolation path.

Result:

- The settings loaded correctly on both local and remote player instances.
- Visible remote transform updates usually reached render cadence, around 60 changes/sec.
- Clean horizontal movement typically had `avg_change_ms ~= 16.8` and `avg_step_px ~= 1.1-1.9`.
- Outbound bandwidth remained high for a tiny two-player scene, roughly 61-72 kbps/client.
- Fusion RTT stayed around 102-108 ms.

Representative logs:

```text
root_smoothing=true smooth_time=0.08 snap_distance=100.0
interest_mode=1
base_send_rate=1

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.89
sent_bps=68511.9

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.58
sent_bps=72160.3

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.57
sent_bps=71234.4

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.4
sent_bps=65348.0
```

Conclusion:

This is the first configuration that objectively produces 60 FPS visible remote transform motion at `RoomSendRate = 30`. It may be a viable feel solution if the user judged it smooth enough. However, the bandwidth cost is high in this two-player close-range test, so this profile should not be treated as the final production interest design.

### Test F: Smoothing Without Area Interest

Status: completed.

Setup:

- `RoomSendRate = 30`
- `ClientSendRate = 30`
- `AuthoritySendRate = 30`
- `interest_mode = 0`
- `FusionInterestArea.enabled = false`
- `root_smoothing = true`
- `root_smooth_time = 0.08`
- `root_snap_distance = 100.0`
- `root_min_position_error = 0.1`

Expected ready logs:

```text
interest_mode=0
root_smoothing=true
smooth_time=0.08
snap_distance=100.0
```

The `FusionInterestArea` diagnostic may still print because the node remains in the scene, but it should show `enabled=false` and should be ignored by the replicator while `interest_mode=0`.

Decision:

- Motion still reached render cadence during clean movement.
- Bandwidth dropped sharply, from roughly 61-72 kbps/client in the area-interest smoothing test to hundreds of bps/client.
- This strongly indicates the simple two-player root-transform movement baseline does not need explicit area interest.
- This does not evaluate production-scale interest management, where area interest is still expected for culling many players/objects.

Result:

- Ready logs confirmed `interest_mode=0`, `root_smoothing=true`, `smooth_time=0.08`, `snap_distance=100.0`, and `FusionInterestArea.enabled=false`.
- Clean horizontal movement often reached `remote_pos_changes_per_sec=60.0`.
- Typical visible smoothing cadence was `avg_change_ms ~= 16.8`.
- Typical visible step size was `avg_step_px ~= 1.4-1.6` during 100 px/sec movement.
- Moving-client outbound bandwidth was usually about 580-642 bps.
- Idle/non-moving-client outbound bandwidth was usually about 209-298 bps.
- This is about two orders of magnitude lower than the area-interest smoothing test.

Representative logs:

```text
interest_mode=0
root_smoothing=true
smooth_time=0.08
snap_distance=100.0
FusionInterestArea.enabled=false

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.58
sent_bps=592.0
recv_bps=123.3

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.62
sent_bps=621.0
recv_bps=128.0

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.45
sent_bps=612.0
recv_bps=128.3

remote_pos_changes_per_sec=59.5
avg_change_ms=16.9
avg_step_px=1.37
sent_bps=450.6
recv_bps=121.5
```

Conclusion:

This is the current best two-player movement baseline. The original bad-looking motion was not caused by the network, Godot FPS, or bandwidth. It was primarily exposed by testing with smoothing disabled. Explicit area interest changes raw cadence but caused a huge bandwidth spike in this tiny close-range test, where there was nothing useful to cull. That result should not be read as an argument against production area interest.

### Test G: Clean Smoothing-Only Scene

Status: completed.

Setup:

- `RoomSendRate = 30`
- `ClientSendRate = 30`
- `AuthoritySendRate = 30`
- `interest_mode = 0`
- no `FusionInterestArea` node
- `root_smoothing = true`
- `root_smooth_time = 0.08`
- `root_snap_distance = 100.0`
- `root_min_position_error = 0.1`

Expected ready logs:

```text
interest_mode=0
root_smoothing=true
smooth_time=0.08
snap_distance=100.0
```

Expected difference from Test F:

There should be no `interest_area` diagnostic line because the node has been removed.

Decision:

- Motion and bandwidth matched Test F.
- Removing the disabled `FusionInterestArea` node did not harm smoothing or increase bandwidth.
- Accept this as the current two-player movement baseline for the simple root-transform case.

Result:

- Ready logs confirmed `interest_mode=0`, `root_smoothing=true`, `smooth_time=0.08`, and `snap_distance=100.0`.
- No `interest_area` diagnostic line appeared, confirming the node was removed.
- Clean horizontal movement repeatedly reached `remote_pos_changes_per_sec=60.0`.
- Typical visible smoothing cadence was `avg_change_ms ~= 16.8`.
- Typical clean horizontal step size was `avg_step_px ~= 1.49-1.62` during 100 px/sec movement.
- Moving-client outbound bandwidth was typically about 599-668 bps, with a few windows around 768 bps.
- Idle/non-moving-client outbound bandwidth was usually about 209-306 bps.
- Some mixed movement/jump/large correction windows showed large `max_step_px` values. These do not contradict the steady horizontal result; they are movement-event/correction windows, not the baseline cadence.

Representative clean horizontal logs:

```text
interest_mode=0
root_smoothing=true
smooth_time=0.08
snap_distance=100.0

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.58
sent_bps=606.3
recv_bps=125.7

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.53
sent_bps=636.7
recv_bps=129.5

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.49
sent_bps=625.8
recv_bps=127.2

remote_pos_changes_per_sec=60.0
avg_change_ms=16.8
avg_step_px=1.62
sent_bps=599.4
recv_bps=120.8
```

Conclusion:

Confirmed current two-player movement baseline:

- `RoomSendRate = 30`
- `ClientSendRate = 30`
- `AuthoritySendRate = 30`
- `FusionSharedReplicator.update_interval = 1`
- `FusionSharedReplicator.root_replication_mode = AUTO`
- `FusionSharedReplicator.interest_mode = 0`
- no `FusionInterestArea`
- `root_smoothing = true`
- `root_smooth_time = 0.08`
- `root_snap_distance = 100.0`
- `root_min_position_error = 0.1`

The original visual lag was primarily caused by evaluating raw replicated root updates with smoothing disabled. Built-in smoothing provides render-cadence presentation at a production-shaped 30 Hz send rate without using explicit area interest as a player-root cadence fix in this tiny test. Production-scale area interest should still be designed separately for culling many players/objects.

## Confirmation Matrix: Profile-Based Retests

Status: ready to run.

Current active profile after the speed tests: `Profile.PRODUCTION_BASELINE`.

To avoid hand-mixing settings, network test profiles now live in:

```text
core/network/network_test_profile.gd
```

Change only this line before each run:

```gdscript
const ACTIVE_PROFILE := Profile.PRODUCTION_BASELINE
```

The room name is automatically changed to `lobby_<profile_id>`, so each profile gets a fresh room config after both clients restart. Run both clients from the same project copy after changing the active profile.

For each profile:

- Fully stop both clients before switching profiles.
- Start both clients and confirm both logs print the same `[NetDiag] test_profile=...`.
- Move one player horizontally at steady speed for at least 10 seconds.
- Avoid mixing jumps, teleports, collisions, or room joins into the clean horizontal sample.
- Capture at least three `[PlayerDiag]` windows for the remote moving player.
- Record `remote_pos_changes_per_sec`, `avg_change_ms`, `avg_step_px`, `sent_bps`, `recv_bps`, and subjective feel.

Recommended run order:

Speed sensitivity check:

1. `Profile.RAW_DEFAULT_SPEED_1X`
   - Purpose: current 100 px/sec speed.
   - Settings: 30/30/30 send rates, priority 2, update interval 1, no area interest.
   - Diagnostic-only change: `root_smoothing = false` so `remote_pos_changes_per_sec` reflects raw visible root updates instead of smoothed presentation.

2. `Profile.RAW_DEFAULT_SPEED_2X`
   - Purpose: 200 px/sec speed.
   - Same settings as `RAW_DEFAULT_SPEED_1X`; only player speed changes.

3. `Profile.RAW_DEFAULT_SPEED_5X`
   - Purpose: 500 px/sec speed.
   - Same settings as `RAW_DEFAULT_SPEED_1X`; only player speed changes.

How to read the speed test:

- If speed does not affect raw sync rate, `remote_pos_changes_per_sec` should stay in the same rough range across 1x/2x/5x.
- `avg_step_px` should grow with speed because each received update covers more distance.
- `avg_remote_speed` should roughly match 100/200/500 px/sec during clean horizontal movement.
- If faster movement changes raw sync rate, it will show up as a clear change in `remote_pos_changes_per_sec` and `avg_change_ms`, not just larger steps.

Original broader factor run order:

1. `Profile.PRODUCTION_BASELINE`
   - Confirms the current winner still holds after adding the profile harness.
   - Expected: visible cadence near 60/sec, `avg_change_ms ~= 16.8`, low hundreds of bps idle, roughly hundreds of bps while moving.

2. `Profile.BEST_CASE_ATTEMPT`
   - Combined best-case attempt.
   - Changes: `RoomSendRate/ClientSendRate/AuthoritySendRate = 60`, `root_smooth_time = 0.05`, no area interest.
   - Question: Does higher send rate plus tighter smoothing feel better than baseline without meaningful bandwidth cost?

3. `Profile.WORST_CASE_ATTEMPT`
   - Combined worst-case attempt.
   - Changes: `update_interval = 6`, `root_smoothing = false`.
   - Question: Does this recreate obvious visible chunkiness and confirm the earlier failure mode?

4. `Profile.RATE_60_ONLY`
   - One-factor test.
   - Changes only rates from 30 to 60.
   - Question: Does send rate alone improve feel, bandwidth, or correction behavior when smoothing remains at 0.08?

5. `Profile.SMOOTHING_OFF_ONLY`
   - One-factor test.
   - Changes only `root_smoothing = false`.
   - Question: Does disabling smoothing expose the raw cadence/chunkiness again under production rates?

6. `Profile.SMOOTH_TIME_005_ONLY`
   - One-factor test.
   - Changes only `root_smooth_time = 0.05`.
   - Question: Is it more responsive without visible stutter or snapping?

7. `Profile.SMOOTH_TIME_015_ONLY`
   - One-factor test.
   - Changes only `root_smooth_time = 0.15`.
   - Question: Is it visually smoother but too delayed?

8. `Profile.SNAP_DISTANCE_5_ONLY`
   - One-factor test.
   - Changes only `root_snap_distance = 5.0`.
   - Question: Do normal corrections begin snapping or producing visible discontinuities?

9. `Profile.UPDATE_INTERVAL_6_ONLY`
   - One-factor test.
   - Changes only `FusionSharedReplicator.update_interval = 6`.
   - Question: Does smoothing hide the throttle, or does it still degrade motion/latency?

10. `Profile.DEFAULT_PRIORITY_1_ONLY`
    - One-factor test.
    - Changes only `DefaultPriority = 1`.
    - Question: Confirm priority is not the important factor.

11. `Profile.AREA_INTEREST_BASE_SEND_1_ONLY`
    - Necessary paired-factor test: enables explicit area interest with `base_send_rate = 1`.
    - Everything else stays production-like.
    - Question: Confirm visible cadence remains good but bandwidth spikes compared with no area interest.

### Speed Sensitivity Result: `Profile.RAW_DEFAULT_SPEED_1X`

Status: completed.

Profile:

```text
raw_default_speed1x
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
FusionSharedReplicator.update_interval = 1
FusionSharedReplicator.interest_mode = 0
No FusionInterestArea
root_smoothing = false
Player speed = 100 px/sec
```

Clean remote moving-player windows:

```text
remote_pos_changes_per_sec=10.4 avg_change_ms=98.3 avg_step_px=8.97 avg_remote_speed=95.8
remote_pos_changes_per_sec=10.5 avg_change_ms=99.2 avg_step_px=9.29 avg_remote_speed=98.3
remote_pos_changes_per_sec=10.4 avg_change_ms=102.5 avg_step_px=9.21 avg_remote_speed=94.3
remote_pos_changes_per_sec=11.0 avg_change_ms=98.4 avg_step_px=9.02 avg_remote_speed=96.0
remote_pos_changes_per_sec=10.4 avg_change_ms=99.1 avg_step_px=8.97 avg_remote_speed=95.0
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=9.17 avg_remote_speed=97.6
remote_pos_changes_per_sec=10.4 avg_change_ms=99.2 avg_step_px=9.37 avg_remote_speed=99.2
```

Conclusion:

At 100 px/sec with default 30 Hz/no-area replication and smoothing disabled, raw visible remote updates are roughly 10-11/sec. This is the baseline for the 2x and 5x speed comparison.

### Speed Sensitivity Result: `Profile.RAW_DEFAULT_SPEED_2X`

Status: completed.

Profile:

```text
raw_default_speed2x
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
FusionSharedReplicator.update_interval = 1
FusionSharedReplicator.interest_mode = 0
No FusionInterestArea
root_smoothing = false
Player speed = 200 px/sec
```

Clean remote moving-player windows:

```text
remote_pos_changes_per_sec=10.5 avg_change_ms=99.2 avg_step_px=19.13 avg_remote_speed=202.4
remote_pos_changes_per_sec=10.4 avg_change_ms=98.3 avg_step_px=17.29 avg_remote_speed=184.7
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=17.73 avg_remote_speed=188.7
remote_pos_changes_per_sec=10.5 avg_change_ms=98.3 avg_step_px=18.10 avg_remote_speed=193.2
remote_pos_changes_per_sec=10.4 avg_change_ms=103.3 avg_step_px=18.10 avg_remote_speed=183.9
remote_pos_changes_per_sec=10.4 avg_change_ms=98.3 avg_step_px=18.26 avg_remote_speed=194.9
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=18.03 avg_remote_speed=191.9
remote_pos_changes_per_sec=10.4 avg_change_ms=98.3 avg_step_px=17.62 avg_remote_speed=188.2
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=17.42 avg_remote_speed=185.4
```

Conclusion:

Doubling player speed did not meaningfully increase raw visible remote update rate. The update rate stayed around 10-11/sec, while the average step size roughly doubled from about 9 px to about 18 px. This supports the idea that movement speed changes how large each remote jump is, not how often default/no-area root replication updates arrive.

### Speed Sensitivity Result: `Profile.RAW_DEFAULT_SPEED_5X`

Status: completed.

Profile:

```text
raw_default_speed5x
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
FusionSharedReplicator.update_interval = 1
FusionSharedReplicator.interest_mode = 0
No FusionInterestArea
root_smoothing = false
Player speed = 500 px/sec
```

Clean remote moving-player windows:

```text
remote_pos_changes_per_sec=10.9 avg_change_ms=99.2 avg_step_px=42.80 avg_remote_speed=451.9
remote_pos_changes_per_sec=10.4 avg_change_ms=98.3 avg_step_px=40.73 avg_remote_speed=435.0
remote_pos_changes_per_sec=10.4 avg_change_ms=103.3 avg_step_px=45.07 avg_remote_speed=457.9
remote_pos_changes_per_sec=10.4 avg_change_ms=99.2 avg_step_px=43.94 avg_remote_speed=465.2
remote_pos_changes_per_sec=10.9 avg_change_ms=97.6 avg_step_px=42.91 avg_remote_speed=460.4
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=44.70 avg_remote_speed=476.0
remote_pos_changes_per_sec=10.4 avg_change_ms=98.4 avg_step_px=42.46 avg_remote_speed=453.2
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=43.29 avg_remote_speed=460.8
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=43.56 avg_remote_speed=463.6
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=42.80 avg_remote_speed=455.8
```

Conclusion:

Increasing speed from 1x to 5x did not meaningfully increase raw visible remote update rate. The update rate stayed around 10-11/sec, while the average step size grew from about 9 px at 1x, to about 18 px at 2x, to about 42-45 px at 5x. Faster movement makes the raw stutter more obvious because each unsmoothed update covers more distance; it does not make default/no-area root replication send or apply updates more often.

Overall speed-test conclusion:

```text
1x / 100 px/sec: remote updates ~= 10-11/sec, avg step ~= 9 px
2x / 200 px/sec: remote updates ~= 10-11/sec, avg step ~= 18 px
5x / 500 px/sec: remote updates ~= 10-11/sec, avg step ~= 42-45 px
```

This confirms speed was not the hidden fix for the raw update-rate problem. The bottleneck is the default/no-area root replication delivery/apply rate, not that the original 100 px/sec movement was too small to trigger frequent updates.

### Confirmation Result: `Profile.BEST_CASE_ATTEMPT`

Status: completed as both a 4-client stress run and a clean 2-client comparison.

Profile:

```text
best_rate60_smooth005
RoomSendRate = 60
ClientSendRate = 60
AuthoritySendRate = 60
DefaultPriority = 2
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.05
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Important caveat:

This run had `players=4`, not the earlier 2-player baseline. Treat bandwidth as a 4-client stress sample, not a direct apples-to-apples comparison with the 2-client runs.

Clean horizontal result:

- Horizontal remote motion still reached render cadence.
- Representative clean horizontal remote samples for the moving player:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.59 avg_remote_speed=95.7
remote_pos_changes_per_sec=58.0 avg_change_ms=17.4 avg_step_px=1.63 avg_remote_speed=94.7
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.67 avg_remote_speed=100.0
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.63 avg_remote_speed=97.6
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.60 avg_remote_speed=96.1
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.59 avg_remote_speed=95.3
```

4-client bandwidth sample:

```text
sent_bps ~= 1191-1558
recv_bps ~= 900-1204
rtt ~= 0.095-0.098
```

This is much higher than the 2-client no-area-interest baseline in absolute bps because there were 4 players in the room, but it is still tiny compared with the explicit area-interest spike seen earlier at roughly 60-72 kbps/client.

Unbounded-fall artifact:

- Several clients fell indefinitely, reaching extreme vertical positions and velocities.
- Those high-speed vertical remotes degraded to about `15.9-19.3` visible changes/sec with huge step sizes.
- Representative falling samples:

```text
remote_pos_changes_per_sec=19.3 avg_change_ms=51.8 avg_step_px=128.66 velocity=(0.0, 3462.66)
remote_pos_changes_per_sec=16.4 avg_change_ms=64.6 avg_step_px=280.78 velocity=(0.0, 5488.01)
remote_pos_changes_per_sec=15.9 avg_change_ms=64.5 avg_step_px=404.76 velocity=(0.0, 7448.03)
remote_pos_changes_per_sec=15.9 avg_change_ms=64.0 avg_step_px=645.86 velocity=(0.0, 11384.3)
```

Interpretation:

The 4-client best-case stress run confirmed that increasing send rates to 60 and tightening smoothing to `0.05` preserves smooth horizontal presentation without an area-interest bandwidth explosion. It does not clearly beat the production baseline for normal 100 px/sec horizontal movement; both produce render-cadence visible motion. The unbounded-fall data is not a normal walking comparison, but it reveals a separate high-speed/correction stress case: at extreme velocities the smoother no longer presents steady 60 Hz motion and large corrections appear. That should be tested separately with realistic max fall speeds and world bounds before choosing final platformer tuning.

2-client repeat:

Status: completed.

Ready logs confirmed:

```text
test_profile=best_rate60_smooth005
rates=60/60/60
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.05
snap=100.0
min_pos_error=0.1
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.60 avg_remote_speed=96.1
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.60 avg_remote_speed=96.3
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.61 avg_remote_speed=96.6
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.60 avg_remote_speed=95.9
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.62 avg_remote_speed=96.9
```

First remote sample after spawn:

```text
remote_pos_changes_per_sec=17.4 avg_change_ms=16.7 avg_step_px=1.52 avg_remote_speed=93.9
```

That first window is not representative because the remote object was allocated partway through the 2-second diagnostic window; the average interval already showed render cadence.

2-client bandwidth sample:

```text
idle-ish client sent_bps ~= 419-432 recv_bps ~= 368-414
moving client sent_bps ~= 1202-1207 recv_bps ~= 183-199
rtt ~= 0.095-0.099
```

2-client interpretation:

The best-case profile objectively matches smooth visible movement: stable `60.0` visible changes/sec at `avg_change_ms ~= 16.8`. Compared with the current production baseline (`RoomSendRate = 30`, `smooth_time = 0.08`), it does not materially improve measured horizontal presentation, because both are already render-cadence smooth. It costs more moving-client outbound bandwidth, roughly around 1.2 kbps instead of the earlier hundreds-of-bps range, but remains nowhere near the explicit area-interest spike. This makes it a possible "slightly more responsive feel" variant, not an objectively necessary replacement for the baseline.

### Confirmation Result: `Profile.WORST_CASE_ATTEMPT`

Status: completed as a clean 2-client failure-mode confirmation.

Profile:

```text
worst_interval6_raw
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 6
interest_mode = 0
area_enabled = false
root_smoothing = false
root_smooth_time = 0.08
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=worst_interval6_raw
rates=30/30/30
update_interval=6
interest_mode=0
area_enabled=false
root_smoothing=false
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=5.0 avg_change_ms=218.5 avg_step_px=22.34 avg_remote_speed=113.6
remote_pos_changes_per_sec=5.0 avg_change_ms=218.5 avg_step_px=19.33 avg_remote_speed=98.3
remote_pos_changes_per_sec=5.0 avg_change_ms=231.5 avg_step_px=18.67 avg_remote_speed=89.6
remote_pos_changes_per_sec=5.0 avg_change_ms=218.5 avg_step_px=19.50 avg_remote_speed=99.2
```

Spawn/mixed windows:

```text
remote_pos_changes_per_sec=4.0 avg_change_ms=226.3 avg_step_px=16.82
remote_pos_changes_per_sec=2.5 avg_change_ms=233.4 avg_step_px=13.53
```

2-client bandwidth sample:

```text
moving client sent_bps ~= 281-282 recv_bps ~= 120-130
idle-ish client sent_bps ~= 209-210 recv_bps ~= 246-283
rtt ~= 0.104-0.107
```

Interpretation:

This profile intentionally recreates the visible chunkiness: about 5 visible remote changes/sec, with roughly 200+ ms between changes and large 18-22 px steps at normal 100 px/sec horizontal speed. This is a negative control showing the diagnostics can still detect a deliberately throttled failure mode.

### Confirmation Result: `Profile.RATE_60_ONLY`

Status: completed as a clean 2-client one-factor test.

Profile:

```text
factor_rate60_only
RoomSendRate = 60
ClientSendRate = 60
AuthoritySendRate = 60
DefaultPriority = 2
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.08
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_rate60_only
rates=60/60/60
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.08
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.59 avg_remote_speed=95.3
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.61 avg_remote_speed=96.5
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.63 avg_remote_speed=98.0
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.56 avg_remote_speed=93.7
```

First remote/spawn-adjacent windows:

```text
remote_pos_changes_per_sec=54.0 avg_change_ms=16.7 avg_step_px=1.95 avg_remote_speed=118.1
remote_pos_changes_per_sec=46.1 avg_change_ms=17.6 avg_step_px=0.93 avg_remote_speed=53.8
```

These early windows are not representative because remote objects were allocated and/or idle movement was mixed into the diagnostic interval. The clean horizontal windows stabilize at render cadence.

2-client bandwidth sample:

```text
idle-ish client sent_bps ~= 419-422 recv_bps ~= 411-442
moving client sent_bps ~= 1198-1246 recv_bps ~= 184-191
rtt ~= 0.094-0.098
```

Interpretation:

Changing only the room/client/authority send rates from 30 to 60 does not materially improve normal horizontal presentation, because the 30 Hz baseline with smoothing already presents at render cadence. It does increase moving-client outbound bandwidth to roughly the same range as the best-case profile, about 1.2 kbps. This is not harmful in absolute terms, but it is not justified by the measured horizontal result unless subjective feel is noticeably better.

### Confirmation Result: `Profile.SMOOTHING_OFF_ONLY`

Status: completed as a clean 2-client one-factor test.

Profile:

```text
factor_smoothing_off_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = false
root_smooth_time = 0.08
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_smoothing_off_only
rates=30/30/30
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=false
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=10.4 avg_change_ms=98.4 avg_step_px=9.13 avg_remote_speed=97.4
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=9.32 avg_remote_speed=99.2
remote_pos_changes_per_sec=10.4 avg_change_ms=98.3 avg_step_px=9.37 avg_remote_speed=100.0
remote_pos_changes_per_sec=10.9 avg_change_ms=96.8 avg_step_px=9.09 avg_remote_speed=98.4
```

Spawn/stop-mixed windows:

```text
remote_pos_changes_per_sec=8.4 avg_change_ms=117.7 avg_step_px=14.36
remote_pos_changes_per_sec=5.5 avg_change_ms=111.7 avg_step_px=8.79
```

2-client bandwidth sample:

```text
moving client sent_bps ~= 605-624 recv_bps ~= 122-145
idle-ish client sent_bps ~= 203 recv_bps ~= 260-290
rtt ~= 0.102-0.105
```

Interpretation:

This is the clearest one-factor proof that built-in root smoothing is carrying the final visual smoothness. With only smoothing disabled, while keeping the good `update_interval = 1` and 30 Hz room rates, normal horizontal remote motion drops to about 10-11 visible changes/sec. That is better than the combined worst-case profile's roughly 5 visible changes/sec, so `update_interval = 6` is also harmful, but smoothing is the decisive presentation fix.

### Confirmation Result: `Profile.SMOOTH_TIME_005_ONLY`

Status: completed as a clean 2-client one-factor test.

Profile:

```text
factor_smooth_time005_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.05
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_smooth_time005_only
rates=30/30/30
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.05
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.60 avg_remote_speed=96.2
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.64 avg_remote_speed=98.1
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.65 avg_remote_speed=99.1
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.62 avg_remote_speed=97.5
```

Spawn/idle-mixed windows:

```text
remote_pos_changes_per_sec=51.6 avg_change_ms=16.7 avg_step_px=2.10 avg_remote_speed=127.4
remote_pos_changes_per_sec=39.2 avg_change_ms=17.3 avg_step_px=1.08 avg_remote_speed=63.2
```

Those early windows are not representative because remote object allocation and idle motion were mixed into the 2-second diagnostic window.

2-client bandwidth sample:

```text
moving client sent_bps ~= 600-651 recv_bps ~= 119-176
idle-ish client sent_bps ~= 203-303 recv_bps ~= 270-296
rtt ~= 0.102-0.109
```

Interpretation:

`root_smooth_time = 0.05` at the production 30 Hz send rate preserves render-cadence visible horizontal motion and keeps bandwidth in the same low range as the 30 Hz baseline. It has the same objective movement cadence as `0.08`; the remaining decision is subjective feel: `0.05` may feel slightly more responsive, while `0.08` may be a little more forgiving around jitter/corrections.

### Confirmation Result: `Profile.SMOOTH_TIME_015_ONLY`

Status: completed as a clean 2-client one-factor test.

Profile:

```text
factor_smooth_time015_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.15
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_smooth_time015_only
rates=30/30/30
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.15
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.55 avg_remote_speed=92.9
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.65 avg_remote_speed=98.7
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.49 avg_remote_speed=89.3
remote_pos_changes_per_sec=57.5 avg_change_ms=17.5 avg_step_px=1.58 avg_remote_speed=90.8
```

Spawn/idle-mixed windows:

```text
remote_pos_changes_per_sec=54.0 avg_change_ms=16.7 avg_step_px=1.54 avg_remote_speed=93.3
remote_pos_changes_per_sec=57.0 avg_change_ms=16.7 avg_step_px=0.61 avg_remote_speed=36.9
remote_pos_changes_per_sec=50.1 avg_change_ms=19.2 avg_step_px=0.93 avg_remote_speed=49.2
```

2-client bandwidth sample:

```text
moving client sent_bps ~= 580-646 recv_bps ~= 122-169
idle-ish client sent_bps ~= 210-313 recv_bps ~= 272-306
rtt ~= 0.103-0.124
```

Interpretation:

`root_smooth_time = 0.15` still presents steady horizontal motion at render cadence, but it appears more buffered than `0.05` or `0.08`. Some clean movement windows report lower apparent remote speed, and direction-change/stop windows show longer catch-up intervals (`max_change_ms` around 100-116 ms). This setting may look forgiving under jitter, but it is likely to feel more delayed. It is not the first-choice tuning unless subjective playtesting prefers the softer feel.

### Confirmation Result: `Profile.SNAP_DISTANCE_5_ONLY`

Status: completed as a clean 2-client one-factor failure test.

Profile:

```text
factor_snap5_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.08
root_snap_distance = 5.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_snap5_only
rates=30/30/30
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.08
snap=5.0
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=10.4 avg_change_ms=99.2 avg_step_px=9.37 avg_remote_speed=99.2
remote_pos_changes_per_sec=10.9 avg_change_ms=97.6 avg_step_px=9.24 avg_remote_speed=99.2
remote_pos_changes_per_sec=9.9 avg_change_ms=103.5 avg_step_px=9.50 avg_remote_speed=96.6
remote_pos_changes_per_sec=10.9 avg_change_ms=98.4 avg_step_px=9.24 avg_remote_speed=98.4
```

Spawn/mixed windows:

```text
remote_pos_changes_per_sec=7.4 avg_change_ms=127.4 avg_step_px=15.75
remote_pos_changes_per_sec=3.0 avg_change_ms=186.6 avg_step_px=16.07
```

2-client bandwidth sample:

```text
moving client sent_bps ~= 580-645 recv_bps ~= 118-164
idle-ish client sent_bps ~= 210-289 recv_bps ~= 250-295
rtt ~= 0.102-0.111
```

Interpretation:

Lowering `root_snap_distance` from `100.0` to `5.0` breaks the smoothing benefit during normal 100 px/sec horizontal motion. The remote returns to roughly the same visible cadence as smoothing-off-only: about 10-11 visible changes/sec with roughly 9 px steps. This strongly suggests normal smoothing error/correction distances exceed 5 px, so a low snap threshold causes ordinary updates to snap instead of interpolate. Keep `root_snap_distance` high enough that normal network correction remains smoothed; `100.0` is currently safe in the tested movement range.

### Confirmation Result: `Profile.UPDATE_INTERVAL_6_ONLY`

Status: completed as a clean 2-client one-factor test.

Profile:

```text
factor_interval6_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 6
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.08
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_interval6_only
rates=30/30/30
update_interval=6
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.08
snap=100.0
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.58 avg_remote_speed=94.9
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.66 avg_remote_speed=99.5
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.52 avg_remote_speed=91.2
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.51 avg_remote_speed=90.8
```

Spawn/idle-mixed windows:

```text
remote_pos_changes_per_sec=54.5 avg_change_ms=16.7 avg_step_px=1.47 avg_remote_speed=89.0
remote_pos_changes_per_sec=51.6 avg_change_ms=16.7 avg_step_px=0.80 avg_remote_speed=48.4
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.38 avg_remote_speed=82.7
```

2-client bandwidth sample:

```text
moving client sent_bps ~= 260-283 recv_bps ~= 121-129
idle-ish client sent_bps ~= 209-211 recv_bps ~= 254-301
rtt ~= 0.103-0.107
```

Interpretation:

With root smoothing enabled, `update_interval = 6` no longer looks visibly chunky during steady horizontal motion; the remote presentation still reaches render cadence. However, this is not evidence that `update_interval = 6` is better. The lower raw update rate is being hidden by smoothing, and several windows report lower apparent remote speed or mixed catch-up behavior. Because `update_interval = 6` becomes a severe failure when smoothing is unavailable or snapping occurs, keep `update_interval = 1` for production unless bandwidth pressure later forces a deliberate tradeoff.

### Confirmation Result: `Profile.DEFAULT_PRIORITY_1_ONLY`

Status: completed as a clean 2-client one-factor test.

Profile:

```text
factor_priority1_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 1
update_interval = 1
interest_mode = 0
area_enabled = false
root_smoothing = true
root_smooth_time = 0.08
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_priority1_only
rates=30/30/30
priority=1
update_interval=1
interest_mode=0
area_enabled=false
root_smoothing=true
smooth_time=0.08
snap=100.0
players=2
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.62 avg_remote_speed=97.0
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.65 avg_remote_speed=99.1
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.56 avg_remote_speed=93.5
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.58 avg_remote_speed=94.9
```

Spawn/idle-mixed windows:

```text
remote_pos_changes_per_sec=54.0 avg_change_ms=16.7 avg_step_px=1.12 avg_remote_speed=67.6
remote_pos_changes_per_sec=54.5 avg_change_ms=16.7 avg_step_px=1.11 avg_remote_speed=66.9
remote_pos_changes_per_sec=31.2 avg_change_ms=18.3 avg_step_px=0.72 avg_remote_speed=39.9
remote_pos_changes_per_sec=54.0 avg_change_ms=17.4 avg_step_px=1.31 avg_remote_speed=75.8
```

2-client bandwidth sample:

```text
moving client sent_bps ~= 599-622 recv_bps ~= 121-136
idle-ish client sent_bps ~= 203-230 recv_bps ~= 251-293
rtt ~= 0.104-0.113
```

Interpretation:

Changing only `DefaultPriority` from `2` to `1` preserves smooth render-cadence presentation during clean horizontal movement, but it does not materially improve the result compared with the current priority-2 baseline. The bandwidth profile remains in the same low hundreds-of-bps family as the 30 Hz no-area baseline. This confirms `DefaultPriority` is not the important factor for the original visible stutter.

### Confirmation Result: `Profile.AREA_INTEREST_BASE_SEND_1_ONLY`

Status: completed as a clean 2-client paired-factor comparison.

Profile:

```text
factor_area_base1_only
RoomSendRate = 30
ClientSendRate = 30
AuthoritySendRate = 30
DefaultPriority = 2
update_interval = 1
interest_mode = 1
area_enabled = true
area_base_send_rate = 1
root_smoothing = true
root_smooth_time = 0.08
root_snap_distance = 100.0
root_min_position_error = 0.1
```

Ready logs confirmed:

```text
test_profile=factor_area_base1_only
rates=30/30/30
priority=2
update_interval=1
interest_mode=1
area_enabled=true
area_base_send_rate=1
root_smoothing=true
smooth_time=0.08
snap=100.0
players=2
```

Runtime confirmed the dynamic interest areas were present:

```text
interest_area name=Player orientation=0 grid_size=21 base_send_rate=1 decay_mode=0 enabled=true
interest_area name=@CharacterBody2D@29 orientation=0 grid_size=21 base_send_rate=1 decay_mode=0 enabled=true
```

Representative clean horizontal remote samples:

```text
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.58 avg_remote_speed=94.9
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.56 avg_remote_speed=93.8
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.58 avg_remote_speed=94.7
remote_pos_changes_per_sec=60.0 avg_change_ms=16.8 avg_step_px=1.58 avg_remote_speed=94.6
```

Spawn/jump-mixed window:

```text
remote_pos_changes_per_sec=39.2 avg_change_ms=16.7 avg_step_px=1.97 avg_remote_speed=119.6
```

2-client bandwidth sample:

```text
initial sent_bps ~= 23462-23470
steady sent_bps ~= 58538-67874
recv_bps ~= 117-452
rtt ~= 0.103-0.107
```

Interpretation:

Explicit area interest with `base_send_rate = 1` preserves smooth render-cadence motion, but it is dramatically more expensive than the no-area baseline in this tiny two-player close-range test. The moving presentation is not meaningfully better than the two-player smoothing baseline, while outbound bandwidth climbs from hundreds of bps to roughly 58-68 kbps per client. This confirms the earlier suspicion: area interest can force higher-cadence delivery for relevant objects. It does not prove area interest is bad for production; a real game should still use area interest to cull many out-of-range players/objects. It only means this specific `base_send_rate = 1` setup is the wrong tradeoff if used solely as a player-root movement fix.

## Current Working Conclusion

The strongest current conclusion:

The user's internet speed/bandwidth is not causing the low-cadence movement. Godot render/physics throttling is also not causing it. The raw sync-rate evidence points most strongly at Fusion's default/global root replication interest/send-rate scheduling. With default/global root replication, raw remote root motion was below the configured room send rate: about 10-11 visible updates/sec in 30 Hz raw tests and about 15-16 visible updates/sec in 60 Hz raw tests. Explicit area interest with `FusionInterestArea.base_send_rate = 1` increased raw cadence to about 20-21 visible updates/sec at 30 Hz and about 30-32 visible updates/sec at 60 Hz, but it also raised bandwidth dramatically. In the final two-client comparison, area interest cost roughly 58-68 kbps/client instead of hundreds of bps/client. A doubled raw update rate cannot explain a roughly 100x bandwidth increase by itself; the explicit area-interest path/payload behavior appears to account for most of the bandwidth jump in the tiny two-player test.

So, for raw sync cadence: area interest enabled with `base_send_rate = 1` is faster, but much heavier. Area interest disabled is cheaper, but lower cadence. `base_send_rate = 0` and `base_send_rate = 2` were worse than `base_send_rate = 1`. `DefaultPriority = 1` did not materially improve cadence or bandwidth. `root_min_position_error = 0.1` improves pixel precision but did not fix cadence. `root_snap_distance = 5.0` caused ordinary corrections to snap visibly, so snap distance should stay high enough for normal correction distances.

Current two-player movement tradeoff for the tested root-transform case: keep `RoomSendRate = 30`, `root_replication_mode = AUTO`, `interest_mode = 0`, no `FusionInterestArea`, `root_smoothing = true`, `root_smooth_time = 0.08`, `root_snap_distance = 100.0`, and `root_min_position_error = 0.1`. This does not make raw sync cadence maximal; it chooses low bandwidth and smooth presentation over expensive area-interest delivery in a tiny test with nothing to cull. Production-scale interest areas remain a separate requirement.

## Questions For Photon/Fusion Developers If Needed

If this becomes a developer support report, ask:

1. In Fusion Godot 3 shared authority, what is the expected effective send/apply cadence for `FusionSharedReplicator` root transform replication when `RoomSendRate = 60`, `ClientSendRate = 60`, `AuthoritySendRate = 60`, and `update_interval = 1`?
2. Why would a `CharacterBody2D` root with smoothing disabled visibly change at ~15-16 Hz under a 60 Hz room send rate?
3. Does `FusionInterestArea.base_send_rate = 1` override this cadence for root replication?
4. How does `fusion/serialization/float_compression` affect 2D pixel positions?
5. Are `root_min_position_error` and `root_min_rotation_error` intended for public use, and should they be exposed/documented?
6. Is built-in root transform replication intended for pixel-art 2D character controllers, or should this use custom replicated properties plus local render interpolation?

## Final Concise Summary

Problem: raw remote root updates were arriving/applying below the configured Photon/Fusion room send rate. With 30 Hz networking and default/global root replication, raw remote motion was around 10-11 visible updates/sec in the no-smoothing tests. This was not caused by internet speed, GPU performance, V-Sync, Godot FPS, physics tick rate, or `DefaultPriority`.

Raw sync-rate finding: explicit area interest with `FusionInterestArea.base_send_rate = 1` increases raw update cadence, but in the tiny two-player test it mostly increased send frequency because there were no far-away objects to cull. The recommended movement baseline chooses low bandwidth plus local interpolation instead of forcing maximum raw cadence. Production-scale area interest should still be added/tuned separately for culling many players/objects:

| Owner / object | Property | Recommended value | Default status |
| --- | --- | --- | --- |
| Photon room `fusion_config` in join options | `RoomSendRate` | `30` | Default / keep |
| Photon room `fusion_config` in join options | `ClientSendRate` | `30` | Default / keep |
| Photon room `fusion_config` in join options | `AuthoritySendRate` | `30` | Default / keep |
| Photon room `fusion_config` in join options | `DefaultPriority` | `2` | Default / keep |
| `Player/FusionSharedReplicator` | `interest_mode` | `0` for the two-player movement baseline | Default / keep for this diagnostic scene; production-scale interest TBD |
| Player scene | `FusionInterestArea` child | none for the two-player movement baseline | Default / keep absent for this diagnostic scene; production-scale interest TBD |
| `Player/FusionSharedReplicator` | `root_replication_mode` | `AUTO` / `1` | Project override; required for remote root visibility |
| `Player/FusionSharedReplicator` | `root_smoothing` | `true` | Default / keep; must stay enabled |
| `Player/FusionSharedReplicator` | `root_smooth_time` | `0.08` | Project tuning; `0.05` is optional lower-latency candidate |
| `Player/FusionSharedReplicator` | `root_snap_distance` | `100.0` | Project tuning; do not lower to `5.0` |
| `Player/FusionSharedReplicator` | `root_min_position_error` | `0.1` | Project override; observed plugin default was `1.0` |

Default/problem settings vs recommended settings:

| Setting | Default / tempting change | Recommended | Why |
| --- | --- | --- | --- |
| Network send rate | 30 Hz default | 30 Hz | 60 Hz was only a stress comparison and is not considered reasonable for this project. |
| `DefaultPriority` | 2 default, 1 tested | 2 | Priority 1 did not materially improve cadence or bandwidth. |
| `interest_mode` / area | No area is cheaper but lower raw cadence; area with `base_send_rate=1` is faster but expensive in the two-player test | Two-player movement baseline: `interest_mode=0`, no area. Production-scale world: area interest TBD. | Area raised raw cadence to about 20-21/sec at 30 Hz, but cost about 58-68 kbps/client when there was nothing useful to cull. Real production area interest should reduce bandwidth by excluding out-of-range players/objects. |
| `root_smoothing` | Disabled exposes raw low cadence | Enabled | This is the visual presentation fix; it does not increase real sync rate. |
| `root_smooth_time` | 0.05 / 0.08 / 0.15 tested | 0.08 | 0.08 is stable. 0.05 is viable if lower latency feels better. 0.15 feels more delayed. |
| `root_snap_distance` | 5 caused snapping | 100 | Low snap distance made normal movement jump at about 10-11 visible changes/sec. |
| `root_min_position_error` | Default observed as 1.0 | 0.1 | Better pixel precision; not the main cadence fix. |

Default-30-Hz tick-rate / cadence limits observed in this project:

| Meaning | Lowest observed | Highest validated | Recommendation |
| --- | --- | --- | --- |
| Configured Fusion room/client/authority send rate | 30 Hz | 30 Hz | Treat 30 Hz as the production network tick rate. |
| Raw visible remote cadence without smoothing at 30 Hz | About 10-11/sec with default/global root replication | About 20-21/sec with area interest, but expensive in the two-player test | Do not use this area-interest profile solely as a player-root cadence fix; tune production area interest for world/object culling. |
| Final visible remote presentation with smoothing at 30 Hz | About 10-11/sec when snap is misconfigured | 60/sec, matching render cadence | Target 60 FPS visual motion from 30 Hz network sends. |

The 60 Hz send-rate tests were diagnostic only. They showed that higher send rates can work, but they are not the recommended "highest" for this game because the 30 Hz setup already reaches 60 FPS visual presentation with much lower bandwidth.
