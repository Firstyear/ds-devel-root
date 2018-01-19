.PHONY: ds-setup

SILENT ?= --enable-silent-rules
DEVDIR ?= $(shell pwd)
BUILDDIR ?= ~/build
PYTHON ?= /usr/bin/python3
MAKE ?= make

ASAN ?= true

PKG_CONFIG_PATH ?= /opt/dirsrv/lib/pkgconfig:/usr/local/lib/pkgconfig/

# Removed the --with-systemd flag to work in containers!

ifeq ($(ASAN), true)
ds_cflags = "-march=native -O0 -Wall -Wextra -Wunused -Wmaybe-uninitialized -Wno-sign-compare -Wstrict-overflow -fno-strict-aliasing -Wunused-but-set-variable -Walloc-zero -Walloca -Walloca-larger-than=512 -Wbool-operation -Wbuiltin-declaration-mismatch -Wdangling-else -Wduplicate-decl-specifier -Wduplicated-branches -Wexpansion-to-defined -Wformat -Wformat-overflow=2 -Wformat-truncation=2 -Wimplicit-fallthrough=2 -Wint-in-bool-context -Wmemset-elt-size -Wpointer-compare -Wrestrict -Wshadow-compatible-local -Wshadow-local -Wshadow=compatible-local -Wshadow=global -Wshadow=local -Wstringop-overflow=4 -Wswitch-unreachable -Wunused-result"
# -Walloc-size-larger-than=1024 -Wvla-larger-than=1024
ds_confflags = --enable-debug --enable-cmocka $(SILENT) --with-openldap --enable-asan --disable-perl --enable-rust
else
# -flto
ds_cflags = "-march=native -O2 -g3"
ds_confflags = --prefix=/opt/dirsrv --enable-gcc-security --enable-cmocka $(SILENT) --enable-rust --with-openldap
endif

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

builddeps-el7:
	sudo yum install -y epel-release
	sudo yum install -y @buildsys-build rpmdevtools git
	sudo yum install -y --skip-broken \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | grep -v "^/" | grep -v pkgversion | sort | uniq|  tr '\n' ' '`

builddeps-fedora:
	sudo dnf upgrade -y
	sudo dnf install -y @buildsys-build rpmdevtools git wget
	sudo dnf install -y ldapvi vim gdb
	sudo dnf install --setopt=strict=False -y \
		`grep -E "^(Build)?Requires" ds/rpm/389-ds-base.spec.in | grep -v -E '(name|MODULE)' | awk '{ print $$2 }' | sed 's/%{python3_pkgversion}/3/g' | grep -v "^/" | grep -v pkgversion | sort | uniq | tr '\n' ' '`

clean: ds-clean srpms-clean rpms-clean

ds-configure:
	cd $(DEVDIR)/ds && autoreconf -fiv
	mkdir -p $(BUILDDIR)/ds/
	cd $(BUILDDIR)/ds/ && CFLAGS=$(ds_cflags) $(DEVDIR)/ds/configure $(ds_confflags)

ds: ds-configure
	PATH="~/.cargo/bin:$$PATH" $(MAKE) -j8 -C $(BUILDDIR)/ds
	$(MAKE) -j1 -C $(BUILDDIR)/ds lib389
	PATH="~/.cargo/bin:$$PATH" $(MAKE) -j1 -C $(BUILDDIR)/ds check
	sudo PATH="~/.cargo/bin:$$PATH" $(MAKE) -j1 -C $(BUILDDIR)/ds install
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
	rm $(BUILDDIR)/ds/rpmbuild/RPMS/*/*.rpm; true
	$(MAKE) -C $(BUILDDIR)/ds rpms
	rm $(DEVDIR)/rpmbuild/RPMS/*.rpm; true
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/x86_64/*.rpm $(DEVDIR)/rpmbuild/RPMS/
	cp $(BUILDDIR)/ds/rpmbuild/RPMS/noarch/*.rpm $(DEVDIR)/rpmbuild/RPMS/
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

ipa-builddeps-fedora: builddeps-fedora
	sudo dnf copr enable -y @freeipa/freeipa-master
	sudo dnf builddep -y -b -D "with_lint 1" --spec freeipa/freeipa.spec.in

ipa-build:
	rm -r freeipa/dist/rpms; true
	cd freeipa; ./makerpms.sh
	sudo dnf install -y freeipa/dist/rpms/*.rpm

ipa-install:
	sudo ipa-server-install -p password -a password -n example.com -r EXAMPLE.COM --hostname=ldapkdc.example.com -U -v -d --no-host-dns

ipa-clean:
	rm freeipa/dist/rpms/*.rpm

ipa-uninstall:
	sudo ipa-server-install -v -d --uninstall -U

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git

clone-anon:
	git clone https://git.fedorahosted.org/git/389/ds.git

pull:
	cd ds; git pull

rpms-clean:
	cd $(DEVDIR)/rpmbuild/; find . -name '*.rpm' -exec rm '{}' \; ; true

rpms: ds-rpms

rpms-install:
	sudo yum install -y $(DEVDIR)/rpmbuild/RPMS/noarch/*.rpm $(DEVDIR)/rpmbuild/RPMS/x86_64/*.rpm

srpms-clean:
	rm $(BUILDDIR)/ds/rpmbuild/SRPMS/*.src.rpm; true
	rm $(DEVDIR)/rpmbuild/SRPMS/*; true

srpms: ds-srpms

# We need to use the wait version, else the deps aren't ready, and these builds
# are linked!
copr:
	# Upload all the sprms to copr as builds
	copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`

copr-echo:
	# Upload all the sprms to copr as builds
	echo copr-cli build ds `ls -1t $(DEVDIR)/rpmbuild/SRPMS/389-ds-base*.src.rpm | head -n 1`

