#!/bin/bash
#
# This script will stop all Unraid VMs and rsync the specified src directories to
# the specified dst directory. All src directories will be base64 encoded with
# hostname and directory path to eliminate potential naming collisions and
# the need for character escapes. This will complicate restoration of
# backup data. The following illustrates what will be written and how to decode
# the base64 string.
#
# # echo $SRC
# /mnt/disks/src/domains/
# # echo $DST
# /mnt/user0/Backup/domains
# # hostname -f
# localhost
# # pwd
# /mnt/user0/Backup/domains
# # ls
# bG9jYWxob3N0Oi9tbnQvZGlza3Mvc3JjL2RvbWFpbnMvCg==/
# # echo "bG9jYWxob3N0Oi9tbnQvZGlza3Mvc3JjL2RvbWFpbnMvCg==" | base64 --decode
# localhost:/mnt/disks/src/domains/
#
# Array of source directories with trailing forward slash
declare -a SRC=(
  "/mnt/disks/src/domains/"
  )
# Destination directory without trailing forward slash
DST="/mnt/user0/Backup/domains"
# Timeout in seconds for waiting for vms to shutdown before failing
TIMEOUT=300

# Stop all VMs
STOP() {
  for i in `virsh list | grep running | awk '{print $2}'`; do
    virsh shutdown $i
  done
}

# Start all VMs flagged with autostart
START() {
  for i in `virsh list --all --autostart|awk '{print $2}'|grep -v Name`; do
    virsh start $i
  done
}

# Wait for VMs to shutdown
WAIT() {
  TIME=$(date -d "$TIMEOUT seconds" +%s)
  while [ $(date +%s) -lt $TIME ]; do
  	# Break while loop when no domains are left.
  	test -z "`virsh list | grep running | awk '{print $2}'`" && break
  	# Wait a little, we don't want to DoS libvirt.
  	sleep 1
  done
}

RSYNC() {
  rsync -avhrW "$1" "$2"
  STATUS=$?
}

QUIT() {
  exit
}

NOTIFY() {
  /usr/local/emhttp/webGui/scripts/notify \
  -i "$1" \
  -e "VM Backup" \
  -s "-- VM Backup --" \
  -d "$2"
}

NOTIFY "normal" "Beginning VM Backup"
STOP
WAIT

if [[ $(virsh list | grep running | awk '{print $2}') -ne 0 ]] ; then
  NOTIFY "alert" "VMs Failed to Shutdown. Restarting VMs and Exiting."
  START
  QUIT
fi

for i in "${SRC[@]}"; do
  RSYNC "$i" "$DST/$(echo `hostname -f`:$i | base64)"
  if ! [[ $STATUS -eq 0 ]] ; then
    NOTIFY "warning" "Rsync of $i return exit code $STATUS."
  fi
done

START
NOTIFY "normal" "Completed VM Backup."
QUIT
