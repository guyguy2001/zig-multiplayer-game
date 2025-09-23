zig build run -Dserver &
pid1=$!
zig build run -- --client-id 1 &
pid2=$!
zig build run -- --client-id 2 &
pid3=$!

# Wait for user input
read -p "Press Enter to continue..."

# Kill both processes
kill $pid1 $pid2 $pid3