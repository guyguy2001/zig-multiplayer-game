- Sending inputs for deterministic simulations - https://web.archive.org/web/20180823010932/https://gafferongames.com/post/deterministic_lockstep/
- source networking (might not get used) - https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking

  - The server sends snapshots to the players in certain intervals, and the players send a snapshot of their input in an interval
  - depending on the simulation rate, the player's snapshot can contain multiple frame's worth of input (I think)
  - server snapshots are sent in a delta format, but clients can request a full snapshot
  - entity interpolation
    - The rendering of network objects is delayed by 50ms in order to be able to interpolate between the current position and the one on the next snapshot, since there are multiple render frames between them
    - the server compensates for this lag when calculating if your shot hits
  - Lag compensation
    - When the server receives a "fire" event, it rolls the players back to where they were, and then calculates the hit.
    - For some reason I don't fully understand, the result isn't fully deterministic to the pixel level
    - Like I thought, it's possible to get hit even if you just got behind cover because of the rollback calculation
  - Additional notes
    - I don't think source games have a lot of a ways of pushing people, so client side prediction of self-position is reliable for like 99% of cases, unlike overwatch - although I'm not sure how it changes the networking aspect.
    - If I want to use their method in my game, it means that other players will be rendered where they were in the past.

- overwatch networking (might not get used) - https://www.youtube.com/watch?v=W3aieHjyNvw

### Design Stuff

Do I want to have the server send client inputs or state?

- Inputs:
  - pros:
    - Allows me to simulate the entire world on the client
  - cons:
    - Forces me to use perfect-information (everyone knows where everyone is)
    - requires rollback
- Snapshots:
  - Scalable for other game types, allow non-perfect information (either secrets of non-determinism)
  - Probably easier to implement on the client
