const std = @import("std");
const rl = @import("raylib");

const Tag = enum {
    player,
    enemy,
};

const RenderTag = enum {
    circle,
    texture,
};

const Render = union(RenderTag) {
    circle: struct {
        radius: f32,
        color: rl.Color,
    },
    texture: struct {
        path: [*:0]u8,
    },
};

pub const Id = struct {
    generation: usize,
    index: usize,

    pub const invalid = Id{ .generation = 0xffff, .index = 0xffff };
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

pub const Entity = struct {
    id: Id = .invalid,
    position: rl.Vector2,
    speed: f32,
    render: Render,
    networked: bool,
    tag: Tag,
    timer: Timer = .invalid(),
    direction: bool = false,
};

const EntitiesAccessError = error{
    IndexTooBig,
    GenerationMismatch,
    EntityNotAlive,
};

pub const EntityList = struct {
    entities: [100]Entity,
    is_alive: [100]bool,
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

    pub fn get(self: *@This(), id: Id) EntitiesAccessError!*Entity {
        if (id.index >= self.next_id) {
            return EntitiesAccessError.IndexTooBig;
        }
        if (!self.is_alive[id.index]) {
            return EntitiesAccessError.EntityNotAlive;
        }
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
    pub fn next(self: *@This()) ?*Entity {
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
    time_per_frame: i64,
    game_start_time: i64,
    frame_number: i64,

    pub fn init(time_per_frame: i64) Time {
        return Time{
            .time_per_frame = time_per_frame,
            .game_start_time = std.time.milliTimestamp(),
            .frame_number = 0,
        };
    }

    pub fn update(self: *@This()) void {
        self.frame_number += 1;
    }

    pub fn deltaMillis(self: *@This()) i64 {
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

pub const World = struct {
    entities: EntityList,
    time: Time,
};
