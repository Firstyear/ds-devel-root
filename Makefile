.PHONY: ds-setup lib389 rest389

DEVDIR ?= $(shell pwd)
LIB389_VERS ?= $(shell cat ./lib389/VERSION | head -n 1)
REST389_VERS ?= $(shell cat ./rest389/VERSION | head -n 1)

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

lib389:
	cd $(DEVDIR)/lib389/ && python setup.py build
	cd $(DEVDIR)/lib389/ && sudo python setup.py install --force --root=/

lib389-rpmbuild-prep:
	mkdir -p ~/rpmbuild/SOURCES
	mkdir -p ~/rpmbuild/SPECS
	#cd $(DEVDIR)/lib389/ && sudo python setup.py sdist --formats=bztar
	#cp $(DEVDIR)/lib389/dist/*.tar.bz2 ~/rpmbuild/SOURCES/
	# This needs to be less shit, but there is a bug in rename.
	#rename 1.tar.bz2 1-1.tar.bz2 ~/rpmbuild/SOURCES/python-lib389*
	cd $(DEVDIR)/lib389/ && git archive --prefix=python-lib389-$(LIB389_VERS)-1/ HEAD | bzip2 > $(DEVDIR)/lib389/dist/python-lib389-$(LIB389_VERS)-1.tar.bz2
	cp $(DEVDIR)/lib389/dist/*.tar.bz2 ~/rpmbuild/SOURCES/

lib389-srpms: lib389-rpmbuild-prep
	rpmbuild -bs $(DEVDIR)/lib389/python-lib389.spec
	cp ~/rpmbuild/SRPMS/python-lib389*.src.rpm $(DEVDIR)/lib389/dist/

lib389-rpms: lib389-rpmbuild-prep
	rpmbuild -bb $(DEVDIR)/lib389/python-lib389.spec

nunc-stans-configure:
	mkdir -p ~/build/nunc-stans
	cd ~/build/nunc-stans && $(DEVDIR)/nunc-stans/configure --prefix=/opt/dirsrv/

nunc-stans: nunc-stans-configure
	make -C ~/build/nunc-stans/
	sudo make -C ~/build/nunc-stans/ install
	sudo cp $(DEVDIR)/nunc-stans/liblfds/bin/* /opt/dirsrv/lib/

ds-configure:
	
	cd $(DEVDIR)/ds && autoreconf
	mkdir -p ~/build/ds/
	cd ~/build/ds/ && $(DEVDIR)//ds/configure --enable-gcc-security --enable-asan --with-openldap --enable-debug --with-nunc-stans=/opt/dirsrv/ --enable-nunc-stans  --prefix=/opt/dirsrv/

ds: lib389 nunc-stans ds-configure
	make -C ~/build/ds
	sudo make -C ~/build/ds install
	sudo cp $(DEVDIR)/start-dirsrv-asan /opt/dirsrv/sbin/start-dirsrv

ds-rpms: ds-configure
	make -C ~/build/ds rpms

ds-srpms: ds-configure
	make -C ~/build/ds srpm

ds-setup:
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=$(DEVDIR)/setup.inf General.FullMachineName=$$(hostname)

rest389: lib389
	cd $(DEVDIR)/rest389/ && python setup.py build
	cd $(DEVDIR)/rest389/ && sudo python setup.py install --force --root=/

rest389-rpmbuild-prep:
	mkdir -p ~/rpmbuild/SOURCES
	mkdir -p ~/rpmbuild/SPECS
	# This needs to be less shit, but there is a bug in rename.
	#rename 1.tar.bz2 1-1.tar.bz2 ~/rpmbuild/SOURCES/python-lib389*
	cd $(DEVDIR)/rest389/ && git archive --prefix=python-rest389-$(REST389_VERS)-1/ HEAD | bzip2 > $(DEVDIR)/rest389/dist/python-rest389-$(REST389_VERS)-1.tar.bz2
	cp $(DEVDIR)/rest389/dist/*.tar.bz2 ~/rpmbuild/SOURCES/

rest389-srpms: rest389-rpmbuild-prep
	rpmbuild -bs $(DEVDIR)/rest389/python-rest389.spec
	sudo cp ~/rpmbuild/SRPMS/python-rest389*.src.rpm $(DEVDIR)/rest389/dist/

rest389-rpms: rest389-rpmbuild-prep
	rpmbuild -bb $(DEVDIR)/rest389/python-rest389.spec

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git
	git clone ssh://git.fedorahosted.org/git/nunc-stans.git
	git clone ssh://git.fedorahosted.org/git/389/lib389.git
	git clone ssh://git.fedorahosted.org/git/389/rest389.git

pull:
	cd ds; git pull
	cd lib389; git pull
	cd rest389; git pull

github-commit:
	cd ds; git push github --all --force
	cd lib389; git push github --all --force
	cd rest389; git push github --all --force

srpms: ds-srpms lib389-srpms rest389-srpms

copr:
	# Upload all the sprms to copr as builds
	copr-cli build lib389 --nowait `ls -1 $(DEVDIR)/lib389/dist/python-lib389*.src.rpm | head`
	copr-cli build ds --nowait `ls -1 $(DEVDIR)/rpmbuild/SRPMS/*.src.rpm | head`
	copr-cli build rest389 --nowait `ls -1 $(DEVDIR)/rest389/dist/python-rest389*.src.rpm | head`


