
TEMPLATE = """
dn: uid=test{id:07d},dc=example,dc=com
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: guest{id:07d}
sn: guest{id:07d}
uid: guest{id:07d}
givenname: givenname{id:07d}
description: description{id:07d}
userPassword: password{id:07d}
mail: uid{id:07d}
uidnumber: 1
gidnumber: 1
shadowMin: 0
shadowMax: 99999
shadowInactive: 30
shadowWarning: 7
homeDirectory: /home/uid{id:07d}"""

for i in range(1,1000001):
    print(TEMPLATE.format(id=i))


