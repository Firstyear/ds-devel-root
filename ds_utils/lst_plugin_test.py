import os
import sys
import time
import ldap
from ldap.ldapobject import SimpleLDAPObject
import logging
import pytest
from lib389 import DirSrv, Entry, tools, tasks
from lib389.tools import DirSrvTools
from lib389._constants import *
from lib389.properties import *
from lib389.tasks import *
from lib389.utils import *
from lib389.plugins import LdapSSOTokenPlugin
from lib389.extended_operations import LdapSSOTokenRequest, LdapSSOTokenResponse, LdapSSOTokenRevokeRequest
from lib389.sasl import LdapSSOTokenSASL

DEBUGGING = True

if DEBUGGING:
    logging.getLogger(__name__).setLevel(logging.DEBUG)
else:
    logging.getLogger(__name__).setLevel(logging.INFO)


log = logging.getLogger(__name__)

PW = 'password'
USER1_DN = 'uid=user1,ou=People,%s' % DEFAULT_SUFFIX
USER1 = 'user1'

USER2_DN = 'uid=user2,ou=People,%s' % DEFAULT_SUFFIX
USER2 = 'user2'

class TopologyStandalone(object):
    """The DS Topology Class"""
    def __init__(self, standalone):
        """Init"""
        standalone.open()
        self.standalone = standalone


@pytest.fixture(scope="module")
def topology(request):
    """Create DS Deployment"""

    # Creating standalone instance ...
    if DEBUGGING:
        standalone = DirSrv(verbose=True)
    else:
        standalone = DirSrv(verbose=False)
    args_instance[SER_HOST] = HOST_STANDALONE
    args_instance[SER_PORT] = PORT_STANDALONE
    args_instance[SER_SERVERID_PROP] = SERVERID_STANDALONE
    args_instance[SER_CREATION_SUFFIX] = DEFAULT_SUFFIX
    args_standalone = args_instance.copy()
    standalone.allocate(args_standalone)
    instance_standalone = standalone.exists()
    if instance_standalone:
        standalone.delete()
    standalone.create()
    standalone.open()

    def fin():
        """If we are debugging just stop the instances, otherwise remove
        them
        """
        if DEBUGGING:
            standalone.stop(60)
        else:
            standalone.delete()

    request.addfinalizer(fin)

    # Clear out the tmp dir
    standalone.clearTmpDir(__file__)

    return TopologyStandalone(standalone)

def _create_user(inst, name, dn):
    inst.add_s(Entry((
                dn, {
                    'objectClass': 'top account simplesecurityobject'.split(),
                     'uid': name,
                     'userpassword': PW
                })))

def _request_token(inst, timeout=0):
    token_request = LdapSSOTokenRequest(timeout)
    response = inst.extop_s(token_request,extop_resp_class=LdapSSOTokenResponse)
    return response.token

def test_lst_plugin(topology):
    """
    Test the functionality of the LdapSSOToken plugin.

    This will assert the conditions of the draft RFC are upheld.

    You should probably be reading:
        https://tools.ietf.org/html/draft-wibrown-ldapssotoken-01
    """
    #Create the plugin on the server
    lst_plugin = LdapSSOTokenPlugin(topology.standalone)
    lst_plugin.create()
    lst_plugin.enable()
    # Restart the server
    topology.standalone.stop()
    # Prepare SSL but don't enable it.
    for f in ('key3.db', 'cert8.db', 'key4.db', 'cert9.db', 'secmod.db', 'pkcs11.txt'):
        try:
            os.remove("%s/%s" % (topology.standalone.confdir, f))
        except:
            pass
    assert(topology.standalone.nss_ssl.reinit() is True)
    assert(topology.standalone.nss_ssl.create_rsa_ca() is True)
    assert(topology.standalone.nss_ssl.create_rsa_key_and_cert() is True)

    # Start again
    topology.standalone.start()
    # topology.standalone.encryption.create()
    topology.standalone.rsa.create()
    # Set the secure port and nsslapd-security
    # Could this fail with selinux?
    # topology.standalone.config.set('nsslapd-secureport', '38936')
    topology.standalone.config.set('nsslapd-security', 'on')

    # Check the extended op oids and sasl mech are present
    assert(topology.standalone.rootdse.supports_sasl_ldapssotoken())
    assert(topology.standalone.rootdse.supports_exop_ldapssotoken_request())
    assert(topology.standalone.rootdse.supports_exop_ldapssotoken_revoke())
    # Create a user to use for the remainder of the test.
    _create_user(topology.standalone, USER1, USER1_DN)
    _create_user(topology.standalone, USER2, USER2_DN)
    # First, attempt to get the token with no SSF, even as Directory Manager.
    with pytest.raises(ldap.UNWILLING_TO_PERFORM):
        _request_token(topology.standalone)
    # Create and setup SSL now so we can satisfy the SSF checks.
    # Restart the server
    topology.standalone.restart()
    # Get a new connection

    # We have to use CACERTDIR because this uses NSS underneath.
    # These options are just BROKEN and IGNORED unless you set them on ldap.
    ldap.set_option(ldap.OPT_X_TLS_CACERTDIR, '%s/' % topology.standalone.confdir)
    test_connection = ldap.initialize(topology.standalone.toLDAPURL())
    # test_connection.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER)

    test_connection.start_tls_s()
    test_connection.simple_bind_s()

    # Now we are anonymous, we should fail to request AND revoke.
    with pytest.raises(ldap.UNWILLING_TO_PERFORM):
        _request_token(test_connection)

    # Okay, now we bind as a proper account
    test_connection.simple_bind_s(USER1_DN, PW)
    # Now we should be able to retrieve a token.
    token = _request_token(test_connection)
    assert(token is not None)

    # Right, we have the token. Lets see if we can bind!
    new_connection = ldap.initialize(topology.standalone.toLDAPURL())
    # First, bind without TLS. This must fail!
    sasl_token = LdapSSOTokenSASL(token)
    with pytest.raises(ldap.UNWILLING_TO_PERFORM):
        new_connection.sasl_interactive_bind_s("", sasl_token)
    # Now, bind with TLS. This will work.
    new_connection.start_tls_s()
    new_connection.sasl_interactive_bind_s("", sasl_token)
    # Unbind, and bind with a bit flipped in the token. Should fail!


    # Revoke the token
    # Now try to bind again. Must fail!


if __name__ == '__main__':
    # Run isolated
    # -s for DEBUG mode
    CURRENT_FILE = os.path.realpath(__file__)
    pytest.main("-s %s" % CURRENT_FILE)

