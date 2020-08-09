#!/bin/bash

yum -y install /tmp/avni-server.rpm 2>&1 >/dev/null

mv /tmp/avni.conf /etc/openchs/openchs.conf 2>&1 >/dev/null
service openchs start 2>&1 >/dev/null

unzip /tmp/avni-webapp.zip -d /opt/openchs-webapp

sleep 20

while true
do
    echo "Press [CTRL+C] to stop the server"
    sleep 5
done
