.PHONY: ds-setup lib389 rest389

SILENT ?= --enable-silent-rules
DEVDIR ?= $(shell pwd)
BUILDDIR ?= ~/build
LIB389_VERS ?= $(shell cat ./lib389/VERSION | head -n 1)
PYTHON ?= /usr/bin/python3
MAKE ?= make

ASAN ?= true

PKG_CONFIG_PATH ?= /opt/dirsrv/lib/pkgconfig:/usr/local/lib/pkgconfig/

# Removed the --with-systemd flag to work in containers!

ifeq ($(ASAN), true)
ds_cflags = "-march=native -O0 -Wall -Wextra -Wunused -Wmaybe-uninitialized -Wno-sign-compare -Wstrict-overflow -fno-strict-aliasing -Wunused-but-set-variable -Walloc-zero -Walloca -Walloca-larger-than=512 -Wbool-operation -Wbuiltin-declaration-mismatch -Wdangling-else -Wduplicate-decl-specifier -Wduplicated-branches -Wexpansion-to-defined -Wformat -Wformat-overflow=2 -Wformat-truncation=2 -Wimplicit-fallthrough=2 -Wint-in-bool-context -Wmemset-elt-size -Wpointer-compare -Wrestrict -Wshadow-compatible-local -Wshadow-local -Wshadow=compatible-local -Wshadow=global -Wshadow=local -Wstringop-overflow=4 -Wswitch-unreachable -Wunused-result"
# -Walloc-size-larger-than=1024 -Wvla-larger-than=1024
ds_confflags = --enable-debug --with-svrcore=/opt/dirsrv --enable-gcc-security --enable-cmocka $(SILENT) --with-openldap --enable-asan --enable-rust
# --disable-perl
 #--enable-profiling
svrcore_cflags = --prefix=/opt/dirsrv --enable-debug --with-systemd $(SILENT) --enable-asan
else
# -flto
ds_cflags = "-march=native -O2 -g3"
ds_confflags = --with-svrcore=/opt/dirsrv --prefix=/opt/dirsrv --enable-gcc-security --enable-cmocka $(SILENT) --enable-rust --with-openldap
#--enable-profiling --enable-tcmalloc
svrcore_cflags = --prefix=/opt/dirsrv --enable-debug --with-systemd $(SILENT)
endif

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

rustup:
	if [ ! -f ./rustup-init ]; then \
		wget https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init && \
		chmod +x ./rustup-init; \
	fi
	./rustup-init --default-toolchain nightly -y
	echo run source ~/.profile

builddeps-el7: rustup
	sudo yum install -y epel-release
	sudo yum install -y @buildsys-build rpmdevtools git
	sudo yum install -y --skip-broken \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in svrcore/svrcore.spec | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | grep -v "^/" | grep -v pkgversion | sort | uniq|  tr '\n' ' '`

builddeps-fedora: rustup
	sudo dnf upgrade -y
	sudo dnf install -y @buildsys-build rpmdevtools git wget
	sudo dnf install --setopt=strict=False -y \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | sed 's/%{python3_pkgversion}/3/g' | grep -v "^/" | grep -v pkgversion | sort | uniq | tr '\n' ' '`

clean: ds-clean svrcore-clean srpms-clean rpms-clean

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
	sudo yum -C -y upgrade $(DEVDIR)/rpmbuild/RPMS/x86_64/svrcore*.rpm; true

ds-configure:
	cd $(DEVDIR)/ds && autoreconf -fiv
	mkdir -p $(BUILDDIR)/ds/
	cd $(BUILDDIR)/ds/ && CFLAGS=$(ds_cflags) $(DEVDIR)/ds/configure $(ds_confflags)

ds: lib389 svrcore ds-configure
	$(MAKE) -j8 -C $(BUILDDIR)/ds
	$(MAKE) -j1 -C $(BUILDDIR)/ds lib389
	$(MAKE) -j1 -C $(BUILDDIR)/ds check
	sudo $(MAKE) -j1 -C $(BUILDDIR)/ds install
	sudo $(MAKE) -j1 -C $(BUILDDIR)/ds lib389-install
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
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/x86_64/*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/noarch/*.rpm $(DEVDIR)/rpmbuild/RPMS/noarch/
	cp $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

ds-srpms: ds-configure
	$(MAKE) -C $(BUILDDIR)/ds srpm
	mkdir -p $(DEVDIR)/rpmbuild/SRPMS/
	cp $(BUILDDIR)/ds/rpmbuild/SRPMS/389-ds-base*.src.rpm $(DEVDIR)/rpmbuild/SRPMS/

ds-setup:
	sudo /usr/sbin/dscreate example > /tmp/ds-setup.inf
	sudo /usr/sbin/dscreate -v fromfile /tmp/ds-setup.inf --IsolemnlyswearthatIamuptonogood --containerised

ds-setup-pl:
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=$(DEVDIR)/setup.inf General.FullMachineName=$$(hostname)

ds-run-nightly:
	sudo py.test -s -v ds/dirsrvtests/tests/tickets/ ds/dirsrvtests/tests/suites/

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git
	git clone ssh://git@pagure.io/rest389.git
	git clone ssh://git@pagure.io/svrcore.git

clone-anon:
	git clone https://git.fedorahosted.org/git/389/ds.git
	git clone https://pagure.io/rest389.git
	git clone https://pagure.io/svrcore.git

pull:
	cd ds; git pull
	cd lib389; git pull
	cd rest389; git pull
	cd svrcore; git pull

rpms-clean:
	cd $(DEVDIR)/rpmbuild/; find . -name '*.rpm' -exec rm '{}' \; ; true

rpms: svrcore-rpms svrcore-rpms-install ds-rpms

rpms-install:
	sudo yum install -y $(DEVDIR)/rpmbuild/RPMS/noarch/*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/*.rpm

srpms-clean:
	rm $(BUILDDIR)/svrcore/rpmbuild/SRPMS/svrcore*.src.rpm; true
	rm $(BUILDDIR)/ds/rpmbuild/SRPMS/*.src.rpm; true
	rm $(DEVDIR)/rpmbuild/SRPMS/*; true

srpms: ds-srpms svrcore-srpms

# We need to use the wait version, else the deps aren't ready, and these builds
# are linked!
copr:
	# Upload all the sprms to copr as builds
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/svrcore*.src.rpm | head -n 1`
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/ds-rust-plugins*.src.rpm | head -n 1`

copr-echo:
	# Upload all the sprms to copr as builds
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/svrcore*.src.rpm | head -n 1`
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/ds-rust-plugins*.src.rpm | head -n 1`

