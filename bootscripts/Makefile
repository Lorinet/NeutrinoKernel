VERSION		:= 1.0-pre5

ETCDIR		:= /etc
EXTDIR		:= ${DESTDIR}${ETCDIR}
MODE		:= 754
DIRMODE		:= 755
CONFMODE	:= 644

all:
	@grep "^install" Makefile | cut -d ":" -f 1
	@echo dist
	@echo "Select an appropriate install target from the above list" ; exit 1

dist:
	rm -rf "dist/clfs-embedded-bootscripts-$(VERSION)"
	mkdir -p "dist/clfs-embedded-bootscripts-$(VERSION)"
	tar --exclude dist -c * | tar -x -C "dist/clfs-embedded-bootscripts-$(VERSION)"
	(cd dist; tar -cjf "clfs-embedded-bootscripts-$(VERSION).tar.bz2" "clfs-embedded-bootscripts-$(VERSION)")
	rm -rf "dist/clfs-embedded-bootscripts-$(VERSION)"

create-dirs:
	install -d -m ${DIRMODE} ${EXTDIR}/rc.d/{init.d,start,stop}

install-bootscripts: create-dirs
	install -m ${CONFMODE} clfs/rc.d/init.d/functions ${EXTDIR}/rc.d/init.d/
	install -m ${MODE} clfs/rc.d/startup         ${EXTDIR}/rc.d/
	install -m ${MODE} clfs/rc.d/shutdown        ${EXTDIR}/rc.d/
	install -m ${MODE} clfs/rc.d/init.d/network  ${EXTDIR}/rc.d/init.d/
	install -m ${MODE} clfs/rc.d/init.d/syslog   ${EXTDIR}/rc.d/init.d/
	install -m ${MODE} clfs/rc.d/init.d/bridge   ${EXTDIR}/rc.d/init.d/
	install -m ${MODE} clfs/rc.d/init.d/sshd   ${EXTDIR}/rc.d/init.d/
	ln -sf ../init.d/syslog ${EXTDIR}/rc.d/start/S05syslog
	ln -sf ../init.d/syslog ${EXTDIR}/rc.d/stop/K99syslog
	ln -sf ../init.d/network ${EXTDIR}/rc.d/start/S10network
	ln -sf ../init.d/network ${EXTDIR}/rc.d/stop/K80network
	ln -sf ../init.d/bridge ${EXTDIR}/rc.d/start/S09bridge
	ln -sf ../init.d/bridge ${EXTDIR}/rc.d/stop/K81bridge
	ln -sf ../init.d/sshd ${EXTDIR}/rc.d/start/S50sshd
	ln -sf ../init.d/sshd ${EXTDIR}/rc.d/stop/K51sshd

install-bcm47xx: create-dirs
	install -m ${MODE} clfs/rc.d/init.d/bcm47xx-switch ${EXTDIR}/rc.d/init.d/
	ln -sf ../init.d/bcm47xx-switch ${EXTDIR}/rc.d/start/S08bcm47xx-switch
	ln -sf ../init.d/bcm47xx-switch ${EXTDIR}/rc.d/stop/K82bcm47xx-switch

install-dropbear: create-dirs
	install -m ${MODE} clfs/rc.d/init.d/sshd   ${EXTDIR}/rc.d/init.d/
	ln -sf ../init.d/sshd ${EXTDIR}/rc.d/start/S30sshd
	ln -sf ../init.d/sshd ${EXTDIR}/rc.d/stop/K30sshd

install-hostapd: create-dirs
	install -m ${MODE} clfs/rc.d/init.d/hostapd ${EXTDIR}/rc.d/init.d
	ln -sf ../init.d/hostapd ${EXTDIR}/rc.d/start/S08hostapd
	ln -sf ../init.d/hostapd ${EXTDIR}/rc.d/stop/K82hostapd

.PHONY: dist all create-dirs install install-bcm47xx install-dropbear \
        install-hostapd
