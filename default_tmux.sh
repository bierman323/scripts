#!/usr/bin/env zsh

if [ -z "$1" ]
then
  echo "You need to add a name of the tmux sesssion"
  exit 1
fi

SESSION=$1
sesson_list=$(tmux list-sessions | grep $SESSION)

if [ -z "$sesson_list" ]
then
  lines="$(tput lines)"
  columns="$(tput cols)"

  # Start a new session
  tmux new-session -d -x "$columns" -y "$lines" -s "$SESSION"

  # Setup Window 1
  tmux rename-window 'neovim'
  tmux send-keys -t "$SESSION:1" "nvim" C-m

  # Setup remote
  tmux new-window -t "$SESSION" -n "remote"
  tmux select-window -t "$SESSION:2"
  tmux split-window -h "zsh"
  tmux split-window -v "zsh"
  tmux send-keys -t 2 "cmatrix -bC cyan" C-m
  tmux select-pane -t 1

fi

tmux attach-session -t "$SESSION"
