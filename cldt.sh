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
  # Set tab title
  printf '\e]1;%s\a' "$SESSION"

  ## Set tab color (red for prod warning)
  printf '\e]6;1;bg;red;brightness;%d\a' 80
  printf '\e]6;1;bg;green;brightness;%d\a' 180
  printf '\e]6;1;bg;blue;brightness;%d\a' 80

## Launch your session
#tmux new-session -A -s prod
  lines="$(tput lines)"
  columns="$(tput cols)"

  # Start a new session
  tmux new-session -d -x "$columns" -y "$lines" -s "$SESSION"

  # Setup Window 1
  tmux rename-window 'code'
  tmux split-window -h "bash"
  tmux send-keys -t "$SESSION:1" "cldr" C-m
  tmux select-pane -t 2

fi

tmux attach-session -t "$SESSION"
