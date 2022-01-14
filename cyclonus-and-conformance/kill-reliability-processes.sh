#!/usr/bin/env bash
## in case you cancel a cyclonus-reliability.sh run, run this to see which processes are still running
echo "cyclonus processes to kill (using sudo to kill them):"
ps aux | grep cyclonus
ps aux | grep cyclonus | awk '{print $2}' | xargs sudo kill -9

echo "processes afterwards:"
ps aux | grep cyclonus
