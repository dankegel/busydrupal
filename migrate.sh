#!/bin/sh
# Simple script to demonstrate migrating calendar data from drupal 6 to drupal 7.
# DO NOT RUN ON SYSTEMS WITH MYSQL OR APACHE2 INSTALLED.  IT WILL NUKE ALL THEIR DATA.

set -e

# Don't use this password if your MySQL server is on the public internet
sqlrootpw="q9z7a1"

# Ubuntu packages we need to install and uninstall in order to
# reproduce everything cleanly.
pkgs="mysql-client mysql-server drush apache2"

workdir=$HOME/migrate-demo.tmp

do_purge() {
    echo "=== Warning, destroying all mysql data ==="
    sudo apt-get remove $pkgs || true
    sudo apt-get purge $pkgs || true
    sudo apt-get autoremove || true
}

do_clean() {
    rm -rf "$workdir" || (chmod -R 755 "$workdir" && rm -rf "$workdir" )
}

do_deps() {
    echo "When prompted, enter $sqlrootpw for the sql root password."
    sleep 4
    sudo apt-get install -y $pkgs
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
    drush -y en date_repeat date_repeat_field date_repeat_instance

    # Some tutorial videos use the admin menu, so install that, too
    drush -y dl admin_menu
    drush -y en admin_menu

    echo "Calendar module enabled.  Now configure it as described in this tutorial:"
    xdg-open http://vimeo.com/6544779
    echo "or this one:"
    xdg-open https://drupal.org/node/1775076
    cat << _EOF_
Then put the block in a region, e.g.
  Site Building > Blocks > List
  "Calendar" > Left Sidebar
  Save Blocks
_EOF_
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

    xdg-open http://www.ostraining.com/blog/drupal/calendar-in-drupal/
    cat << _EOF_
Calendar module enabled.  Now perform the following steps in the gui
to add a calendar view to the left sidebar:

1. Add a view for the calendar
 Structure > Views > Add view from template
 "A calendar view of the 'created' field in the 'comment' base table" > add
 Continue, Save

2. Put the block in a region
 Structure > Blocks
 "View: Calendar" > Sidebar First
 Save Blocks

Opening http://www.ostraining.com/blog/drupal/calendar-in-drupal/
for a more thorough explanation of how to get started with calendars.

Notes:
If you can't seem to enter repeating dates, be aware that
the Date Repeat module has to be enabled before creating
your content type.  (This script should have already done this for you.)

If you get 
"Undefined index: tz in date_ical_date() (line 620 of ../modules/date/date_api/date_api_ical.inc)"
when editing a repeating event, apply the patch from
https://drupal.org/node/1633146
_EOF_
}

usage() {
    echo "Usage: $0 [nuke|deps|install6|install7]"
    echo "Example of how to create a Drupal project in both drupal 6 and 7 and migrate data from 6 to 7."
    echo "DO NOT RUN ON SYSTEMS WITH MYSQL INSTALLED.  IT WILL NUKE ALL MYSQL DATA."
    echo "Run each of the verb in order (e.g. $0 nuke; $0 deps; $0 install6; $0 install7)"
}

set -x
set -e
mkdir -p $workdir
cd $workdir

case $1 in
purge) do_purge;;
clean) do_clean;;
deps) do_deps;;
install6) do_install6;;
install7) do_install7;;
*) usage; exit 1;;
esac
