#!/bin/bash
#
# Upload the file erratas to spacewalk server
#
export SPACEWALK_USER='admin'
export SPACEWALK_PASS='PASSWORD'
./errata-import.pl --server IPADDRESS --errata errata.latest.xml --rhsa-oval com.redhat.rhsa-all.xml
