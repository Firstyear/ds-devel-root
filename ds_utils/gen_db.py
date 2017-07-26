
#  /opt/dirsrv/bin/ldclt -h localhost -p 389 -n 30 -N 10 -D "cn=Directory Manager" -w password -e esearch,random -r0 -R999999 -e attrlist=cn -f '(&(objectClass=groupOfUniqueNames)(uniqueMember=uid=uXXXXXX,ou=People,dc=example,dc=com))'


header = """version: 1

# entry-id: 1
dn: dc=example,dc=com
objectClass: top
objectClass: domain
dc: example

# entry-id: 2
dn: ou=People,dc=example,dc=com
objectClass: top
objectClass: organizationalUnit
ou: People

# entry-id: 3
dn: ou=Groups,dc=example,dc=com
objectClass: top
objectClass: organizationalUnit
ou: Groups

"""

group_template = """# entry-id: {ENTRYID}
dn: cn=g{GID:06d},ou=Groups,dc=example,dc=com
objectClass: top
objectClass: groupOfUniqueNames
cn: g{GID:06d}
"""

group_member_template = """uniqueMember: uid=u{UID:06d},ou=People,dc=example,dc=com
"""

user_template = """# entry-id: {ENTRYID}
dn: uid=u{UID:06d},ou=People,dc=example,dc=com
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: u{UID:06d}
sn: u{UID:06d}
uid: u{UID:06d}
givenname: u{UID:06d}
description: u{UID:06d}
userPassword: passwordu{UID:06d}
mail: u{UID:06d}@example.com
uidnumber: 1
gidnumber: 1
shadowMin: 0
shadowMax: 99999
shadowInactive: 30
shadowWarning: 7
homeDirectory: /home/u{UID:06d}

"""

GROUP_COUNT = 60000
USER_COUNT = 100000
USER_MEMBERSHIPS = 500

# GROUP_COUNT = 60
# USER_COUNT = 100
# USER_MEMBERSHIPS = 5

# Remember, if a user is in x groups, then (users * x / groups)
# is avg number of users per group.
GROUP_MEMBERS = (USER_COUNT * USER_MEMBERSHIPS) / GROUP_COUNT

import random

if __name__ == '__main__':
    idcount = 4
    with open('output.2db.ldif', 'w') as f:
        f.write(header)
        for i in range(0, USER_COUNT):
            f.write(user_template.format(ENTRYID=idcount, UID=i))
            idcount += 1
        for i in range(0, GROUP_COUNT):
            f.write(group_template.format(ENTRYID=idcount, GID=i))
            uidseed = random.randint(0, USER_COUNT - 1)
            for j in range(0, GROUP_MEMBERS):
                uid = (uidseed + j) % USER_COUNT
                f.write(group_member_template.format(UID=uid))
            f.write("\n")
            idcount += 1







