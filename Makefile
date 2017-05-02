.PHONY: ds-setup lib389 rest389 pyldap

SILENT ?= --enable-silent-rules
DEVDIR ?= $(shell pwd)
BUILDDIR ?= ~/build
LIB389_VERS ?= $(shell cat ./lib389/VERSION | head -n 1)
PYTHON ?= /usr/bin/python
# PYTHON ?= /usr/bin/python3
MAKE ?= make

ASAN ?= true

PKG_CONFIG_PATH ?= /opt/dirsrv/lib/pkgconfig:/usr/local/lib/pkgconfig/

# -Wlogical-op  -Wduplicated-cond  -Wshift-overflow=2  -Wnull-dereference -Wstrict-prototypes

# Removed the --with-systemd flag to work in containers!

ifeq ($(ASAN), true)
# 																																				v-- comment here
ds_cflags = "-march=native -O0 -Wall -Wextra -Wunused -Wmaybe-uninitialized -Wsign-compare -Wstrict-overflow -fno-strict-aliasing -Wunused-but-set-variable -Walloc-size-larger-than=1024 -Walloc-zero -Walloca -Walloca-larger-than=512 -Wbool-operation -Wbuiltin-declaration-mismatch -Wdangling-else -Wduplicate-decl-specifier -Wduplicated-branches -Wexpansion-to-defined -Wformat -Wformat-overflow=2 -Wformat-truncation=2 -Wimplicit-fallthrough=2 -Wint-in-bool-context -Wmemset-elt-size -Wpointer-compare -Wrestrict -Wshadow-compatible-local -Wshadow-local -Wshadow=compatible-local -Wshadow=global -Wshadow=local -Wstringop-overflow=4 -Wswitch-unreachable -Wvla-larger-than=1024"
ds_confflags = --enable-debug --with-svrcore=/opt/dirsrv --enable-gcc-security --enable-asan --enable-cmocka $(SILENT) --with-openldap
# --prefix=/opt/dirsrv 
 #--enable-profiling 
svrcore_cflags = --prefix=/opt/dirsrv --enable-debug --with-systemd --enable-asan $(SILENT)
else
# -flto
ds_cflags = "-march=native -O2 -Wall -Wextra -Wunused -Wmaybe-uninitialized -Wno-sign-compare -Wstrict-overflow -fno-strict-aliasing -Wunused-but-set-variable -g3"
ds_confflags = --with-svrcore=/opt/dirsrv --prefix=/opt/dirsrv --enable-gcc-security --enable-cmocka $(SILENT) #--enable-profiling #--enable-tcmalloc
svrcore_cflags = --prefix=/opt/dirsrv --enable-debug --with-systemd $(SILENT)
endif

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

builddeps-el7:
	sudo yum install -y epel-release
	sudo yum install -y @buildsys-build rpmdevtools git
	sudo yum install -y --skip-broken \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in svrcore/svrcore.spec lib389/python-lib389.spec | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | grep -v "^/" | grep -v pkgversion | sort | uniq|  tr '\n' ' '`

builddeps-fedora:
	sudo dnf upgrade -y
	sudo dnf install -y @buildsys-build rpmdevtools git
	sudo dnf install --setopt=strict=False -y \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | grep -v "^/" | grep -v pkgversion | sort | uniq | tr '\n' ' '`
	sudo dnf builddep --setopt=strict=False -y lib389/python-lib389.spec
	sudo dnf builddep --setopt=strict=False -y svrcore/svrcore.spec

clean: ds-clean svrcore-clean srpms-clean rpms-clean

lib389: pyldap
	$(MAKE) -C $(DEVDIR)/lib389/ build PYTHON=$(PYTHON)
	sudo $(MAKE) -C $(DEVDIR)/lib389/ install PYTHON=$(PYTHON)

lib389-rpmbuild-prep:
	$(MAKE) -C $(DEVDIR)/lib389/ rpmbuild-prep

lib389-srpms: lib389-rpmbuild-prep
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	$(MAKE) -C $(DEVDIR)/lib389/ srpm
	cp $(DEVDIR)/lib389/rpmbuild/SRPMS/python-lib389*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

lib389-rpms: lib389-rpmbuild-prep
	$(MAKE) -C $(DEVDIR)/lib389/ rpm
	cp $(DEVDIR)/lib389/rpmbuild/RPMS/noarch/python*-lib389*.rpm $(DEVDIR)/rpmbuild/RPMS/noarch/

svrcore-configure:
	cd $(DEVDIR)/svrcore/ && autoreconf -fiv
	mkdir -p $(BUILDDIR)/svrcore
	cd $(BUILDDIR)/svrcore && $(DEVDIR)/svrcore/configure $(svrcore_cflags)

svrcore: svrcore-configure
	$(MAKE) -C $(BUILDDIR)/svrcore
	sudo $(MAKE) -C $(BUILDDIR)/svrcore install

svrcore-clean:
	$(MAKE) -C $(BUILDDIR)/svrcore clean; true

svrcore-rpms: svrcore-configure
	$(MAKE) -C $(BUILDDIR)/svrcore rpms
	cp $(BUILDDIR)/svrcore/rpmbuild/RPMS/x86_64/svrcore*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/

svrcore-srpms: svrcore-configure
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	$(MAKE) -C $(BUILDDIR)/svrcore srpm
	cp $(BUILDDIR)/svrcore/rpmbuild/SRPMS/svrcore*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

svrcore-rpms-install:
	sudo yum -y upgrade $(DEVDIR)/rpmbuild/RPMS/x86_64/svrcore*.rpm; true

ds-configure:
	cd $(DEVDIR)/ds && autoreconf -fiv
	mkdir -p $(BUILDDIR)/ds/
	cd $(BUILDDIR)/ds/ && CFLAGS=$(ds_cflags) $(DEVDIR)/ds/configure $(ds_confflags)

ds: lib389 svrcore ds-configure
	$(MAKE) -j8 -C $(BUILDDIR)/ds
	$(MAKE) -j1 -C $(BUILDDIR)/ds check
	sudo $(MAKE) -j1 -C $(BUILDDIR)/ds install
	sudo mkdir -p /opt/dirsrv/etc/sysconfig

ds-rust-clean:
	$(MAKE) -C $(BUILDDIR)/ds_rust clean; true

ds-rust-configure:
	cd $(DEVDIR)/ds_rust && autoreconf -fiv
	mkdir -p $(BUILDDIR)/ds_rust
	cd $(BUILDDIR)/ds_rust/ &&  $(DEVDIR)/ds_rust/configure --prefix=/opt/dirsrv $(SILENT)

ds-rust: ds-rust-configure
	$(MAKE) -C $(BUILDDIR)/ds_rust
	sudo $(MAKE) -C $(BUILDDIR)/ds_rust install

ds-rust-srpms: ds-rust-configure
	$(MAKE) -C $(BUILDDIR)/ds_rust srpms
	cp $(BUILDDIR)/ds_rust/rpmbuild/SRPMS/*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

ds-rust-rpms: ds-rust-configure
	$(MAKE) -C $(BUILDDIR)/ds_rust rpms
	cp $(BUILDDIR)/ds_rust/rpmbuild/RPMS/x86_64/ds-rust* $(DEVDIR)/rpmbuild/RPMS/x86_64/

ds-clean:
	$(MAKE) -C $(BUILDDIR)/ds clean; true

ds-rpms: ds-configure
	mkdir -p $(BUILDDIR)/ds/rpmbuild/SOURCES/
	$(MAKE) -C $(BUILDDIR)/ds rpms
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/x86_64/389-ds-base*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/noarch/*389-ds-base*.rpm $(DEVDIR)/rpmbuild/RPMS/noarch/
	cp $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

ds-srpms: ds-configure
	$(MAKE) -C $(BUILDDIR)/ds srpm
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	cp $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

ds-setup: lib389
	sudo python /usr/sbin/dscreate example > /tmp/ds-setup.inf
	sudo python /usr/sbin/dscreate -v fromfile /tmp/ds-setup.inf --IsolemnlyswearthatIamuptonogood --containerised

ds-setup-py3: lib389
	sudo python3 /usr/sbin/dscreate example > /tmp/ds-setup.inf
	sudo python3 /usr/sbin/dscreate -v fromfile /tmp/ds-setup.inf --IsolemnlyswearthatIamuptonogood --containerised

ds-setup-pl:
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=$(DEVDIR)/setup.inf General.FullMachineName=$$(hostname)

ds-run-nightly:
	sudo py.test -s -v --ignore=ds/dirsrvtests/tests/tickets/ticket47838_test.py ds/dirsrvtests/tests/tickets/ ds/dirsrvtests/tests/suites/

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git
	git clone ssh://git.fedorahosted.org/git/389/lib389.git
	git clone ssh://git@pagure.io/rest389.git
	git clone ssh://git@pagure.io/svrcore.git

clone-anon:
	git clone https://git.fedorahosted.org/git/389/ds.git
	git clone https://git.fedorahosted.org/git/389/lib389.git
	git clone https://pagure.io/rest389.git
	git clone https://pagure.io/svrcore.git

pull:
	cd ds; git pull
	cd lib389; git pull
	cd rest389; git pull
	cd svrcore; git pull

rpms-clean:
	cd $(DEVDIR)/rpmbuild/; find . -name '*.rpm' -exec rm '{}' \; ; true

rpms: svrcore-rpms svrcore-rpms-install lib389-rpms ds-rpms

rpms-install:
	sudo yum install -y $(DEVDIR)/rpmbuild/RPMS/noarch/*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/*.rpm

srpms-clean:
	rm $(BUILDDIR)/svrcore/rpmbuild/SRPMS/svrcore*.src.rpm; true
	rm $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm; true
	rm $(DEVDIR)/lib389/dist/*; true
	rm $(DEVDIR)/rpmbuild/SRPMS/*; true

srpms: ds-srpms lib389-srpms svrcore-srpms

# We need to use the wait version, else the deps aren't ready, and these builds
# are linked!
copr:
	# Upload all the sprms to copr as builds
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/svrcore*.src.rpm | head -n 1`
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/ds-rust-plugins*.src.rpm | head -n 1`
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-lib389*.src.rpm | head -n 1`

copr-echo:
	# Upload all the sprms to copr as builds
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/svrcore*.src.rpm | head -n 1`
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/ds-rust-plugins*.src.rpm | head -n 1`
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/python-lib389*.src.rpm | head -n 1`

