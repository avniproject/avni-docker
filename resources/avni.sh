#!/bin/bash

yum -y install /tmp/avni-server.rpm 2>&1 >/dev/null

mv /tmp/avni.conf /etc/openchs/openchs.conf 2>&1 >/dev/null
service openchs start 2>&1 >/dev/null

unzip /tmp/avni-webapp.zip -d /opt/openchs-webapp
cd /opt/openchs
git clone https://github.com/avniproject/avni-canned-reports.git
source ~/.bashrc
nvm install v14.16.0
cd avni-canned-reports
yarn install
REACT_APP_DEV_ENV_USER=user@test yarn start

sleep 20

while true
do
    echo "Server started successfully. Visit http://localhost:8021"
    sleep 5
done
