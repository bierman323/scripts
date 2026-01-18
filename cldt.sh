#!/usr/bin/env zsh

if [ -z "$1" ]
then
  echo "You need to add a name of the tmux sesssion"
  exit 1
fi


SESSION=claude-$1
sesson_list=$(tmux list-sessions | grep $SESSION)

if [ -z "$sesson_list" ]
then
  lines="$(tput lines)"
  columns="$(tput cols)"

  # Start a new session
  tmux new-session -d -x "$columns" -y "$lines" -s "$SESSION"

  # Setup Window 1
  tmux rename-window 'code'
  tmux split-window -h "bash"
  tmux send-keys -t "$SESSION:1" "claude" C-m
  tmux split-window -v "bash"
  tmux select-pane -t 1

fi

tmux attach-session -t "$SESSION"
