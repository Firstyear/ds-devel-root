#!/usr/bin/python

import getpass
import base64
import hashlib

rawpw = getpass.getpass("Enter Password: ")

h = hashlib.new('md4', rawpw.encode('utf-16le')).digest()

print("ntUserNtPassword:: %s" % base64.b64encode(h))



