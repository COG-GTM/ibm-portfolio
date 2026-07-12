#!/bin/bash
# Runs automatically by the DB2 container entrypoint after the TRADER database
# is created (scripts in /var/custom are executed post-setup).
su - db2inst1 -c "db2 connect to trader && db2 -tvf /var/custom-ddl/createTables.ddl && db2 terminate"
