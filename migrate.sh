#!/bin/sh
# Simple script to demonstrate migrating calendar data from drupal 6 to drupal 7.
# Written for Ubuntu 14.04, might need adjusting to run on other systems.
# DO NOT RUN ON SYSTEMS WITH MYSQL OR APACHE2 INSTALLED.  IT WILL NUKE ALL THEIR DATA.

set -e

# Don't use this password if your MySQL server is on the public internet
sqlrootpw="q9z7a1"

# Ubuntu packages we need to install and uninstall in order to
# reproduce everything cleanly.
pkgs="mysql-client mysql-server drush apache2 libapache2-mod-php5"

workdir=$HOME/migrate-demo.tmp

do_undeps() {
    echo "=== Warning, destroying all mysql data ==="
    sudo apt-get remove $pkgs || true
    sudo apt-get purge $pkgs || true
    sudo apt-get autoremove || true
}

do_clean() {
    rm -rf "$workdir" 2> /dev/null || (chmod -R 755 "$workdir" && rm -rf "$workdir" )
    sudo rm -f /etc/apache2/sites-*/migrate-demo*
}

do_deps() {
    echo "When prompted, enter $sqlrootpw for the sql root password."
    sleep 4
    sudo apt-get install -y $pkgs
    sudo a2enmod rewrite
    sudo service apache2 restart
}

# Usage: my_download url filename
my_download_and_unpack() {
    _mycdir=$HOME/.cache/migrate-demo
    if ! test -f $_mycdir/$2
    then
        ( mkdir -p $_mycdir; cd $_mycdir; wget $1 )
    fi
    tar -xf $_mycdir/$2
}

my_enable_site() {
    major=`echo $dir | sed 's/drupal-//;s/\..*//'`
    cat > migrate-demo-drupal$major.conf <<_EOF_
<VirtualHost *:80>
	ServerName drupal$major

	ServerAdmin webmaster@localhost
	DocumentRoot $workdir/$dir
	ErrorLog \${APACHE_LOG_DIR}/error.log
	CustomLog \${APACHE_LOG_DIR}/access.log combined
	<Directory $workdir/$dir>
		Options Indexes FollowSymLinks
		AllowOverride None
		Require all granted
	</Directory>
</VirtualHost>
_EOF_
    sudo cp -f migrate-demo-drupal$major.conf /etc/apache2/sites-available
    sudo ln -sf ../sites-available/migrate-demo-drupal$major.conf /etc/apache2/sites-enabled
    sudo service apache2 restart
    echo "127.0.0.1  drupal$major" | sudo tee -a /etc/hosts

    echo "Opening drupal$major site in your browser"
    xdg-open http://drupal$major
}

do_install6() {
    dir=drupal-6.35
    my_download_and_unpack http://ftp.drupal.org/files/projects/$dir.tar.gz $dir.tar.gz
    cd $dir

    # Note: older versions of drush didn't need the 'standard' word
    drush si default --site-name=site6 --db-url=mysql://root:$sqlrootpw@localhost/drupal6 --account-name=drupal --account-pass=drupal

    # FIXME: This is insecure, but required to pass the status report tests
    chmod 777 sites/default/files

    # Home page: https://drupal.org/project/calendar
    # See related tutorials:
    #  http://vimeo.com/6544779
    #  http://gotdrupal.com/videos/drupal-calendar

    # Date Popup requires jquery_ui, but the command
    #   "drush dl jquery_ui; drush en jquery_ui"
    # will fail with message
    #   "Module jquery_ui doesn't meet the requirements to be enabled.
    #   The jQuery UI plugin is missing. Download and extract it
    #   into the sites/all/libraries directory. Rename the extracted
    #   folder to jquery.ui. (Currently using jQuery UI Not found)"
    # so do that first.
    mkdir -p sites/all/libraries
    (cd sites/all/libraries; my_download_and_unpack https://github.com/jquery/jquery-ui/archive/1.6.tar.gz 1.6.tar.gz )
    mv sites/all/libraries/jquery-ui-1.6/ sites/all/libraries/jquery.ui

    drush -y dl jquerymenu-6.x-3.3 cck views date jquery_ui calendar
    drush -y en views views_ui date date_popup jquery_ui calendar

    # For repeating dates, need a bit more
    drush -y dl date_repeat_instance
    drush -y en date_repeat date_repeat_instance

    # Some tutorial videos use the admin menu, so install that, too
    drush -y dl admin_menu
    drush -y en admin_menu

    # Enable the site in apache
    my_enable_site

    cat << _EOF_
Calendar module enabled.
Opening a tutorial or two in your browser
for an explanation of how to get started with calendars.

Follow them to create an Event content type, then
add a calendar view to the left sidebar, e.g.
1.  Put the block in a region, e.g.
  Site Building > Blocks > List
  "Calendar" > Left Sidebar
  Save Blocks

_EOF_
    xdg-open https://drupal.org/node/1775076
    xdg-open http://vimeo.com/6544779
}

do_install7() {
    dir=drupal-7.36
    my_download_and_unpack http://ftp.drupal.org/files/projects/$dir.tar.gz $dir.tar.gz
    cd $dir

    # Note: older versions of drush didn't need the 'standard' word
    drush si standard --site-name=site7 --db-url=mysql://root:$sqlrootpw@localhost/drupal7 --account-name=drupal --account-pass=drupal

    # FIXME: This is insecure, but required to pass the status report tests
    chmod 777 sites/default/files

    echo Home page: https://drupal.org/project/calendar
    echo See related tutorials:
    echo  https://drupal.org/node/1477602
    echo  http://www.ostraining.com/blog/drupal/calendar-in-drupal/
    echo  http://drupalize.me/series/calendars-drupal-7

    drush -y dl ctools views date calendar
    drush -y en ctools views views_ui date date_popup calendar

    # For repeating dates, need a bit more
    drush -y dl date_repeat_instance
    drush -y en date_repeat date_repeat_field date_repeat_instance

    # Enable the site in apache
    my_enable_site

    cat << _EOF_
Calendar module enabled.
Opening a tutorial or two in your browser
for an explanation of how to get started with calendars.

Follow them to create an Event content type, then
add a calendar view to the left sidebar, e.g.

1. Add a view for the calendar
 Structure > Views > Add view from template
 "A calendar view of the 'created' field in the 'comment' base table" > add
 Continue, Save

2. Put the block in a region
 Structure > Blocks
 "View: Calendar" > Sidebar First
 Save Blocks

Notes:
If you can't seem to enter repeating dates, be aware that
the Date Repeat module has to be enabled before creating
your content type.  (This script should have already done this for you.)

If you get
"Undefined index: tz in date_ical_date() (line 620 of ../modules/date/date_api/date_api_ical.inc)"
when editing a repeating event, apply the patch from
https://drupal.org/node/1633146
_EOF_
    xdg-open https://www.drupal.org/node/1250714
    xdg-open http://www.ostraining.com/blog/drupal/calendar-in-drupal/
}

usage() {
    echo "Usage: $0 [undeps|deps|clean|install6|install7]"
    echo "Example of how to create a Drupal project in both drupal 6 and 7 and migrate data from 6 to 7."
    echo "DO NOT RUN ON SYSTEMS WITH MYSQL INSTALLED.  IT WILL NUKE ALL MYSQL DATA."
    echo "Run each of the verb in order (e.g. $0 undeps; $0 deps; $0 clean; $0 install6; $0 install7)"
}

set -x
set -e
mkdir -p $workdir
cd $workdir

case $1 in
undeps) do_undeps;;
clean) do_clean;;
deps) do_deps;;
install6) do_install6;;
install7) do_install7;;
*) usage; exit 1;;
esac
