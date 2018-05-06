#!/bin/bash

export DRUSH="/.composer/vendor/drush/drush/drush"
export LOCAL_IP=$(hostname -I)
export HOSTIP=$(/sbin/ip route | awk '/default/ { print $3 }')
echo "${HOSTIP} dockerhost" >> /etc/hosts

function PrintCreds() {
  # This is so the passwords show up in logs.
  echo
	echo "----GENERATED USERS CREDENTIALS----"
	echo "mysql drupal password: $2"
	echo "mysql root   password: $1"
  echo "ssh   root   password: $1"
	echo "-----------------------------------"
}
# If there is no index.php, download drupal
if [ ! -f /var/www/html/index.php ]; then
  echo "**** No Drupal found. Downloading latest to /var/www/html/ ****"
  cd /var/www/html;
  /.composer/vendor/drush/drush/drush -vy dl drupal \
  --default-major=8 --drupal-project-rename="."
  chmod a+w /var/www/html/sites/default;
  mkdir /var/www/html/sites/default/files;
  chown -R www-data:www-data /var/www/html/
fi

# Create a basic mysql install
if [ ! -d /var/lib/mysql/mysql ]; then
  echo "**** No MySQL data found. Creating data on /var/lib/mysql/ ****"
  /usr/bin/mysql_install_db > /dev/null
fi

# Setup Drupal if settings.php is missing
if [ ! -f /var/www/html/sites/default/settings.php ]; then
	# Start mysql
	/usr/bin/mysqld_safe --skip-syslog &
	sleep 3s
	# Generate random passwords
	DRUPAL_DB="drupal"
	ROOT_PASSWORD=`pwgen -c -n -1 12`
	DRUPAL_PASSWORD=`pwgen -c -n -1 12`
	echo $ROOT_PASSWORD > /var/lib/mysql/mysql/mysql-root-pw.txt
	echo $DRUPAL_PASSWORD > /var/lib/mysql/mysql/drupal-db-pw.txt
  PrintCreds $ROOT_PASSWORD $DRUPAL_PASSWORD
  echo "root:${ROOT_PASSWORD}" | chpasswd
	mysqladmin -u root password $ROOT_PASSWORD
	mysql -uroot -p$ROOT_PASSWORD -e "CREATE DATABASE drupal; GRANT ALL PRIVILEGES ON drupal.* TO 'drupal'@'%' IDENTIFIED BY '$DRUPAL_PASSWORD'; FLUSH PRIVILEGES;"
	cd /var/www/html
	cp sites/default/default.services.yml sites/default/services.yml
	${DRUSH} site-install standard -y --account-name=admin --account-pass=admin \
  --db-url="mysqli://drupal:${DRUPAL_PASSWORD}@localhost:3306/drupal" \
  --site-name="Drupal8 docker App" | grep -v 'continue?'
	${DRUSH} -y dl memcache | grep -v 'continue?'
	${DRUSH} -y en memcache | grep -v 'continue?'
	killall mysqld
	sleep 3s
else
	ROOT_PASSWORD=$(cat /var/lib/mysql/mysql/mysql-root-pw.txt)
	DRUPAL_PASSWORD=$(cat /var/lib/mysql/mysql/drupal-db-pw.txt)
  PrintCreds $ROOT_PASSWORD $DRUPAL_PASSWORD
fi

# Clear caches and reset files perms
chown -fR www-data /var/www/html/sites/default/files/
(sleep 3; drush --root=/var/www/html/ cache-rebuild 2>/dev/null) &

echo
echo "--------------------------STARTING SERVICES-----------------------------------"
# TODO: Show external port from env
echo "SSH    LOGIN: ssh root@${LOCAL_IP} with root  password: ${ROOT_PASSWORD}"
echo "DRUPAL LOGIN: http://${LOCAL_IP}   with admin password: admin"
echo "Please report any issues to https://github.com/ricardoamaro/drupal8-docker-app"
echo "USE CTRL+C TO STOP THIS APP"
echo "------------------------------------------------------------------------------"
supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
