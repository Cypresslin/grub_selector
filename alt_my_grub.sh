#!/bin/bash
#
# A script that helps you to select a different kernel to boot on your Ubuntu system.
# https://github.com/Cypresslin/alt_my_grub
#
#                              Author: Po-Hsu Lin <po-hsu.lin@canonical.com>

grubcfg="/boot/grub/grub.cfg"
grubfile="/etc/default/grub"
end_pattern="### END /etc/grub.d/30_os-prober ###"
one_time=false

function filecheck {
    if [ ! -f $1 ]; then
        echo "$1 not found, please change the setting"
        exit 1
    fi
}

function helpmsg {
    echo "Usage: bash alt_my_grub.sh [options]"
    echo ""
    echo "Options:"
    echo -e "  -h | --help\t\tPrint this help message and exit"
    echo -e "  -r | --restore\tRestore the grub backup file"
    echo -e "  -y | --yes\t\tReply YES to the 'I understand the risk' question"
    echo -e "  --once\t\tBoot to the desired option for next reboot only"
}

# Flag parser
while [[ $# > 0 ]]
do
    flag="$1"
    case $flag in
        -h | --help)
        helpmsg
        exit 0
        ;;
        -r | --restore)
        echo "Trying to restore the grub backup file (grub-bak)"
        if [ -f grub-bak ] && filecheck $grubfile; then
            echo "Copy grub-bak to $grubfile"
            sudo cp grub-bak $grubfile
            sudo update-grub
            echo "Job done, please reboot now."
        else
            echo "Backup file grub-bak not found, aborted"
        fi
        exit 0
        ;;
        -y | --yes)
        echo "You won't be asked to answer the 'I understand the risk' question."
        ans="y"
        shift
        ;;
        --once)
        echo "Running in one-time task mode"
        one_time=true
        shift
        ;;
        *)
        echo "ERROR: Unknown option"
        helpmsg
        exit 1
        ;;
    esac
done

filecheck $grubcfg
filecheck $grubfile
# Find menuentries and submenu, unify the quote and extract the title
rawdata=`grep -e 'menuentry ' -e 'submenu ' "$grubcfg"`
output=`echo "$rawdata" |sed "s/'/\"/g" | cut -d '"' -f2`
# Get the line index of submenu
subidx=`echo "$rawdata" | grep -n 'submenu ' | awk -F':' '{print $1}'`
# As grep -n return 1-based number, subidx needs to -1 for 0-based bash array
# But don't do it here, as the return value is not alway one value

# The submenu will eventually ends before "### END /etc/grub.d/30_os-prober ###"
endidx=`grep -e "menuentry " -e "submenu " -e "$end_pattern" "$grubcfg" | grep -n "$end_pattern" | awk -F':' '{print $1}'`
endidx=$((endidx-1))

# Split results into array
IFS=' '
readarray -t entries <<<"$output"

idx=0
echo "Available menuentries:"
for entry in "${entries[@]}"
do
    # Use grep -w for the idx check, idx+1 as subidx wan't modified
    echo "$subidx" | grep -w "$((idx+1))" > /dev/null
    if [ $? -eq 0 ]; then
        echo "-" $entry
    else
        echo "$idx" $entry
    fi
    idx=$((idx+1))
done
idx=$((idx-1))

read -p "Please select the desired one [0-$idx]: " opt
# Check option availability
if [ "$opt" -eq "$opt" ] 2>/dev/null ; then
    if [ $opt -gt $idx ];then
        echo "ERROR: index out of range."
        exit 1
    elif [ `echo "$subidx" | grep -w "$((opt+1))"` ]; then
        echo "ERROR: This is a submenu, please select other options"
        exit 1
    fi
else
    echo "ERROR: please enter number from 0 - $idx"
    exit 1
fi

subidx=`echo $subidx | tr '\n' ' '`
menuid=""
for i in $subidx
do
    if [ $opt -gt $((i-1)) ] && [ $opt -lt $endidx ]; then
        menuid=$((i-1))
    fi
done
if [ ! -z "$menuid" ]; then
    target="'${entries[$menuid]}>${entries[$opt]}'"
else
    target="'${entries[$opt]}'"
fi
echo "Selected: $target"
echo "==========================================="
echo "The following operation needs root access"
echo "It will backup $grubfile first, and"
echo "make changes to the GRUB_DEFAULT if needed"
echo "==========================================="
if [ "$ans" == "y" ]; then
    echo "YES I understand the risk."
else
    read -p "I understand the risk (y/N): " ans
fi

case $ans in
    "Y" | "y")
        grep "^GRUB_DEFAULT=saved" $grubfile > /dev/null
        if [ $? -ne 0 ]; then
            echo "Backing up your grub file to ./grub-bak"
            cp "$grubfile" ./grub-bak
            echo "Changing GRUB_DEFAULT to 'saved' in $grubfile"
            sudo sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/" $grubfile
            sudo update-grub
        fi
        if [ $one_time = true ]; then
            echo "Setting up one-time task with grub-reboot..."
            cmd="sudo grub-reboot $target"
            eval $cmd
        else
            echo "Setting up default boot option with grub-set-default..."
            cmd="sudo grub-set-default $target"
            eval $cmd
        fi
        echo "Job done, please reboot now."
        ;;
    *)
        echo "User aborted."
        ;;
esac
