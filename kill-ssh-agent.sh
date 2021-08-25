#!/bin/sh

if [ -n "SSH_AGENT_PID" ]
then
   echo "...kill ssh-agent: $SSH_AGENT_PID"
   ssh-agent -k
fi
