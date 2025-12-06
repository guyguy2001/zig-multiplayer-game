const std = @import("std");
const rl = @import("raylib");

const net = @import("net");

const Tag = enum {
    player,
    enemy,
    ui,
};

const RenderTag = enum {
    circle,
    button,
    texture,
};

const Render = union(RenderTag) {
    circle: struct {
        color: rl.Color,
        radius: f32,
    },
    button: struct {
        color: rl.Color,
        text: *const [10:0]u8,
        width: f32,
        height: f32,
    },
    texture: struct {
        path: [*:0]u8,
    },
};

pub const Id = packed struct {
    generation: usize,
    index: usize,

    pub const invalid = Id{ .generation = 0xffff, .index = 0xffff };

    pub fn equals(self: @This(), other: @This()) bool {
        return self.generation == other.generation and self.index == other.index;
    }
};

pub const Timer = struct {
    max: i64,
    remaining: i64,
    just_finished: bool = false,
    paused: bool = false,

    pub fn update(self: *@This(), time: *Time) void {
        self.just_finished = false;
        if (self.paused) return;

        self.remaining -= time.deltaMillis();
        if (self.remaining <= 0) {
            self.remaining += self.max;
            self.just_finished = true;
        }
    }

    pub fn invalid() Timer {
        return Timer{
            .max = 0,
            .remaining = 0,
            .just_finished = false,
            .paused = true,
        };
    }
};

pub const NetworkedEntity = struct {
    owner_id: net.ClientId,
};

pub const Entity = struct {
    id: Id = .invalid,
    name: ?[]const u8,
    position: rl.Vector2,
    speed: f32 = 0,
    render: Render,
    network: ?NetworkedEntity = null,
    tag: Tag,
    timer: Timer = .invalid(),
    direction: bool = false,
    visible: bool = true,

    // TODO: Switch from ClientId to NetowrkIdentity (which is either Server{} or Client{id: u8?})
    pub fn isSimulatedLocally(self: *const @This(), client_id: net.ClientId) bool {
        if (self.network) |network| {
            return network.owner_id.value == client_id.value;
        } else {
            // Any entity which isn't networked has to be simulated by us (currently unused)
            return true;
        }
    }

    pub fn make_diff(self: *const @This()) EntityDiff {
        return .{
            .id = self.id,
            .position = .{
                .x = self.position.x,
                .y = self.position.y,
            },
        };
    }

    pub fn apply_diff(self: *@This(), diff: EntityDiff) !void {
        if (!self.id.equals(diff.id)) return error.DiffHasWrongId;
        // std.debug.print("apply_diff on {?s} - ({d}, {d}) -> ({d}, {d})\n", .{
        //     self.name,
        //     self.position.x,
        //     self.position.y,
        //     diff.position.x,
        //     diff.position.y,
        // });
        self.position = rl.Vector2.init(diff.position.x, diff.position.y);
    }
};

pub const EntityDiff = packed struct {
    id: Id,
    position: packed struct {
        x: f32,
        y: f32,
    },
};

const EntitiesAccessError = error{
    IndexTooBig,
    GenerationMismatch,
    EntityNotAlive,
};

pub const EntityList = struct {
    entities: [100]Entity,
    is_alive: [100]bool,
    modified_this_frame: [100]bool,
    next_id: usize,

    pub fn spawn(self: *@This(), engine: Entity) Id {
        if (self.next_id >= self.entities.len) {
            @panic("Over 100 entities!");
        }
        var ent = engine;
        ent.id = Id{ .generation = 0, .index = self.next_id };
        self.entities[ent.id.index] = ent;
        self.is_alive[ent.id.index] = true;
        self.next_id += 1;
        return ent.id;
    }

    pub fn get(self: *const @This(), id: Id) EntitiesAccessError!*const Entity {
        if (id.index >= self.next_id) {
            return EntitiesAccessError.IndexTooBig;
        }
        if (!self.is_alive[id.index]) {
            return EntitiesAccessError.EntityNotAlive;
        }
        return &self.entities[id.index];
    }

    pub fn get_mut(self: *@This(), id: Id) *Entity {
        if (id.index >= self.next_id) {
            @panic("IndexTooBig");
        }
        if (!self.is_alive[id.index]) {
            @panic("EntityNotAlive");
        }
        self.modified_this_frame[id.index] = true;
        return &self.entities[id.index];
    }

    pub fn iter(self: *@This()) EntitiesIterator {
        return EntitiesIterator{
            .list = self,
            .index = 0,
        };
    }
};

pub const EntitiesIterator = struct {
    list: *EntityList,
    index: usize,
    pub fn next(self: *@This()) ?*const Entity {
        for (self.index..self.list.next_id) |i| {
            if (self.list.is_alive[i]) {
                self.index = i + 1;
                return &self.list.entities[i];
            }
        }
        return null;
    }
};

pub const Time = struct {
    time_per_frame: u32,
    game_start_time: i64,
    frame_number: u64,

    pub fn init(time_per_frame: u32) Time {
        return Time{
            .time_per_frame = time_per_frame,
            .game_start_time = std.time.milliTimestamp(),
            .frame_number = 0,
        };
    }

    pub fn reset(self: *@This()) void {
        self.game_start_time = std.time.milliTimestamp();
    }

    pub fn update(self: *@This()) void {
        self.frame_number += 1;
    }

    pub fn deltaMillis(self: *@This()) u32 {
        return self.time_per_frame;
    }

    pub fn deltaSecs(self: *@This()) f32 {
        return @as(f32, @floatFromInt(self.deltaMillis())) / 1000.0;
    }

    pub fn getDrift(self: *@This()) f32 {
        return (@as(f32, @floatFromInt(std.time.milliTimestamp() - self.game_start_time)) /
            @as(f32, @floatFromInt(self.time_per_frame))) -
            @as(f32, @floatFromInt(self.frame_number));
    }
};

pub const State = enum {
    menu,
    game,
};

// Everything in this struct should be predictable from the last frame, given the inputs/snapshots
pub const World = struct {
    entities: EntityList,
    time: Time,
    screen_size: rl.Vector2,
    state: State,
};

pub const Input = packed struct {
    up: bool,
    left: bool,
    down: bool,
    right: bool,

    pub fn empty() Input {
        return .{
            .up = false,
            .left = false,
            .down = false,
            .right = false,
        };
    }

    pub fn fromRaylib() Input {
        return .{
            .up = rl.isKeyDown(.up) or rl.isKeyDown(.w),
            .left = rl.isKeyDown(.left) or rl.isKeyDown(.a),
            .down = rl.isKeyDown(.down) or rl.isKeyDown(.s),
            .right = rl.isKeyDown(.right) or rl.isKeyDown(.d),
        };
    }

    pub fn getDirection(input: *const @This()) rl.Vector2 {
        var direction = rl.Vector2.zero();
        if (input.up) {
            direction = direction.add(rl.Vector2.init(0, -1));
        }
        if (input.left) {
            direction = direction.add(rl.Vector2.init(-1, 0));
        }
        if (input.down) {
            direction = direction.add(rl.Vector2.init(0, 1));
        }
        if (input.right) {
            direction = direction.add(rl.Vector2.init(1, 0));
        }
        return direction;
    }
};
