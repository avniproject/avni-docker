#!/bin/bash

function wait_emulator_to_be_ready() {
  adb devices | grep emulator | cut -f1 | while read line; do adb -s $line emu kill; done
  emulator @test -verbose -memory 3000 -gpu swiftshader_indirect -no-audio -no-boot-anim &

boot_completed=false
  while [ "$boot_completed" == false ]; do
    status=$(adb wait-for-device shell getprop sys.boot_completed | tr -d '\r')
    echo "Boot Status: $status"

    if [ "$status" == "1" ]; then
      echo "Boot completed"
      boot_completed=true
      sleep 5
      echo "Installing the app"
      adb install /home/avni.apk
      echo "App installation completed connect with VNC"
    else
      sleep 1
    fi
  done
}

vncserver :1 -geometry 1280x1280 -depth 24 -alwaysshared
sleep 5

wait_emulator_to_be_ready
sleep 1

while true
do
    echo "connect with VNC to view the emulator"
    sleep 5
done
