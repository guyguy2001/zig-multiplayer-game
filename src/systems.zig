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
