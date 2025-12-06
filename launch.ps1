$server = Start-Process -FilePath "zig_multiplayer_game.exe" -ArgumentList "--", "--server" -PassThru
$client1 = Start-Process -FilePath "zig_multiplayer_game.exe" -ArgumentList "--", "--client-id", "1" -PassThru
$client2 = Start-Process -FilePath "zig_multiplayer_game.exe" -ArgumentList "--", "--client-id", "2" -PassThru

Write-Host "Started processes:"
Write-Host "  Server:  $($server.Id)"
Write-Host "  Client1: $($client1.Id)"
Write-Host "  Client2: $($client2.Id)"
Write-Host ""

Read-Host "Press Enter to terminate them"

Stop-Process -Id $server.Id, $client1.Id, $client2.Id -Force
