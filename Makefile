
.PHONY: nunc-stans-configure nunc-stans ds-configure ds ds-setup

nunc-stans-configure:
	mkdir -p ~/build/nunc-stans
	cd ~/build/nunc-stans && ~/development/389ds/nunc-stans/configure --prefix=/opt/dirsrv/

nunc-stans:
	make -C ~/build/nunc-stans/
	sudo make -C ~/build/nunc-stans/ install
	sudo cp ./nunc-stans/liblfds/bin/* /opt/dirsrv/lib/

ds-configure:
	mkdir -p ~/build/ds/
	cd ~/build/ds/ && ~/development/389ds/ds/configure --with-openldap --enable-debug --with-nunc-stans=/opt/dirsrv/ --enable-nunc-stans  --prefix=/opt/dirsrv/

ds: nunc-stans ds-configure
	make -C ~/build/ds
	sudo make -C ~/build/ds install

ds-setup: ds
	sudo /opt/dirsrv/sbin/setup-ds.pl --silent --debug --file=./setup.inf General.FullMachineName=$(hostname)


