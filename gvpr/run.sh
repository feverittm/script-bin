#!/bin/sh

script=$0
link=$(ls -ld $0 | awk '{print $NF}')
case $link in
  /*) script=$link ;;
  *)  script=$(dirname $script)/$link ;;
esac

export GPRPATH=$(dirname $script)

exec gvpr -f $(basename $0).gvpr ${1+-a "$*"}
