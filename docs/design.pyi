# Server
type ClientId = int

class Inputs: ...

class InputBuffer:
    earliest_frame: int  # The first frame in the buffer
    frames: list[dict[ClientId, Inputs | None]]

# Client
class SnapshotBuffer:
    earlier_frame: int
    frames: list[
        World | None
    ]  # The client later takes the world and injects client owned entities into it
