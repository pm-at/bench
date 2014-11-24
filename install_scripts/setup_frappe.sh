#!/bin/bash

set -e


## Utils

print_msg() {
	echo "Frappe password: $FRAPPE_USER_PASS"
	echo "MariaDB root password: $MSQ_PASS"
	echo "Administrator password: $ADMIN_PASS"
}

get_passwd() {
	echo `cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
}

set_opts () {
	OPTS=`getopt -o v --long verbose,mysql-root-password:,frappe-user:,setup-production,help -n 'parse-options' -- "$@"`
	 
	if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi
	 
	eval set -- "$OPTS"
	 
	VERBOSE=false
	HELP=false
	FRAPPE_USER=false
	FRAPPE_USER_PASS=`get_passwd`
	MSQ_PASS=`get_passwd`
	ADMIN_PASS=`get_passwd`
	SETUP_PROD=false
	 
	while true; do
	case "$1" in
	-v | --verbose ) VERBOSE=true; shift ;;
	-h | --help ) HELP=true; shift ;;
	--mysql-root-password ) MSQ_PASS="$2"; shift; shift ;;
	--frappe-user ) FRAPPE_USER="$2"; shift; shift ;;
	--setup-production ) SETUP_PROD=true; shift;;
	-- ) shift; break ;;
	* ) break ;;
	esac
	done
}

get_distro() {
	ARCH=$(uname -m | sed 's/x86_/amd/;s/i[3-6]86/x86/') 

	if [ $ARCH == "amd64" ]; then
		T_ARCH="x86_64"
		WK_ARCH="amd64"
	else
		T_ARCH="i386"
		WK_ARCH="i386"
	fi 

	if [ -f /etc/redhat-release ]; then
		OS="centos"
		OS_VER=`cat /etc/redhat-release | sed 's/Linux\ //g' | cut -d" " -f3 | cut -d. -f1`

	elif [ -f /etc/lsb-release ]; then
		. /etc/lsb-release
		OS=$DISTRIB_ID
		OS_VER=$DISTRIB_CODENAME

	elif [ -f /etc/debian_version ]; then
		. /etc/os-release
		OS="debian"  # XXX or Ubuntu??
		OS_VER=$VERSION_ID
	fi

	export OS=$OS
	export OS_VER=$OS_VER
	export ARCH=$ARCH
	export T_ARCH=$T_ARCH
	export WK_ARCH=$WK_ARCH
	echo Installing for $OS $OS_VER $ARCH 
	echo "In case you encounter an error, you can post on https://discuss.frappe.io"
	echo
}

run_cmd() {
	if $VERBOSE; then
		"$@"
	else
		# $@ 
		"$@" > /tmp/cmdoutput.txt 2>&1 || (cat /tmp/cmdoutput.txt && exit 1)
	fi
}

## add repos

add_centos6_mariadb_repo() {
	echo "
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/5.5/centos$OS_VER-$ARCH
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
" > /etc/yum.repos.d/mariadb.repo
}
 

add_ubuntu_mariadb_repo() {
	run_cmd sudo apt-get update
	run_cmd sudo apt-get install -y software-properties-common python-software-properties
	run_cmd sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db
	run_cmd sudo add-apt-repository "deb http://ams2.mirrors.digitalocean.com/mariadb/repo/5.5/ubuntu $OS_VER main"
}

add_debian_mariadb_repo() {
	if [ $OS_VER == "7" ]; then
		CODENAME="wheezy"
	
	elif [ $OS_VER == "6" ]; then
		CODENAME="squeeze"
	else
		echo Unsupported Debian Version
		exit 1
	fi

	run_cmd sudo apt-get update
	run_cmd sudo apt-get install -y python-software-properties
	run_cmd sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
	run_cmd sudo add-apt-repository "deb http://ams2.mirrors.digitalocean.com/mariadb/repo/5.5/debian $CODENAME main"
}

add_ius_repo() {
	if [ $OS_VER -eq "6" ]; then
	wget http://dl.iuscommunity.org/pub/ius/stable/CentOS/$OS_VER/$T_ARCH/epel-release-6-5.noarch.rpm
	wget http://dl.iuscommunity.org/pub/ius/stable/CentOS/$OS_VER/$T_ARCH/ius-release-1.0-13.ius.centos6.noarch.rpm
	rpm --quiet -q epel-release || rpm -Uvh epel-release-6-5.noarch.rpm
	rpm --quiet -q ius-release || rpm -Uvh ius-release-1.0-13.ius.centos6.noarch.rpm
	fi
}

add_epel_centos7() {
	yum install -y epel-release
}

add_maria_db_repo() {
	if [ "$OS" == "Ubuntu" ] && [ $VER=="utopic" ]; then 
		return
	elif [ "$OS" == "centos" ]; then
		echo Adding centos mariadb repo
		add_centos6_mariadb_repo
	
	elif [ "$OS" == "debian" ]; then 
		echo Adding debian mariadb repo
		add_debian_mariadb_repo

	elif [ "$OS" == "Ubuntu" ]; then 
		echo Adding debian mariadb repo
		add_ubuntu_mariadb_repo
	else
		echo Unsupported Distribution
		exit 1
	fi
}

## install 

install_packages() {
	if [ $OS == "centos" ]; then
		run_cmd sudo yum install wget -y
		run_cmd sudo yum groupinstall -y "Development tools"
		if [ $OS_VER == "6" ]; then 
			run_cmd add_ius_repo
			run_cmd sudo yum install -y git MariaDB-server MariaDB-client MariaDB-compat python-setuptools nginx zlib-devel bzip2-devel openssl-devel memcached postfix python27-devel python27 libxml2 libxml2-devel libxslt libxslt-devel redis MariaDB-devel libXrender libXext python27-setuptools
		elif [ $OS_VER == "7" ]; then
			run_cmd add_epel_centos7
			run_cmd sudo yum install -y git mariadb-server mariadb-devel python-setuptools nginx zlib-devel bzip2-devel openssl-devel memcached postfix python-devel libxml2 libxml2-devel libxslt libxslt-devel redis libXrender libXext supervisor
		fi
		echo "Installing wkhtmltopdf"
		install_wkhtmltopdf_centos
		run_cmd easy_install-2.7 -U pip
	
	
	elif [ $OS == "debian" ] || [ $OS == "Ubuntu" ]; then 
		export DEBIAN_FRONTEND=noninteractive
		setup_debconf
		run_cmd sudo apt-get update
		run_cmd sudo apt-get install python-dev python-setuptools build-essential python-mysqldb git memcached ntp vim screen htop mariadb-server mariadb-common libmariadbclient-dev  libxslt1.1 libxslt1-dev redis-server libssl-dev libcrypto++-dev postfix nginx supervisor python-pip fontconfig libxrender1 libxext6 -y
		echo "Installing wkhtmltopdf"
		install_wkhtmltopdf_deb

	else
		echo Unsupported Distribution
		exit 1
	fi
}

install_wkhtmltopdf_centos () {

	if [[ $OS == "centos" && $OS_VER == "7" && $T_ARCH="i386" ]]; then
		echo "Cannot install wkhtmltodpdf. Skipping..."
		return 0
	fi
	RPM="wkhtmltox-0.12.1_linux-$OS$OS_VER-$WK_ARCH.rpm"
	run_cmd wget http://downloads.sourceforge.net/project/wkhtmltopdf/0.12.1/$RPM
	rpm --quiet -q wkhtmltox || run_cmd rpm -Uvh $RPM
}

install_wkhtmltopdf_deb () {
	if [[ $OS_VER == "utopic" ]]; then
		echo "Cannot install wkhtmltodpdf. Skipping..."
		return 0
	fi
	if [[ $OS == "debian" &&  $OS_VER == "7" ]]; then
		WK_VER="wheezy"
	else
		WK_VER=$OS_VER
	fi
	run_cmd wget http://downloads.sourceforge.net/project/wkhtmltopdf/0.12.1/wkhtmltox-0.12.1_linux-$WK_VER-$WK_ARCH.deb
	run_cmd dpkg -i wkhtmltox-0.12.1_linux-$WK_VER-$WK_ARCH.deb
}


install_supervisor_centos6() {
		run_cmd easy_install supervisor
		curl -Ss https://raw.githubusercontent.com/pdvyas/supervisor-initscripts/master/redhat-init-jkoppe > /etc/init.d/supervisord
		curl -Ss https://raw.githubusercontent.com/pdvyas/supervisor-initscripts/master/redhat-sysconfig-jkoppe > /etc/sysconfig/supervisord
		curl -Ss https://raw.githubusercontent.com/pdvyas/supervisor-initscripts/master/supervisord.conf > /etc/supervisord.conf
		run_cmd mkdir /etc/supervisor.d
		run_cmd chmod +x /etc/init.d/supervisord
		bash -c "service supervisord start || true"
}

### config

get_mariadb_password() {
	get_password "MariaDB root" MSQ_PASS
}

get_site_admin_password() {
	get_password "Admin password" ADMIN_PASS
}

get_password() {
	if [ -z "$2" ]; then
		read -t 1 -n 10000 discard  || true
		echo
		read -p "Enter $1 password to set:" -s TMP_PASS1
		echo
		read -p "Re enter $1 password to set:" -s TMP_PASS2
		echo
		if [ $TMP_PASS1 == $TMP_PASS2 ]; then
			export $2=$TMP_PASS1
		else
			echo Passwords do not match
			get_password $1 $2
		fi
	fi
}

configure_mariadb_centos() {
	# Required only for CentOS, Ubuntu and Debian will show dpkg configure screen to set the password
	if [ $OS == "centos" ]; then
		mysqladmin -u root password $MSQ_PASS
	fi
}

start_services_centos6() {
	run_cmd service nginx start
	run_cmd service mysql start
	run_cmd service redis start
}

configure_services_centos6() {
	run_cmd chkconfig --add supervisord
	run_cmd chkconfig redis on
	run_cmd chkconfig mysql on
	run_cmd chkconfig nginx on
	run_cmd chkconfig supervisord on
}

configure_services_centos7() {
	run_cmd systemctl enable nginx
	run_cmd systemctl enable mariadb
	run_cmd systemctl enable redis
	run_cmd systemctl enable supervisord
	run_cmd systemctl enable memcached
}

start_services_centos7() {
	run_cmd systemctl start nginx
	run_cmd systemctl start mariadb
	run_cmd systemctl start redis
	run_cmd systemctl start supervisord
	run_cmd systemctl start memcached
}

setup_debconf() {
	debconf-set-selections <<< "postfix postfix/mailname string `hostname`"
	debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
	debconf-set-selections <<< "mariadb-server-5.5 mysql-server/root_password password $MSQ_PASS"
	debconf-set-selections <<< "mariadb-server-5.5 mysql-server/root_password_again password $MSQ_PASS"
}

install_bench() {
	run_cmd sudo su $FRAPPE_USER -c "cd /home/$FRAPPE_USER && git clone https://github.com/frappe/bench bench-repo"
	if hash pip-2.7; then
		PIP="pip-2.7"
	elif hash pip2.7; then
		PIP="pip2.7"
	elif hash pip2; then
		PIP="pip2"
	elif hash pip; then
		PIP="pip"
	else
		echo PIP not installed
		exit 1
	fi
	run_cmd sudo $PIP install -e /home/$FRAPPE_USER/bench-repo
}

setup_bench() {
	echo Installing frappe-bench
	FRAPPE_BRANCH="develop"
	ERPNEXT_APPS_JSON="https://raw.githubusercontent.com/frappe/bench/master/install_scripts/erpnext-apps.json"
	if $SETUP_PROD; then
		FRAPPE_BRANCH="master"
		ERPNEXT_APPS_JSON="https://raw.githubusercontent.com/frappe/bench/master/install_scripts/erpnext-apps-master.json"
	fi
		
	run_cmd sudo su $FRAPPE_USER -c "cd /home/$FRAPPE_USER && bench init frappe-bench --frappe-branch $FRAPPE_BRANCH --apps_path $ERPNEXT_APPS_JSON"
	echo Setting up first site
	echo /home/$FRAPPE_USER/frappe-bench > /etc/frappe_bench_dir
	run_cmd sudo su $FRAPPE_USER -c "cd /home/$FRAPPE_USER/frappe-bench && bench new-site site1.local --mariadb-root-password $MSQ_PASS --admin-password $ADMIN_PASS"
	run_cmd sudo su $FRAPPE_USER -c "cd /home/$FRAPPE_USER/frappe-bench && bench frappe --install_app erpnext"
	run_cmd sudo su $FRAPPE_USER -c "cd /home/$FRAPPE_USER/frappe-bench && bench frappe --install_app shopping_cart"
	run_cmd bash -c "cd /home/$FRAPPE_USER/frappe-bench && bench setup sudoers $FRAPPE_USER"
	if $SETUP_PROD; then
		run_cmd bash -c "cd /home/$FRAPPE_USER/frappe-bench && bench setup production $FRAPPE_USER"
	fi
}

add_user() {
# Check if script is running as root and is not running as sudo. We want to skip
# this step if the user is already running this script with sudo as a non root
# user
	if [ "$FRAPPE_USER" == "false" ]; then
		if [[ $SUDO_UID -eq 0 ]] && [[ $EUID -eq 0 ]]; then
			export FRAPPE_USER="frappe"
		else
			export FRAPPE_USER="$SUDO_USER"
		fi
	fi

	USER_EXISTS=`bash -c "id $FRAPPE_USER > /dev/null 2>&1  && echo true || (echo false && exit 0)"`

	if [ $USER_EXISTS == "false" ]; then
		useradd -m -d /home/$FRAPPE_USER -s $SHELL $FRAPPE_USER
		echo $FRAPPE_USER:$FRAPPE_USER_PASS | chpasswd
		chmod o+x /home/$FRAPPE_USER
		chmod o+r /home/$FRAPPE_USER
	fi
}

main() {
	set_opts $@
	get_distro
	add_maria_db_repo
	echo Installing packages for $OS\. This might take time...
	install_packages
	if [ $OS == "centos" ]; then
		if [ $OS_VER == "6" ]; then
			echo "Installing supervisor"
			install_supervisor_centos6
			echo "Configuring CentOS services"
			configure_services_centos6
			echo "Starting services"
			start_services_centos6
		elif [ $OS_VER == "7" ]; then
			echo "Configuring CentOS services"
			configure_services_centos7
			echo "Starting services"
			start_services_centos7
		fi
		configure_mariadb_centos
	fi
	echo "Adding frappe user"
	add_user
	install_bench
	setup_bench

	echo
	RUNNING=""
	if $SETUP_PROD; then
		RUNNING=" and is running on port 80"
	fi
	echo "Frappe/ERPNext is installed successfully$RUNNING."
	print_msg > ~/frappe_passwords.txt
	print_msg
	echo
	echo "The passwords are also stored at ~/frappe_passwords.txt"
	echo "You can remove this file after making a note of the passwords."
}

main $@
