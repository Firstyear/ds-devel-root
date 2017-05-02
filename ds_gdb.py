import gdb
import re

thread_extract = re.compile('\*?\s+(?P<tid>\d*)\s*Thread (?P<taddr>[\dxabcdef]+) \(LWP (?P<tpid>\d+)\)')

# Known idle states:
# #4  0x0000000000417e7e in connection_wait_for_new_work (pb=pb@entry=0x7fc2c80008c0, interval=interval@entry=4294967295) at /home/william/development/389ds/ds/ldap/servers/slapd/connection.c:968
# #3  0x00007fc38d2c7c24 in work_q_wait (tp=0x22a2000) at /home/william/development/389ds/ds/src/nunc-stans/ns/ns_thrpool.c:321
# #1  0x00007fc38ce5460a in DS_Sleep (ticks=ticks@entry=250) at /home/william/development/389ds/ds/ldap/servers/slapd/util.c:1060
thread_idle = re.compile('.*#\d*\s+[\dxabcdef]+ in ((connection_wait_for_new_work)|(work_q_wait)|(DS_Sleep)).*')

def _display_access_log():
    print('===== BEGIN ACCESS LOG =====')
    gdb.execute('set print elements 0')
    o = gdb.execute('p loginfo.log_access_buffer.top', to_string=True)
    for l in o.split('\\n'):
        print(l)
    print('===== END ACCESS LOG =====')

def _parse_thread_state(t):
    # Get the thread frame state.
    # Is it asleep in a known function?
    alive = False
    o = gdb.execute('thread apply %s bt' % t['tid'], to_string=True)
    if thread_idle.match(o.replace('\n', '')) is None:
        print(o)
        # Do a deadlock check?
    else:
        print("Thread %s (Thread %s (LWP %s)) -- INACTIVE" % (t['tid'], t['taddr'], t['tpid']))
    #    print("INACTIVE")
    #    print(o)
    return True

def _display_active_threads():
    print('===== BEGIN ACTIVE THREADS =====')
    o = gdb.execute('info threads', to_string=True)
    # Each line should have the format:
    # Id Target Frame
    # Extract these out to a list of threads.
    raw_threads = o.split('\n')
    raw_threads = raw_threads[1:]
    proc_threads = []
    # Now split this up into use information.
    for thread in raw_threads:
        reresult = thread_extract.match(thread)
        if reresult is not None:
            proc_threads.append(reresult.groupdict())
    for t in proc_threads:
        _parse_thread_state(t)

    print('===== END ACTIVE THREADS =====')

# Show the active threads
_display_active_threads()

# Show the log buffer.
_display_access_log()


