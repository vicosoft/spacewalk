#!/usr/bin/python
import xmlrpclib

SATELLITE_URL = "https://SERVER/rpc/api"
SATELLITE_LOGIN = "migracion"
SATELLITE_PASSWORD = "PASSWORD"

client = xmlrpclib.Server(SATELLITE_URL, verbose=0)

key = client.auth.login(SATELLITE_LOGIN, SATELLITE_PASSWORD)
list = client.user.list_users(key)
deleteSystem = client.system.deleteSystem("SERVER_TO_DELETE")
for user in list:
   print user.get('login')

print(deleteSystem)

client.auth.logout(key)
    

