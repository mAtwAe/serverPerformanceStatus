#!/bin/bash

total_CPU_usage(){
    echo "---------CPU Usage----------"
    top -bn1 | grep "%Cpu(s)" | \
    cut -d ',' -f 4 | \
    awk '{print "CPU Usage: " 100-$1 "%"}'
}

total_memory_usage(){
    echo "--------Total memory usage-----------"
    free  | grep "Mem" | \
    awk '{printf "Total: %sG\nUsed: %.1fGi (%.2f%%)\nFree: %.1fGi (%.2f%%)\n", $2/1024^2 , $3/1024^2, $3/$2*100, $4/1024^2, $4/$2*100}'
}

total_disk_usage(){
    echo "--------Total disk usage-----------"
    df -h --total | grep "total" | \
    #if you want to include all filesystems, remove the grep "total" part 
    #if for wsl use df -h /mnt/c | grep -E "Filesystem|total"
    awk '{printf "Total: %s\nUsed: %s (%.2f%%)\nFree: %s (%.2f%%)\n", $2, $3, $3/$2*100, $4, $4/$2*100}'
}

top_processes_by_cpu(){
    echo "--------Top 5 processes by CPU usage-----------"
    ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 6
}

top_processes_by_memory(){
    echo "--------Top 5 processes by memory usage-----------"
    ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -n 6
}

os_version(){
    echo "--------OS Version-----------"
    uname -a
}

show_uptime(){
    echo "--------Uptime-----------"
    uptime | awk -F'up ' '{ print $2 }' | awk -F', ' '{ print $1 }'
}

load_average(){
    echo "--------Load Average-----------"
    uptime | awk -F'load average:' '{ print $2 }' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

get_logging_user(){
    echo "--------Logged in users-----------"
    who | awk '{print $1}' | sort | uniq
}

fail_loqging_user(){
    echo "--------Failed login attempts-----------"
    lastb | head -n 10
}

main(){
    os_version
    total_CPU_usage
    total_memory_usage
    total_disk_usage
    top_processes_by_cpu
    top_processes_by_memory
    show_uptime
    load_average
    # get_logging_user
    # fail_logging_user
}

main