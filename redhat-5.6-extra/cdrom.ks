# Kickstart file automatically generated by anaconda.

install
cdrom
key --skip
lang en_US.UTF-8
keyboard us
text
# crowbar
rootpw --iscrypted $1$H6F/NLec$Fps2Ut0zY4MjJtsa1O2yk0
firewall --disabled
authconfig --enableshadow --enablemd5
selinux --disabled
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda
zerombr yes
ignoredisk --drives=sdb,sdc,sdd,sde,sdf,sdg,sdh,sdi,sdj,sdk,sdl,sdm,sdn,sdo,sdp,sdq,sdr,sds,sdt,sdu,sdv,sdw,sdx,sdy,sdz,hdb,hdc,hdd,hde,hdf,hdg,hdh,hdi,hdj,hdk,hdl,hdm,hdn,hdo,hdp,hdq,hdr,hds,hdt,hdu,hdv,hdw,hdx,hdy,hdz
clearpart --all --drives=sda
part /boot --fstype ext3 --size=100 --ondisk=sda
part swap --recommended
part pv.6 --size=0 --grow --ondisk=sda
volgroup lv_admin --pesize=32768 pv.6
logvol / --fstype ext3 --name=lv_root --vgname=lv_admin --size=1 --grow
reboot

%packages
@base
@core
@editors
@text-internet
keyutils
trousers
fipscheck
device-mapper-multipath
OpenIPMI
OpenIPMI-tools
emacs-nox
openssh
createrepo

%post --nochroot
export PS4='${BASH_SOURCE}@${LINENO}(${FUNCNAME[0]}): '
set -x
(
    ls -al /tmp
    mount
    mount /tmp/cdrom /mnt/sysimage/mnt
    mkdir -p /mnt/sysimage/tftpboot/redhat_dvd/dell
    cp -a /mnt/sysimage/mnt/. /mnt/sysimage/tftpboot/redhat_dvd/.
    umount /mnt/sysimage/mnt
) &>/mnt/sysimage/root/post-install-copy.log

%post
export PS4='${BASH_SOURCE}@${LINENO}(${FUNCNAME[0]}): '
set -x
(
    cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=none
ONBOOT=yes
NETMASK=255.255.255.0
IPADDR=192.168.124.10
GATEWAY=192.168.124.1
TYPE=Ethernet
EOF

    BASEDIR="/tftpboot/redhat_dvd"
    
    (cd /etc/yum.repos.d && rm *)
    
    cat >/etc/yum.repos.d/RHEL5.6-Base.repo <<EOF
[RHEL56-Base]
name=RHEL 5.6 Server
baseurl=file://$BASEDIR/Server
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
    
    cat >/etc/yum.repos.d/crowbar-xtras.repo <<EOF
[crowbar-xtras]
name=Crowbar Extra Packages
baseurl=file://$BASEDIR/extra/pkgs
gpgcheck=0
EOF

# Create the repo metadata we will need

(cd /tftpboot/redhat_dvd/extra/pkgs; createrepo -d -q .)

# We prefer rsyslog.
yum -y install rsyslog
chkconfig syslog off
chkconfig rsyslog on

# Make sure rsyslog picks up our stuff
echo '$IncludeConfig /etc/rsyslog.d/*.conf' >>/etc/rsyslog.conf
mkdir -p /etc/rsyslog.d/

# Make runlevel 3 the default
sed -i -e '/^id/ s/5/3/' /etc/inittab

# Make sure /opt is created
    mkdir -p /opt/dell/bin
    
# Copy the dell parts into a hidden install directory.
    cd /opt
    cp -r /$BASEDIR/dell .dell-install
    
# Make a destination for dell finishing scripts
    
    finishing_scripts=(update_hostname.sh barclamp_install.rb barclamp_create.rb barclamp_inst_lib.rb parse_node_data)
    ( cd /opt/.dell-install; cp "${finishing_scripts[@]}" /opt/dell/bin; )
    
# "Install h2n for named management"
    cd /opt/dell/
    tar -zxf /tftpboot/redhat_dvd/extra/h2n.tar.gz
    ln -s /opt/dell/h2n-2.56/h2n /opt/dell/bin/h2n
    
    cp -r /opt/.dell-install/crowbar_framework /opt/dell
    
# Make a destination for switch configs
    mkdir -p /opt/dell/switch
    cp /opt/.dell-install/*.stk /opt/dell/switch
    
# Install dell code
    cd /opt/.dell-install
    
# put the chef files in place
    cp -r chef /opt/dell
    cp rsyslog.d/* /etc/rsyslog.d/
    
# Barclamp preparation (put them in the right places)
    mkdir /opt/dell/barclamps
    cd barclamps
    for i in *; do
      [[ -d $i ]] || continue
      if [ -e $i/crowbar.yml ]; then
        # MODULAR FORMAT copy to right location (installed by rake barclamp:install)
        cp -r $i /opt/dell/barclamps
        echo "copy new format $i"
      else
        echo "WARNING: item $i found in barclamp directory, but it is not a barclamp!"
      fi
    done
    cd ..

# Make sure the bin directory is executable
    chmod +x /opt/dell/bin/*

# This directory is the model to help users create new barclamps
cp -r barclamp_model /opt/dell
    
# Make sure the ownerships are correct
    chown -R crowbar.admin /opt/dell
    
# Get out of the directories.
    cd 
    
# Look for any crowbar specific kernel parameters
    for s in $(cat /proc/cmdline); do
	VAL=${s#*=} # everything after the first =
	case ${s%%=*} in # everything before the first =
	    crowbar.hostname) CHOSTNAME=$VAL;;
	    crowbar.url) CURL=$VAL;;
	    crowbar.use_serial_console) 
		sed -i "s/\"use_serial_console\": .*,/\"use_serial_console\": $VAL,/" /opt/dell/chef/data_bags/crowbar/bc-template-provisioner.json;;
	    crowbar.debug.logdest) 
		echo "*.*    $VAL" >> /etc/rsyslog.d/00-crowbar-debug.conf
		mkdir -p "$BASEDIR/rsyslog.d"
		echo "*.*    $VAL" >> "$BASEDIR/rsyslog.d/00-crowbar-debug.conf"
		;;
	    crowbar.authkey)
		mkdir -p "/root/.ssh"
		printf "$VAL\n" >>/root/.ssh/authorized_keys
		cp /root/.ssh/authorized_keys "$BASEDIR/authorized_keys"
		;;
	    crowbar.debug)
		sed -i -e '/config.log_level/ s/^#//' \
		    -e '/config.logger.level/ s/^#//' \
		    /opt/dell/crowbar_framework/config/environments/production.rb
		;;
 	esac
    done
    
    if [[ $CHOSTNAME ]]; then
	
	cat > /install_system.sh <<EOF
#!/bin/bash
set -e
cd /tftpboot/redhat_dvd/extra
./install $CHOSTNAME

rm -f /etc/rc2.d/S99install
rm -f /etc/rc3.d/S99install
rm -f /etc/rc5.d/S99install

rm -f /install_system.sh

EOF
	
	chmod +x /install_system.sh
	ln -s /install_system.sh /etc/rc3.d/S99install
	ln -s /install_system.sh /etc/rc5.d/S99install
	ln -s /install_system.sh /etc/rc2.d/S99install
	
    fi
) &>/root/post-install.log
