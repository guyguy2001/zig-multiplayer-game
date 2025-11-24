General thoughts

- It's hard to develop/debug programs that have to work in lock-step - whenever I change something in the code in the server that waits for all of the clients to send their input, everything freezes.

Protocol explanations:

- I end up having a cyclic buffer of "what was sent for each frame" a lot of the time
