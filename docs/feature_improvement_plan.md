# Feature Improvement Plan

## Current foundation

- City generation owns walkable geometry, building slots, lighting profiles, and walk snapping.
- Population simulation owns residents, households, relationships, life events, character profiles, activity intents, visual appearance intents, and time.
- Pedestrian crowd owns visible actors, movement, social groups, conversations, event spectators, and player interaction.
- UI owns inspection, event feed, controls, and projected speech bubbles.

The latest performance work added spatial indexes for city walk snapping and crowd proximity queries, cached resident activity decisions, and a data-only visible-intent layer. The visual crowd now renders selected population intents instead of making the deeper life decisions itself.

## Near-term features

1. Conversation reliability and feedback
   - Add a tiny on-screen status for selected-person dialogue: local fallback, API pending, API response, API unavailable.
   - Store the last generated player line on each resident so repeated clicks can continue rather than restart.
   - Add a short cooldown only for automatic player-nearby remarks; manual clicks should always override.

2. Resident intent and schedules
   - Promote activity dictionaries into a small `ResidentActivity` schema with mode, target, venue, urgency, guardian rules, and expiry.
   - Cache activities by explicit time bucket and invalidate on life events that change household/workplace.
   - Let residents form small purposeful flows: home to work, work to lunch, plaza to shop, event to home.

3. Inspectable city memory
   - Add a "recent memories" list per resident sourced from life events, conversations, and daily destinations.
   - Show household relationships and recent memories in the existing selection panel.
   - Let OpenRouter prompts use this memory context when present.

4. Higher-density crowd mode
   - Add a crowd quality preset: low, balanced, dense.
   - Scale update slices, label interval, event effect cap, and detailed actor animation from that preset.
   - Add a dense benchmark script that validates 100-200 visible actors without regressing frame cost.

## Architecture targets

- Keep city queries data-oriented: all repeated spatial queries should use indexes or cached snapshots.
- Keep population state deterministic for tests: feature simulations should be seed-driven.
- Keep player-triggered interactions authoritative: direct clicks should override ambient systems.
- Keep UI projection defensive: bubbles and labels should clamp or degrade gracefully at camera edges.

## Completed milestone

Resident memory conversations are now in place at the first useful level:
- Population exposes a conversation context for each resident.
- Clicked player conversations can use name, age, occupation, current activity, household, top bonds, and recent life events.
- OpenRouter prompts receive that context.
- Local fallback dialogue also uses that context, so the feature still works offline.

Resident intent isolation is now in place at the first useful level:
- Population assigns each resident character traits, values, quirks, and motivation.
- Population exposes low-frequency visible resident intents for the crowd to render.
- Young children require guardian companions before they can be visualized outside the home.
- The crowd uses population intent data and keeps visual movement/conversation separate from simulation identity decisions.

## Suggested next milestone

Build "conversation continuity": after a generated player conversation, store a short resident memory such as "met the player near the plaza" or "mentioned the bakery." Use that memory in future prompts and show it in the selection panel. This turns one-off clicks into an inspectable relationship thread.
