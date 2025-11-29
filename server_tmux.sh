#!/usr/bin/env zsh


SESSION="servers"
sesson_list=$(tmux list-sessions | grep $SESSION)

if [ -z "$sesson_list" ]
then
  lines="$(tput lines)"
  columns="$(tput cols)"

  # Start a new session
  tmux new-session -d -x "$columns" -y "$lines" -s "$SESSION"

  # Setup Window 1
  tmux rename-window 'shell'
  # tmux send-keys -t "$SESSION:1" "mini" C-m

  # Setup Window 2

  tmux new-window -t "$SESSION" -n "servers"
  tmux select-window -t "$SESSION:2"
  tmux send-keys -t "$SESSION:2" "ssh mini" C-m
  tmux split-window -h -p 60
  tmux split-window -v
  tmux split-window -h
  tmux split-window -h
  tmux select-pane -t 1
  tmux send-keys -t "$SESSION:2.2" "ssh mini-2" C-m
  tmux send-keys -t "$SESSION:2.3" "ssh trailer" C-m
  tmux send-keys -t "$SESSION:2.4" "ssh big-boy" C-m
  tmux send-keys -t "$SESSION:2.5" "ssh ubuntu-pi5" C-m
  tmux select-layout -t "$SESSION:2" tiled

fi

tmux attach-session -t "$SESSION"
