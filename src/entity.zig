const std = @import("std");
const rl = @import("raylib");

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

pub const Entity = struct {
    id: Id = .invalid,
    position: rl.Vector2,
    render: Render,
    networked: bool,
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

    pub fn spawn(self: *@This(), entity: Entity) Id {
        if (self.next_id >= self.entities.len) {
            @panic("Over 100 entities!");
        }
        var ent = entity;
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
