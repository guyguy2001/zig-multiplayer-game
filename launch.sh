# Copy this near the exe before running
./zig_multiplayer_game.exe -- --server &
pid1=$!
./zig_multiplayer_game.exe -- --client-id 1 &
pid2=$!
./zig_multiplayer_game.exe -- --client-id 2 &
pid3=$!

# Wait for user input
read -p "Press Enter to continue..."

# Kill both processes
kill $pid1 $pid2 $pid3