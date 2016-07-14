# --- BEGIN COPYRIGHT BLOCK ---
# Copyright (C) 2016 Red Hat, Inc.
# All rights reserved.
#
# License: GPL (version 3 or any later version).
# See LICENSE for details.
# --- END COPYRIGHT BLOCK ---
#

import os
import sys
import time
import ldap
import logging
import pytest
import signal
import threading
from ldap.ldapobject import SimpleLDAPObject
from lib389 import DirSrv
from lib389._constants import *
from lib389.properties import *

MAX_CONNS = 10000000
MAX_THREADS = 20
STOP = False


def signalHandler(signal, frame):
    """
    handle control-C cleanly
    """
    global STOP
    STOP = True
    sys.exit(0)


def openConnection(host, port, binddn="", passwd=""):
    """Open a new connection to an LDAP server"""
    uri = "ldap://%s:%d/" % (host, port)
    server = ldap.initialize(uri)
    server.simple_bind_s(binddn, passwd)

    return server


class BindOnlyConn(threading.Thread):
    """This class opens and closes connections to a specified server
    """
    def __init__(self, host='localhost', port=389, binddn=None, passwd=None):
        """Initialize the thread class withte server isntance info"""
        threading.Thread.__init__(self)
        self.daemon = True
        self.host = host
        self.port = port
        self.binddn = binddn
        self.passwd = passwd

    def run(self):
        """Keep opening and closing connections"""
        global STOP
        idx = 0
        while idx < MAX_CONNS and not STOP:
            try:
                conn = openConnection(self.host, self.port, self.binddn,
                                      self.passwd)
                conn.unbind_s()
                time.sleep(.2)
            except:
                return
            idx += 1


class IdleConn(threading.Thread):
    """This class opens and closes connections to a specified server
    """
    def __init__(self, host='localhost', port=389, binddn=None, passwd=None):
        """Initialize the thread class withte server isntance info"""
        threading.Thread.__init__(self)
        self.daemon = True
        self.host = host
        self.port = port
        self.binddn = binddn
        self.passwd = passwd

    def run(self):
        """Assume idleTimeout is set to less than 10 seconds
        """
        global STOP
        idx = 0
        while idx < (MAX_CONNS / 10) and not STOP:
            try:
                conn = openConnection(self.host, self.port, self.binddn,
                                      self.passwd)
                conn.search_s('dc=example,dc=com', ldap.SCOPE_SUBTREE,
                              'uid=*')
                time.sleep(10)
                conn.search_s('dc=example,dc=com', ldap.SCOPE_SUBTREE,
                              'cn=*')
                conn.unbind_s()
            except:
                return
            idx += 1


class LongConn(threading.Thread):
    """This class opens and closes connections to a specified server
    """
    def __init__(self, host='localhost', port=389, binddn=None, passwd=None):
        """Initialize the thread class with the server instance info"""
        threading.Thread.__init__(self)
        self.daemon = True
        self.host = host
        self.port = port
        self.binddn = binddn
        self.passwd = passwd

    def run(self):
        """Assume idleTimeout is set to less than 10 seconds
        """
        global STOP
        idx = 0
        while idx < MAX_CONNS and not STOP:
            try:
                conn = openConnection(self.host, self.port, self.binddn,
                                      self.passwd)
                conn.search_s('dc=example,dc=com', ldap.SCOPE_SUBTREE,
                              'objectclass=*')
                conn.search_s('dc=example,dc=com', ldap.SCOPE_SUBTREE,
                              'uid=test0001')
                conn.search_s('dc=example,dc=com', ldap.SCOPE_SUBTREE,
                              'cn=*')
                conn.search_s('', ldap.SCOPE_BASE, 'objectclass=*')
                conn.unbind_s()
                time.sleep(.2)
            except:
                return
            idx += 1


def test_connection_load():
    """Start a bunch of threads that are going to open and close connections"""

    # setup the control-C signal handler
    signal.signal(signal.SIGINT, signalHandler)

    #
    # Bind/Unbind Conn Threads
    #
    threads = []
    idx = 0
    while idx < MAX_THREADS:
        threads.append(BindOnlyConn(binddn='uid=test0001,dc=example,dc=com',
                            passwd='password0001'))
        idx += 1

    for thread in threads:
        thread.start()

    #
    # Idle Conn Threads
    #
    idx = 0
    idle_threads = []
    while idx < 10:
        idle_threads.append(IdleConn(binddn='uid=test0001,dc=example,dc=com',
                                     passwd='password0001'))
        idx += 1

    for thread in idle_threads:
        thread.start()

    #
    # Long Conn Threads
    #
    idx = 0
    long_threads = []
    while idx < 10:
        long_threads.append(LongConn(binddn='cn=Directory Manager',
                                     passwd='password'))
        idx += 1
    for thread in long_threads:
        thread.start()

    #
    # Now wait for all the threads to complete
    #

    while threading.active_count() > 0:
        time.sleep(0.1)

    print "Done"


if __name__ == '__main__':
    # Run isolated
    # -s for DEBUG mode
    CURRENT_FILE = os.path.realpath(__file__)
    pytest.main("-s %s" % CURRENT_FILE)
