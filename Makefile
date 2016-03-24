.PHONY: ds-setup lib389 rest389 pyldap

DEVDIR ?= $(shell pwd)
BUILDDIR ?= ~/build
LIB389_VERS ?= $(shell cat ./lib389/VERSION | head -n 1)
REST389_VERS ?= $(shell cat ./rest389/VERSION | head -n 1)

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

clean: ds-clean nunc-stans-clean

pyldap:
	cd $(DEVDIR)/pyldap/ && python setup.py build
	cd $(DEVDIR)/pyldap/ && sudo python setup.py install --force --root=/

lib389:
	make -C $(DEVDIR)/lib389/ build
	sudo make -C $(DEVDIR)/lib389/ install

lib389-rpmbuild-prep:
	make -C $(DEVDIR)/lib389/ rpmbuild-prep

lib389-srpms: lib389-rpmbuild-prep
	make -C $(DEVDIR)/lib389/ srpm

lib389-rpms: lib389-rpmbuild-prep
	make -C $(DEVDIR)/lib389/ rpm

nunc-stans-configure:
	cd $(DEVDIR)/nunc-stans/ && autoreconf --force --install
	mkdir -p $(BUILDDIR)/nunc-stans
	cd $(BUILDDIR)/nunc-stans && $(DEVDIR)/nunc-stans/configure --prefix=/opt/dirsrv

nunc-stans: nunc-stans-configure
	make -C $(BUILDDIR)/nunc-stans/
	sudo make -C $(BUILDDIR)/nunc-stans/ install
	sudo cp $(DEVDIR)/nunc-stans/liblfds/bin/* /opt/dirsrv/lib/

nunc-stans-clean:
	make -C $(BUILDDIR)/nunc-stans/ clean

ds-configure:
	cd $(DEVDIR)/ds && autoreconf
	mkdir -p $(BUILDDIR)/ds/
	cd $(BUILDDIR)/ds/ && CFLAGS=-O0 $(DEVDIR)/ds/configure --with-openldap --enable-debug --with-nunc-stans=/opt/dirsrv --enable-nunc-stans  --prefix=/opt/dirsrv --enable-gcc-security --enable-asan --with-systemd --enable-auto-dn-suffix --enable-autobind

ds: lib389 nunc-stans ds-configure
	make -C $(BUILDDIR)/ds 1> /tmp/buildlog
	sudo make -C $(BUILDDIR)/ds install 1>> /tmp/buildlog
	sudo cp $(DEVDIR)/start-dirsrv-asan /opt/dirsrv/sbin/start-dirsrv

ds-clean:
	make -C $(BUILDDIR)/ds clean

ds-rpms: ds-configure
	make -C $(BUILDDIR)/ds rpmsources
	make -C $(BUILDDIR)/ds rpms

ds-srpms: ds-configure
	make -C $(BUILDDIR)/ds rpmsources
	make -C $(BUILDDIR)/ds srpm
	cp $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

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

# Is there a nicer way to do this?
copr-wait:
	# Upload all the sprms to copr as builds
	copr-cli build lib389 `ls -1r $(DEVDIR)/lib389/dist/python-lib389*.src.rpm | head -n 1`
	copr-cli build rest389 `ls -1r $(DEVDIR)/rest389/dist/python-rest389*.src.rpm | head -n 1`
	copr-cli build ds `ls -1r $(DEVDIR)/rpmbuild/SRPMS/*.src.rpm | head -n 1`

copr:
	# Upload all the sprms to copr as builds
	copr-cli build lib389 --nowait `ls -1r $(DEVDIR)/lib389/dist/python-lib389*.src.rpm | head -n 1`
	copr-cli build rest389 --nowait `ls -1r $(DEVDIR)/rest389/dist/python-rest389*.src.rpm | head -n 1`
	copr-cli build ds --nowait `ls -1r $(DEVDIR)/rpmbuild/SRPMS/*.src.rpm | head -n 1`

