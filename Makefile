.PHONY: ds-setup lib389 rest389 pyldap

DEVDIR ?= $(shell pwd)
BUILDDIR ?= ~/build
LIB389_VERS ?= $(shell cat ./lib389/VERSION | head -n 1)
REST389_VERS ?= $(shell cat ./rest389/VERSION | head -n 1)
PYTHON ?= /usr/bin/python3

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

builddeps-el7:
	sudo yum install -y rpm-build gcc autoconf make automake libtool libasan rpmdevtools pam-devel libcmocka libcmocka-devel \
		python34 python34-devel python34-setuptools python34-six httpd-devel python-pep8 \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in svrcore/svrcore.spec rest389/python-rest389.spec lib389/python-lib389.spec | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | grep -v "^/"`
	sudo /usr/bin/easy_install-3.4 pip
	sudo pip3.4 install pyasn1 pyasn1-modules flask python-dateutil mod_wsgi
	echo "LoadModule wsgi_module /usr/lib64/python3.4/site-packages/mod_wsgi/server/mod_wsgi-py34.cpython-34m.so" | sudo tee /etc/httpd/conf.modules.d/10-wsgi.conf

builddeps-fedora:
	sudo yum install -y rpm-build gcc autoconf make automake libtool libasan rpmdevtools pam-devel american-fuzzy-lop libcmocka libcmocka-devel \
		python3 python3-devel python3-setuptools python3-six httpd-devel python3-mod_wsgi \
		python3-pyasn1 python3-pyasn1-modules python3-dateutil python3-flask python3-nss python3-pytest python3-pep8 \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in svrcore/svrcore.spec rest389/python-rest389.spec lib389/python-lib389.spec | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | grep -v "^/"`

clean: ds-clean nunc-stans-clean svrcore-clean srpms-clean

pyldap:
	cd $(DEVDIR)/pyldap/ && $(PYTHON) setup.py build
	cd $(DEVDIR)/pyldap/ && sudo $(PYTHON) setup.py install --force --root=/

lib389: pyldap
	make -C $(DEVDIR)/lib389/ build PYTHON=$(PYTHON)
	sudo make -C $(DEVDIR)/lib389/ install PYTHON=$(PYTHON)

lib389-rpmbuild-prep:
	make -C $(DEVDIR)/lib389/ rpmbuild-prep

lib389-srpms: lib389-rpmbuild-prep
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	make -C $(DEVDIR)/lib389/ srpm
	cp $(DEVDIR)/lib389/dist/python-lib389*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

lib389-rpms: lib389-rpmbuild-prep
	make -C $(DEVDIR)/lib389/ rpm
	cp ~/rpmbuild/RPMS/noarch/python-lib389*.rpm $(DEVDIR)/rpmbuild/RPMS/noarch/

nunc-stans-configure:
	cd $(DEVDIR)/nunc-stans/ && autoreconf --force --install
	mkdir -p $(BUILDDIR)/nunc-stans
	cd $(BUILDDIR)/nunc-stans && ASAN_OPTIONS="detect_leaks=0" CFLAGS="-g3 -fsanitize=address -fno-omit-frame-pointer -lasan" $(DEVDIR)/nunc-stans/configure --prefix=/opt/dirsrv
	#cd $(BUILDDIR)/nunc-stans && ASAN_OPTIONS="detect_leaks=0" CFLAGS="-DDEBUG -DDEBUG_FSM -g3 -fsanitize=address -fno-omit-frame-pointer -lasan" $(DEVDIR)/nunc-stans/configure --prefix=/opt/dirsrv

nunc-stans: nunc-stans-configure
	make -C $(BUILDDIR)/nunc-stans/
	sudo make -C $(BUILDDIR)/nunc-stans/ install
	sudo cp $(DEVDIR)/nunc-stans/liblfds/bin/* /opt/dirsrv/lib/

nunc-stans-clean:
	make -C $(BUILDDIR)/nunc-stans/ clean

svrcore-configure:
	cd $(DEVDIR)/svrcore/ && autoreconf --force --install
	mkdir -p $(BUILDDIR)/svrcore
	cd $(BUILDDIR)/svrcore && $(DEVDIR)/svrcore/configure --prefix=/opt/dirsrv --enable-debug --with-systemd #--enable-asan

svrcore: svrcore-configure
	make -C $(BUILDDIR)/svrcore
	sudo make -C $(BUILDDIR)/svrcore install

svrcore-clean:
	make -C $(BUILDDIR)/svrcore clean

svrcore-rpms: svrcore-configure
	make -C $(BUILDDIR)/svrcore rpms
	cp $(BUILDDIR)/svrcore/rpmbuild/RPMS/x86_64/svrcore*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/

svrcore-srpms: svrcore-configure
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	make -C $(BUILDDIR)/svrcore srpm
	cp $(BUILDDIR)/svrcore/rpmbuild/SRPMS/svrcore*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

# Can I improve this to not need svrcore?
ds-configure: 
	cd $(DEVDIR)/ds && autoreconf --force
	mkdir -p $(BUILDDIR)/ds/
	# -Wlogical-op  -Wduplicated-cond  -Wshift-overflow=2  -Wnull-dereference
	cd $(BUILDDIR)/ds/ && CFLAGS="-O0 -Wall -Wextra -Wunused -Wno-unused-parameter" $(DEVDIR)/ds/configure --enable-debug --with-svrcore=/opt/dirsrv --with-nunc-stans=/opt/dirsrv --enable-nunc-stans  --prefix=/opt/dirsrv --enable-gcc-security --with-openldap --enable-asan --enable-auto-dn-suffix --enable-autobind --with-systemd # --with-journald

ds: lib389 svrcore nunc-stans ds-configure
	make -C $(BUILDDIR)/ds 1> /tmp/buildlog
	sudo make -C $(BUILDDIR)/ds install 1>> /tmp/buildlog

ds-clean:
	make -C $(BUILDDIR)/ds clean

ds-rpms: ds-configure
	make -C $(BUILDDIR)/ds rpmsources
	make -C $(BUILDDIR)/ds rpms
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/x86_64/389-ds-base*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/

ds-srpms: ds-configure
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	make -C $(BUILDDIR)/ds rpmsources
	make -C $(BUILDDIR)/ds srpm
	cp $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

ds-setup:
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=$(DEVDIR)/setup.inf General.FullMachineName=$$(hostname)

ds-setup-py: rest389
	sudo /usr/sbin/ds-rest-setup -f /usr/share/rest389/examples/ds-setup-rest-admin.inf --IsolemnlyswearthatIamuptonogood -v

rest389: lib389
	make -C $(DEVDIR)/rest389/ build PYTHON=$(PYTHON)
	sudo make -C $(DEVDIR)/rest389/ install PYTHON=$(PYTHON)

rest389-rpmbuild-prep:
	mkdir -p $(DEVDIR)/rest389/dist
	mkdir -p ~/rpmbuild/SOURCES
	mkdir -p ~/rpmbuild/SPECS
	cd $(DEVDIR)/rest389/ && git archive --prefix=python-rest389-$(REST389_VERS)-1/ HEAD | bzip2 > $(DEVDIR)/rest389/dist/python-rest389-$(REST389_VERS)-1.tar.bz2
	cp $(DEVDIR)/rest389/dist/*.tar.bz2 ~/rpmbuild/SOURCES/

rest389-srpms: rest389-rpmbuild-prep
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	rpmbuild -bs $(DEVDIR)/rest389/python-rest389.spec
	cp ~/rpmbuild/SRPMS/python-rest389*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

rest389-rpms: rest389-rpmbuild-prep
	rpmbuild -bb $(DEVDIR)/rest389/python-rest389.spec
	cp ~/rpmbuild/RPMS/noarch/python-rest389*.rpm $(DEVDIR)/rpmbuild/RPMS/noarch/

idm389: lib389
	make -C $(DEVDIR)/idm389/ build PYTHON=$(PYTHON)
	sudo make -C $(DEVDIR)/idm389/ install PYTHON=$(PYTHON)

idm389-rpmbuild-prep:
	make -C $(DEVDIR)/idm389/ rpmbuild-prep

idm389-srpms: idm389-rpmbuild-prep
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	make -C $(DEVDIR)/idm389/ srpm
	cp $(DEVDIR)/idm389/dist/python-idm389*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

idm389-rpms: idm389-rpmbuild-prep
	make -C $(DEVDIR)/idm389/ rpm
	cp ~/rpmbuild/RPMS/noarch/python-idm389*.rpm $(DEVDIR)/rpmbuild/RPMS/noarch/

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git
	git clone ssh://git.fedorahosted.org/git/nunc-stans.git
	git clone ssh://git.fedorahosted.org/git/389/lib389.git
	git clone ssh://git.fedorahosted.org/git/rest389.git
	git clone ssh://git@github.com:Firstyear/idm389.git
	git clone ssh://git@pagure.io/svrcore.git
	#git clone ssh://github.com/pyldap/pyldap.git

clone-anon:
	git clone https://git.fedorahosted.org/git/389/ds.git
	git clone https://git.fedorahosted.org/git/nunc-stans.git
	git clone https://git.fedorahosted.org/git/389/lib389.git
	git clone https://git.fedorahosted.org/git/rest389.git
	git clone https://github.com/Firstyear/idm389.git
	git clone https://pagure.io/svrcore.git
	git clone https://github.com/pyldap/pyldap.git

pull:
	cd ds; git pull
	cd lib389; git pull
	cd rest389; git pull
	cd idm389; git pull
	cd nunc-stans; git pull
	cd svrcore; git pull
	cd pyldap; git pull

github-commit:
	echo you should be on the master branches here!
	cd ds; git push github master
	cd lib389; git push github master
	cd idm389; git push origin master
	cd rest389; git push github master
	cd svrcore; git push github master
	cd nunc-stans; git push github master

rpms: ds-rpms lib389-rpms rest389-rpms idm389-rpms svrcore-rpms

srpms-clean:
	rm $(DEVDIR)/rpmbuild/SRPMS/*

srpms: ds-srpms lib389-srpms rest389-srpms idm389-srpms svrcore-srpms

# Is there a nicer way to do this?
copr-wait:
	# Upload all the sprms to copr as builds
	copr-cli build lib389 `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-lib389*.src.rpm | head -n 1`
	copr-cli build rest389 `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-rest389*.src.rpm | head -n 1`
	copr-cli build idm389 `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-idm389*.src.rpm | head -n 1`
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`
	copr-cli build svrcore `ls -1t $(DEVDIR)/rpmbuild/SRPMS/svrcore*.src.rpm | head -n 1`

copr:
	# Upload all the sprms to copr as builds
	copr-cli build lib389 --nowait `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-lib389*.src.rpm | head -n 1`
	copr-cli build rest389 --nowait `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-rest389*.src.rpm | head -n 1`
	copr-cli build idm389 --nowait `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-idm389*.src.rpm | head -n 1`
	copr-cli build ds --nowait `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`
	copr-cli build svrcore --nowait `ls -1t $(DEVDIR)/rpmbuild/SRPMS/svrcore*.src.rpm | head -n 1`

