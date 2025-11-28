# Architecture

## Server

Procedure:

- Whenever an input message arrives from a client, store it in a buffer.
- When the inputs from all players for the next frame arrive, simulate that frame, and publish the rsult to the players as a snapshot.
  - TODO: Limit this to run on a clock?

## Client

- Always simulate the rest of the clients 2 frames behind.
- Locally simulated entities (the player + offline NPCs) are simulated on the current frame.
  - TODO: What to do once I start sending stuff about the NPCs? Probably irrelant for my scope

Procedure:

- Whenever you recieve a snapshot part, store it in a buffer
- Whenever you simulate a frame, use the data from 2 frames ago, interpolating if said frame is missing.
  - As for locally-owned entities (the player for now), replay the inputs of the last 2 frames, and apply them on top of what the server sent. For 99% of cases should be the same, is different with stuns / input-PL. (Practically a rebase)

# Resulting Todos

- Make sure it's easy to simulate a single game frame, I need to make sure time travel both on the clients and the server is easily doable
- I think that for interpolations I would want to retain the previous frame the buffer.
