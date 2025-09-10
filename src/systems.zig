const std = @import("std");
const rl = @import("raylib");
const entity = @import("entity.zig");

pub fn movePlayer(entities: *entity.EntityList, player_id: entity.Id) !void {
    const speed = 10;
    const player = try entities.get(player_id);

    if (rl.isKeyDown(.up) or rl.isKeyDown(.w)) {
        player.position.y -= speed;
    }
    if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) {
        player.position.x -= speed;
    }
    if (rl.isKeyDown(.down) or rl.isKeyDown(.s)) {
        player.position.y += speed;
    }
    if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) {
        player.position.x += speed;
    }
}

pub fn moveEnemies(entities: *entity.EntityList) void {
    const TIMER = 1500;
    var iter = entities.iter();
    while (iter.next()) |ent| {
        if (ent.tag == .enemy) {
            ent.position.x += if (ent.direction) 4 else -4;
            // TODO: chagne ent.timestamp to ent.time_remaining, and find a way to pass the delta time - maybe wrap `entities` in a `world`?
            if (std.time.milliTimestamp() >= ent.timestamp + TIMER) {
                ent.direction = !ent.direction;
                ent.timestamp += TIMER;
            }
        }
    }
}
