zig build run -Dserver &
pid1=$!
zig build run &
pid2=$!

# Wait for user input
read -p "Press Enter to continue..."

# Kill both processes
kill $pid1 $pid2