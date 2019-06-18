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

clean: ds-clean

ds-configure:
	cd $(DEVDIR)/ds && autoreconf -fiv
	mkdir -p $(BUILDDIR)/ds/
	cd $(BUILDDIR)/ds/ && CFLAGS=$(ds_cflags) $(DEVDIR)/ds/configure $(ds_confflags)

ds-python: ds-configure
	$(MAKE) -j1 -C $(BUILDDIR)/ds lib389
	sudo $(MAKE) -j1 -C $(BUILDDIR)/ds lib389-install

ds-build: ds-configure
	PATH="~/.cargo/bin:$$PATH" $(MAKE) -j12 -C $(BUILDDIR)/ds
	$(MAKE) -j1 -C $(BUILDDIR)/ds lib389

ds-test: ds-build
	echo PATH="~/.cargo/bin:$$PATH" $(MAKE) -j1 -C $(BUILDDIR)/ds check
	sudo PATH="~/.cargo/bin:$$PATH" $(MAKE) -j1 -C $(BUILDDIR)/ds check

ds: ds-test
	sudo PATH="~/.cargo/bin:$$PATH" $(MAKE) -j1 -C $(BUILDDIR)/ds install
	sudo $(MAKE) -j1 -C $(BUILDDIR)/ds lib389-install
	sudo mkdir -p /opt/dirsrv/etc/sysconfig
	sudo mkdir -p /opt/dirsrv/etc/dirsrv
	sudo chown -R dirsrv: /opt/dirsrv/etc
	sudo mkdir -p /opt/dirsrv/var/lib/dirsrv/
	sudo mkdir -p /opt/dirsrv/var/lock/dirsrv/
	sudo mkdir -p /opt/dirsrv/var/log/dirsrv/
	sudo mkdir -p /opt/dirsrv/var/run/dirsrv/
	sudo chown -R dirsrv: /opt/dirsrv/var/

ds-rust-clean:
	$(MAKE) -C $(BUILDDIR)/ds_rust clean; true

ds-rust-configure:
	cd $(DEVDIR)/ds_rust && autoreconf -fiv
	mkdir -p $(BUILDDIR)/ds_rust
	cd $(BUILDDIR)/ds_rust/ &&  $(DEVDIR)/ds_rust/configure --prefix=/opt/dirsrv $(SILENT)

ds-rust: ds-rust-configure
	$(MAKE) -C $(BUILDDIR)/ds_rust
	sudo $(MAKE) -C $(BUILDDIR)/ds_rust install

ds-clean:
	$(MAKE) -C $(BUILDDIR)/ds clean; true

ds-setup:
	sudo -u dirsrv /usr/sbin/dscreate create-template --containerized > /tmp/ds-setup.inf
	sudo -u dirsrv /usr/sbin/dscreate -v from-file /tmp/ds-setup.inf --containerized

ds-container-reset:
	sudo rm -r /data; true
	sudo rm -r /logs; true
	sudo rm /opt/dirsrv/etc/sysconfig/dirsrv-localhost; true
	sudo rm /opt/dirsrv/var/run/dirsrv/slapd-localhost.pid; true

ds-container-prep:
	sudo mkdir -p /data/
	sudo rm -f /opt/dirsrv/etc/dirsrv/slapd-localhost /opt/dirsrv/etc/dirsrv/ssca
	sudo ln -s /data/config /opt/dirsrv/etc/dirsrv/slapd-localhost
	sudo ln -s /data/ssca /opt/dirsrv/etc/dirsrv/ssca
	sudo chown -R dirsrv: /data

	# sudo ln -s /data/db /opt/dirsrv/var/lib/dirsrv/slapd-localhost
	# sudo ln -s /logs /opt/dirsrv/var/log/dirsrv/slapd-localhost

ds-container: ds-container-prep
	sudo -u dirsrv /usr/sbin/dscontainer -r

# DEBUGSETUP=True
ds-run-test:
	sudo -u dirsrv DEBUGGING=True py.test $(TEST_OPT) -s -v ds/dirsrvtests/tests/$(TEST)

ds-run-nightly:
	sudo -u dirsrv py.test -x -s -v ds/dirsrvtests/tests/tickets/ ds/dirsrvtests/tests/suites/

