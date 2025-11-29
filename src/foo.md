I might be confusing 2 things here.

My main goal is for the client to be ahead enough of the server, such that our messages reach the server (after passing half rtt) when it needs them - 1 or 2 frames before simulations.

Server's inputs buffer:
[#|#######]
^^^^^^ half rtt
^ buffer

That is a separate idea from the buffer on the client.

Let's assume I keep the client's buffer at 2.
Then I need the server

half rtt

client's frame = server + half-rtt + 2
