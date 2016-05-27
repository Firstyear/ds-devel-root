# ds-devel-root
389-ds helper make files and tools. Will build a DS env wherever you check it out to! 

# Howto:

clone this repository to some location:

```
git clone https://github.com/Firstyear/ds-devel-root.git 389ds
cd 389ds
```

Now you can grab and build the deps.

```
make clone-anon
# For Fedora Rawhide
make builddeps-fedora
# For RHEL7
make builddeps-el7
```

Finally, you can now build the parts of DS that you want. You can twiddle the settings at the top of the makefile to change the build effects.

All outputs are configured to go to /opt/dirsrv by default.

For example, you may do:

```
make ds
make ds-setup
```

This will build a basic local host instance for cn=Directory Manager:password.

You can try out the new installer and rest server

```
make ds
make ds-setup-py
```

You can even build rpms for your systems:

```
make rpms
```

