.PHONY: ds-setup lib389 rest389

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

lib389:
	cd ./lib389/ && python setup.py build
	cd ./lib389/ && sudo python setup.py install --force

lib389-rpmbuild-prep:
	mkdir -p ~/rpmbuild/SOURCES
	mkdir -p ~/rpmbuild/SPECS
	cd ./lib389/ && sudo python setup.py sdist --formats=bztar
	cp ./lib389/dist/*.tar.bz2 ~/rpmbuild/SOURCES/
	# This needs to be less shit, but there is a bug in rename.
	rename 1.tar.bz2 1-1.tar.bz2 ~/rpmbuild/SOURCES/python-lib389*

lib389-srpms: lib389-rpmbuild-prep
	rpmbuild -bs ./lib389/python-lib389.spec
	cp ~/rpmbuild/SRPMS/*.src.rpm ./lib389/dist/

lib389-rpms: lib389-rpmbuild-prep
	rpmbuild -bb ./lib389/python-lib389.spec

nunc-stans-configure:
	mkdir -p ~/build/nunc-stans
	cd ~/build/nunc-stans && ./nunc-stans/configure --prefix=/opt/dirsrv/

nunc-stans: nunc-stans-configure
	make -C ~/build/nunc-stans/
	sudo make -C ~/build/nunc-stans/ install
	sudo cp ./nunc-stans/liblfds/bin/* /opt/dirsrv/lib/

ds-configure:
	cd ./ds && autoreconf
	mkdir -p ~/build/ds/
	cd ~/build/ds/ && ./ds/configure --enable-gcc-security --enable-asan --with-openldap --enable-debug --with-nunc-stans=/opt/dirsrv/ --enable-nunc-stans  --prefix=/opt/dirsrv/

ds: lib389 nunc-stans ds-configure
	make -C ~/build/ds
	sudo make -C ~/build/ds install
	sudo cp ./start-dirsrv-asan /opt/dirsrv/sbin/start-dirsrv

ds-rpms: ds-configure
	make -C ~/build/ds rpms

ds-srpms: ds-configure
	make -C ~/build/ds srpm

ds-setup:
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=./setup.inf General.FullMachineName=$$(hostname)

rest389: lib389
	cd ./rest389/ && python setup.py build
	cd ./rest389/ && sudo python setup.py install --force

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git
	git clone ssh://git.fedorahosted.org/git/nunc-stans.git
	git clone ssh://git.fedorahosted.org/git/389/lib389.git

pull:
	cd ds; git pull
	cd lib389; git pull

github-commit:
	cd ds; git push github --all --force
	cd lib389; git push github --all --force

srpms: ds-srpms lib389-srpms

copr:
	# Upload all the sprms to copr as builds
	copr-cli build --nowait lib389 `ls -1 ./lib389/dist/*.src.rpm | head`
	copr-cli build --nowait ds `ls -1 ./rpmbuild/SRPMS/*.src.rpm | head`


