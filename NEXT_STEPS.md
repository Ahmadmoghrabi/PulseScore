# Rebase — status and next steps

## Done

- **Step 1** — project scaffold (XcodeGen-based), full UI shell against mock data.
- **Step 2** — `ScoreEngine`, pure Swift, 13 passing XCTest cases.
- **UI redesign** — two-ring "Workout + Recovery" summary card, square metric tiles in a 3-column grid, line-and-dot Swift Charts trend, custom heartbeat/ring vector app icon.
- **Step 3** — `HealthKitManager` wired end-to-end. Real `HKStatisticsCollectionQueryDescriptor` queries, native async/await (no continuation bridging needed), graceful `LoadState` handling (loading / authorization-denied / not-enough-data / loaded / failed). Verified for real on the Simulator via a DEBUG-only "Seed Data" button that writes synthetic samples into the Simulator's HealthKit store (Release builds never request write access — this is entirely compiled out via `#if DEBUG`).
- **Portfolio-ready**: pushed to GitHub at `Ahmadmoghrabi/Rebase` with a README covering the scoring formula, architecture, and real debugging lessons.
- **Pull-to-refresh** — `.refreshable` on the dashboard's `ScrollView` calls `load()` again, so updated numbers (e.g. right after a workout) don't require force-quitting and relaunching.

Three real bugs were found and fixed during Step 3 by actually running the app, not by code review — worth remembering the *kind* of thing to watch for next time:
1. Third-party apps can't write `HKQuantityTypeIdentifier.appleExerciseTime` (or Stand Time) — Apple reserves those for its own frameworks.
2. Write access needs `NSHealthUpdateUsageDescription`, a separate Info.plist key from the read-only `NSHealthShareUsageDescription`.
3. The original "not enough data" check compared day *counts*, but `fetchFourteenDayHistory()` always returns exactly 14 synthesized days regardless of real data — the actual check needs to look for real recorded activity, not calendar coverage.

## Not yet done — pick from here

Roughly in priority order, but none of these block each other — pick whichever's most useful for wherever you're taking this next (interview prep vs. actually shipping it).

### 1. Verify on a real device, with real data
Everything so far has only been verified on the Simulator with synthetic seeded data. Real verification needs: Xcode → Signing & Capabilities → Team set to your Apple ID, a physical iPhone as the run destination, trusting the dev certificate on-device (Settings → General → VPN & Device Management), then granting the real Health permission sheet. Worth specifically checking what happens if your real 7-day history is thin — that's exactly the `.notEnoughData` path, and it'd be good to confirm it degrades as gracefully with real data as it did with the empty Simulator store.

### 2. Home Screen widget (WidgetKit)
You floated this idea mid-session — glanceable Workout Score right after finishing a workout, without opening the app. This is a genuinely good next feature: a `WidgetKit` extension target, sharing `ScoreEngine` and the HealthKit-fetching logic via an App Group, showing the current Workout/Recovery scores. Also a natural bridge toward the "watch software" angle below, since widgets and watchOS complications are close cousins conceptually.

### 3. A watchOS companion (stretch, but the most direct alignment with a Fitness+/Watch Software role)
Everything built so far reads *historical, already-saved* HealthKit samples after the fact. The Fitness+/Watch Software domain is about *live* workout sessions — `HKWorkoutSession` and the `WorkoutKit` framework, streaming heart rate/energy in real time on-wrist, saving the completed session back to HealthKit when done. Even a minimal watchOS target that starts a workout session and shows live heart rate would be a meaningfully different (and more directly relevant) skill demonstration than anything in the iPhone app so far. Worth treating as its own multi-session project rather than a quick add-on.

### 4. Engineering hygiene
- Unit tests for `HealthKitManager`'s pure logic (e.g. `computeTrend`) — the HealthKit-calling parts can't be unit tested without a device/simulator, but the date-bucketing and trend-assembly logic could be extracted and tested the same way `ScoreEngine` is.
- XCUITest coverage for the loading/denied/empty/loaded states in `ContentView`.
- HealthKit background delivery (`HKObserverQuery`) so the score updates automatically instead of only at launch.

### 5. UI/feature extras (lower priority, "nice to have")
- A detail view per metric (tap a tile → see the actual 7-day values that produced today's percentage, not just the summary sentence).
- Let the user adjust the metric weights themselves and see the score recompute — turns the "explainable formula" pitch into something interactive.
- A longer trend view (30 days) alongside the current 7-day one.

### 6. Visual design tweaks
- ~~Revisit the app icon~~ — done, after a few rounds: colored two-ring mark → monochrome EKG-bridge mark → finally replaced with the user's own IconKitchen export (solid white heart with a black EKG notch on black). That's the current icon.
- Change the main dashboard's background — currently a flat near-black (`Theme.background`); consider a gradient or otherwise more distinct "landing" treatment for the top of the screen behind the title/summary card.

### 7. Project rename follow-through
The project was renamed PulseScore → Rebase (folders, bundle ID, GitHub repo, resume, README) — all verified working. Nothing left to do here, just noting it happened in case older conversation history or search results still reference the old name.
