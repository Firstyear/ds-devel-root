.PHONY: ds-setup lib389

all:
	echo "make ds|nunc-stans|lib389|ds-setup"

lib389:
	cd ~/development/389ds/lib389/ && python setup.py build
	cd ~/development/389ds/lib389/ && sudo python setup.py install

nunc-stans-configure:
	mkdir -p ~/build/nunc-stans
	cd ~/build/nunc-stans && ~/development/389ds/nunc-stans/configure --prefix=/opt/dirsrv/

nunc-stans: nunc-stans-configure
	make -C ~/build/nunc-stans/
	sudo make -C ~/build/nunc-stans/ install
	sudo cp ./nunc-stans/liblfds/bin/* /opt/dirsrv/lib/

ds-configure:
	mkdir -p ~/build/ds/
	cd ~/build/ds/ && ~/development/389ds/ds/configure --enable-gcc-security --enable-asan --with-openldap --enable-debug --with-nunc-stans=/opt/dirsrv/ --enable-nunc-stans  --prefix=/opt/dirsrv/

ds: lib389 nunc-stans ds-configure
	make -C ~/build/ds
	sudo make -C ~/build/ds install
	sudo cp ~/development/389ds/start-dirsrv-asan /opt/dirsrv/sbin/start-dirsrv

ds-setup:
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=./setup.inf General.FullMachineName=$$(hostname)

clone:
	git clone ssh://git.fedorahosted.org/git/389/ds.git
	git clone ssh://git.fedorahosted.org/git/nunc-stans.git
	git clone ssh://git.fedorahosted.org/git/389/lib389.git


